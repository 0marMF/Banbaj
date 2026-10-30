/* =====================================================================
   Banbaj · 80 Migración inicial desde los DBF (una sola vez)
   ---------------------------------------------------------------------
   Sustituye a tools/migrar_dbf.py: todo corre en SQL Server.

   1. En FoxPro, exportar cada DBF a CSV con cyber/486/EXPORTAR_MIGRACION.prg
      (deja C:\MIGRA486\<FUENTE>.csv: DAT, TAB7, HISTORIA, PAGTOT, ETI, DM1, TOP,
      STATUS, EXC486, DIRMAL, EMAILMALO, BLACKLIST, TELBAJ, LADA, PNC).
      La carpeta debe ser visible para el servicio de SQL Server.
   2. Revisar (no escribe nada):   EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';
   3. Cargar:                      EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;
      Si los destinos ya tienen datos hay que pedir @reemplazar = 1.
      @solo = N'DAT,HISTORIA,…' limita los destinos.
   4. Borrar los CSV de C:\MIGRA486 (traen datos de clientes).

   Destinos (en una sola transacción; si algo falla no queda nada a medias):
     DAT          DAT.csv                              -> dat.DAT_486
     HISTORIA     DAT.csv (activas)                    -> dat.HISTORIA_FOLIO   (PURGA y DEVOL no se migran)
     CONSECUTIVO  máximo folio de TAB7, DAT e HISTORIA -> dat.FOLIO_CONSECUTIVO
     PAGOS        PAGTOT.csv (CUENTA, FE_PAG, MONT)    -> dat.PAGO_ARRIBADO
     ETIQUETAS    ETI, DM1, TOP, STATUS                -> cfg.ETIQUETA
     EXCLUSIONES  EXC486, DIRMAL, EMAILMALO, BLACKLIST (10 dígitos), TELBAJ -> cfg.EXCLUSION
     LADA         LADA.csv                             -> cfg.LADA
     PNC          PNC.csv                              -> cfg.PLAN_NUMERACION
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Lee un CSV con encabezado a stg.MIG_<fuente> (todas las columnas NVARCHAR, FILA = orden del archivo).
   @n = -1 si el archivo no existe. */
CREATE OR ALTER PROCEDURE ops.sp_mig_leer
    @fuente   SYSNAME,
    @archivo  NVARCHAR(500),
    @codepage VARCHAR(10) = 'ACP',
    @n        INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX), @hdr NVARCHAR(4000), @tabla NVARCHAR(200) = N'stg.' + QUOTENAME(N'MIG_' + @fuente),
            @vista NVARCHAR(200) = N'stg.' + QUOTENAME(N'vMIG_' + @fuente), @ultima SYSNAME,
            @cp NVARCHAR(100) = CASE WHEN NULLIF(@codepage, '') IS NOT NULL THEN N', CODEPAGE = ' + QUOTENAME(@codepage, '''') ELSE N'' END;
    SET @n = -1;
    EXEC (N'DROP VIEW IF EXISTS ' + @vista + N'; DROP TABLE IF EXISTS ' + @tabla + N';');

    CREATE TABLE #h (L NVARCHAR(4000));
    SET @sql = N'BULK INSERT #h FROM ' + QUOTENAME(@archivo, '''') + N' WITH (FIRSTROW = 1, LASTROW = 1, ROWTERMINATOR = ''0x0a'', FIELDTERMINATOR = ''\t\t\t''' + @cp + N');';
    BEGIN TRY
        EXEC (@sql);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (4860, 4861, 12704) RETURN;          -- el archivo no existe
        THROW;
    END CATCH;
    SELECT @hdr = REPLACE(REPLACE(REPLACE(L, NCHAR(13), N''), N'"', N''), NCHAR(65279), N'') FROM #h;
    IF NULLIF(LTRIM(@hdr), N'') IS NULL BEGIN SET @n = 0; RETURN; END;

    SELECT CAST([key] AS INT) + 1 AS POS, UPPER(LTRIM(RTRIM([value]))) AS CAMPO
    INTO #c FROM OPENJSON(N'["' + REPLACE(STRING_ESCAPE(@hdr, 'json'), N',', N'","') + N'"]');
    UPDATE #c SET CAMPO = CONCAT(N'COL_', POS) WHERE CAMPO = N'';
    ;WITH r AS (SELECT CAMPO, ROW_NUMBER() OVER (PARTITION BY CAMPO ORDER BY POS) AS RN FROM #c)
    UPDATE r SET CAMPO = CONCAT(CAMPO, N'_', RN) WHERE RN > 1;
    SELECT @ultima = CAMPO FROM #c WHERE POS = (SELECT MAX(POS) FROM #c);

    SET @sql = N'CREATE TABLE ' + @tabla + N' (FILA INT IDENTITY(1,1) NOT NULL, '
             + (SELECT STRING_AGG(CAST(QUOTENAME(CAMPO) + N' NVARCHAR(4000) NULL' AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY POS) FROM #c) + N');';
    EXEC (@sql);
    SET @sql = N'CREATE VIEW ' + @vista + N' AS SELECT '
             + (SELECT STRING_AGG(CAST(QUOTENAME(CAMPO) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY POS) FROM #c) + N' FROM ' + @tabla + N';';
    EXEC (@sql);
    SET @sql = N'BULK INSERT ' + @vista + N' FROM ' + QUOTENAME(@archivo, '''')
             + N' WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', TABLOCK' + @cp + N');';
    EXEC (@sql);
    SET @sql = N'UPDATE ' + @tabla + N' SET ' + QUOTENAME(@ultima) + N' = REPLACE(' + QUOTENAME(@ultima) + N', NCHAR(13), N''''); SELECT @n = COUNT(*) FROM ' + @tabla + N';';
    EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @n OUTPUT;
    EXEC (N'DROP VIEW ' + @vista + N';');
END;
GO

/* ¿La tabla stg.MIG_<fuente> existe y trae estas columnas? Si no: aviso o error */
CREATE OR ALTER FUNCTION ops.fn_mig_faltan (@fuente SYSNAME, @columnas NVARCHAR(400))
RETURNS NVARCHAR(400)
AS
BEGIN
    RETURN (SELECT STRING_AGG(LTRIM(RTRIM(value)), N', ') FROM STRING_SPLIT(@columnas, N',')
            WHERE COL_LENGTH(N'stg.MIG_' + @fuente, LTRIM(RTRIM(value))) IS NULL);
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_migrar_486
    @carpeta    NVARCHAR(400) = N'C:\MIGRA486\',
    @confirmar  BIT           = 0,
    @reemplazar BIT           = 0,
    @solo       NVARCHAR(200) = NULL,
    @codepage   VARCHAR(10)   = 'ACP',          -- '' en SQL Server Linux
    @cliente    VARCHAR(10)   = '486'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @sql NVARCHAR(MAX), @n INT, @f SYSNAME, @msg NVARCHAR(4000), @falta NVARCHAR(400), @ruta NVARCHAR(500), @mig VARCHAR(40) = 'MIGRACION DBF';
    IF RIGHT(@carpeta, 1) NOT IN (N'\', N'/') SET @carpeta += CASE WHEN @carpeta LIKE N'/%' THEN N'/' ELSE N'\' END;

    DECLARE @dest TABLE (D VARCHAR(20) PRIMARY KEY);
    INSERT INTO @dest SELECT value FROM STRING_SPLIT('DAT,HISTORIA,CONSECUTIVO,PAGOS,ETIQUETAS,EXCLUSIONES,LADA,PNC', ',')
    WHERE @solo IS NULL OR value IN (SELECT UPPER(LTRIM(RTRIM(s.value))) FROM STRING_SPLIT(@solo, ',') s);
    CREATE TABLE #aviso (ID INT IDENTITY(1,1), TEXTO NVARCHAR(1000));
    CREATE TABLE #fuente (FUENTE SYSNAME PRIMARY KEY, FILAS INT);

    BEGIN TRY
    /* 1. Leer los CSV */
    DECLARE cf CURSOR LOCAL FAST_FORWARD FOR
        SELECT value FROM STRING_SPLIT('DAT,TAB7,HISTORIA,PAGTOT,ETI,DM1,TOP,STATUS,EXC486,DIRMAL,EMAILMALO,BLACKLIST,TELBAJ,LADA,PNC', ',');
    OPEN cf; FETCH NEXT FROM cf INTO @f;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @ruta = @carpeta + @f + N'.csv';
        EXEC ops.sp_mig_leer @f, @ruta, @codepage, @n OUTPUT;
        INSERT INTO #fuente VALUES (@f, @n);
        FETCH NEXT FROM cf INTO @f;
    END;
    CLOSE cf; DEALLOCATE cf;
    DECLARE @hay TABLE (F SYSNAME PRIMARY KEY);
    INSERT INTO @hay SELECT FUENTE FROM #fuente WHERE FILAS >= 0;

    /* 2. Transformar a tablas temporales con la forma del destino */
    SELECT TOP (0) * INTO #d_dat FROM dat.DAT_486;
    SELECT TOP (0) CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA INTO #d_hist FROM dat.HISTORIA_FOLIO;
    CREATE TABLE #d_cons (CLIENTE VARCHAR(10), ULTIMO_FOLIO INT);
    CREATE TABLE #d_pag (CLIENTE VARCHAR(10), CUENTA VARCHAR(25), FE_PAG DATE, IMPORTE DECIMAL(15,2), FE_REG DATE, ID_CORRIDA INT, ORIGEN VARCHAR(10));
    CREATE TABLE #d_eti (CLIENTE VARCHAR(10), TIPO VARCHAR(20), LLAVE VARCHAR(30), VALOR NVARCHAR(100));
    CREATE TABLE #eti_tipos (TIPO VARCHAR(20));
    CREATE TABLE #d_exc (CLIENTE VARCHAR(10), TIPO VARCHAR(20), VALOR NVARCHAR(200), VALOR2 NVARCHAR(200), MOTIVO NVARCHAR(200), REQ VARCHAR(40));
    CREATE TABLE #d_lada (CP CHAR(5), LADA VARCHAR(5));
    CREATE TABLE #d_pnc (LADA VARCHAR(3), SERIE VARCHAR(4), N_INI INT, N_FIN INT, TIPORED VARCHAR(10));
    CREATE TABLE #cuentas (C NVARCHAR(100) PRIMARY KEY);

    -- DAT
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'DAT')
    BEGIN
        SET @falta = ops.fn_mig_faltan('DAT', N'CUENTA, FOLIO, CUENTA2');
        IF @falta IS NOT NULL BEGIN SET @msg = CONCAT(N'DAT.csv: faltan las columnas ', @falta); THROW 50900, @msg, 1; END;
        SELECT @sql = N'INSERT INTO #d_dat (' + STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ') + N') SELECT '
                    + STRING_AGG(CAST(
                        CASE WHEN t.name IN ('decimal', 'numeric', 'int', 'bigint', 'smallint', 'money')
                                  THEN N'TRY_CONVERT(' + t.name + CASE WHEN t.name IN ('decimal', 'numeric') THEN CONCAT(N'(', c.precision, N',', c.scale, N')') ELSE N'' END
                                       + N', REPLACE(cfg.fn_texto(m.' + QUOTENAME(c.name) + N'), N'','', N''''))'
                             WHEN t.name IN ('date', 'datetime', 'datetime2', 'smalldatetime')
                                  THEN N'COALESCE(TRY_CONVERT(DATE, cfg.fn_texto(m.' + QUOTENAME(c.name) + N'), 112), TRY_CONVERT(DATE, cfg.fn_texto(m.' + QUOTENAME(c.name)
                                       + N'), 23), TRY_CONVERT(DATE, cfg.fn_texto(m.' + QUOTENAME(c.name) + N'), 101))'
                             ELSE N'LEFT(cfg.fn_texto(m.' + QUOTENAME(c.name) + N'), ' + CAST(CASE WHEN c.max_length < 0 THEN 4000 WHEN t.name LIKE 'n%' THEN c.max_length / 2 ELSE c.max_length END AS NVARCHAR(10)) + N')'
                        END AS NVARCHAR(MAX)), N', ')
                    + N' FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY cfg.fn_texto(CUENTA) ORDER BY FILA) AS RN_MIG FROM stg.MIG_DAT) m'
                    + N' WHERE cfg.fn_texto(m.CUENTA) IS NOT NULL AND m.RN_MIG = 1;'
        FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
        WHERE c.object_id = OBJECT_ID('dat.DAT_486') AND COL_LENGTH('stg.MIG_DAT', c.name) IS NOT NULL;
        EXEC (@sql);
        DECLARE @sin_cuenta INT, @repetidas INT;
        SELECT @sin_cuenta = SUM(CASE WHEN cfg.fn_texto(CUENTA) IS NULL THEN 1 ELSE 0 END),
               @repetidas = COUNT(cfg.fn_texto(CUENTA)) - COUNT(DISTINCT cfg.fn_texto(CUENTA))
        FROM stg.MIG_DAT;
        IF @sin_cuenta > 0 INSERT INTO #aviso (TEXTO) VALUES (CONCAT(N'DAT: ', @sin_cuenta, N' registros sin CUENTA omitidos'));
        IF @repetidas > 0 INSERT INTO #aviso (TEXTO) VALUES (CONCAT(N'DAT: ', @repetidas, N' registros con CUENTA repetida omitidos (se queda el primero)'));
        INSERT INTO #aviso (TEXTO)
        SELECT CONCAT(N'DAT: columnas del archivo que no existen en dat.DAT_486 (se ignoran): ', STRING_AGG(c.name, N', '))
        FROM sys.columns c WHERE c.object_id = OBJECT_ID('stg.MIG_DAT') AND c.name <> 'FILA' AND COL_LENGTH('dat.DAT_486', c.name) IS NULL
        HAVING COUNT(*) > 0;
        INSERT INTO #cuentas SELECT DISTINCT C FROM (SELECT CUENTA AS C FROM #d_dat UNION SELECT CUENTA2 FROM #d_dat) x WHERE C IS NOT NULL;

        -- HISTORIA: activas del DAT
        INSERT INTO #d_hist (CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA)
        SELECT @cliente, d.CUENTA, TRY_CONVERT(INT, d.FOLIO), ISNULL(d.CUENTA2, CONCAT(@cliente, '-', TRY_CONVERT(INT, d.FOLIO))), d.SEGMENTO2, d.RIESGO,
               CASE WHEN d.SUB_CTE IN ('NVA', 'REA') THEN d.SUB_CTE ELSE 'NVA' END, 'A', ISNULL(d.FE_ASIG, '19000101'), NULL, NULL
        FROM #d_dat d WHERE TRY_CONVERT(INT, d.FOLIO) IS NOT NULL;
    END;

    -- CONSECUTIVO: máximo de TAB7, DAT e HISTORIA.csv
    DECLARE @max_tab7 INT, @max_otros INT = 0, @hay_folio BIT = 0;
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'TAB7')
    BEGIN
        IF ops.fn_mig_faltan('TAB7', N'FOLIO') IS NOT NULL THROW 50901, 'TAB7.csv: falta la columna FOLIO.', 1;
        EXEC sp_executesql N'SELECT @m = ISNULL(MAX(TRY_CONVERT(INT, cfg.fn_texto(FOLIO))), 0) FROM stg.MIG_TAB7;', N'@m INT OUTPUT', @m = @max_tab7 OUTPUT;
        SET @hay_folio = 1;
    END;
    IF EXISTS (SELECT 1 FROM #d_dat) SELECT @max_otros = ISNULL(MAX(TRY_CONVERT(INT, FOLIO)), 0), @hay_folio = 1 FROM #d_dat;
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'HISTORIA') AND ops.fn_mig_faltan('HISTORIA', N'FOLIO') IS NULL
    BEGIN
        DECLARE @mh INT;
        EXEC sp_executesql N'SELECT @m = ISNULL(MAX(TRY_CONVERT(INT, cfg.fn_texto(FOLIO))), 0) FROM stg.MIG_HISTORIA;', N'@m INT OUTPUT', @m = @mh OUTPUT;
        IF @mh > @max_otros SET @max_otros = @mh;
        SET @hay_folio = 1;
    END;
    IF @hay_folio = 1
    BEGIN
        INSERT INTO #d_cons VALUES (@cliente, CASE WHEN ISNULL(@max_tab7, 0) > @max_otros THEN @max_tab7 ELSE @max_otros END);
        IF @max_tab7 < @max_otros
            INSERT INTO #aviso (TEXTO) VALUES (CONCAT(N'CONSECUTIVO: TAB7 (', @max_tab7, N') es menor que el folio más alto usado (', @max_otros, N'); se toma ', @max_otros));
    END;

    -- PAGOS (PAGTOT): solo CUENTA + FE_PAG + MONT (y FE_REG informativo)
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'PAGTOT')
    BEGIN
        SET @falta = ops.fn_mig_faltan('PAGTOT', N'CUENTA, FE_PAG, MONT');
        IF @falta IS NOT NULL BEGIN SET @msg = CONCAT(N'PAGTOT.csv: faltan las columnas ', @falta); THROW 50902, @msg, 1; END;
        SET @sql = N'
        ;WITH p AS (
            SELECT LEFT(cfg.fn_texto(CUENTA), 25) AS CUENTA,
                   CASE WHEN cfg.fn_texto(FE_PAG) LIKE ''[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]''
                        THEN TRY_CONVERT(DATE, RIGHT(cfg.fn_texto(FE_PAG), 4) + LEFT(cfg.fn_texto(FE_PAG), 2) + SUBSTRING(cfg.fn_texto(FE_PAG), 3, 2), 112) END AS FE_PAG,
                   TRY_CONVERT(DECIMAL(38,4), cfg.fn_texto(MONT)) AS IMP,
                   ' + CASE WHEN COL_LENGTH('stg.MIG_PAGTOT', 'FE_REG') IS NULL THEN N'CAST(NULL AS NVARCHAR(20))' ELSE N'cfg.fn_texto(FE_REG)' END + N' AS FE_REG
            FROM stg.MIG_PAGTOT)
        INSERT INTO #d_pag (CLIENTE, CUENTA, FE_PAG, IMPORTE, FE_REG, ID_CORRIDA, ORIGEN)
        SELECT @cliente, CUENTA, FE_PAG, CAST(IMP AS DECIMAL(15,2)),
               CASE WHEN FE_REG LIKE ''[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'' THEN TRY_CONVERT(DATE, RIGHT(FE_REG, 4) + LEFT(FE_REG, 2) + SUBSTRING(FE_REG, 3, 2), 112) END,
               0, ''PAGTOT''
        FROM p WHERE CUENTA IS NOT NULL AND FE_PAG IS NOT NULL AND IMP IS NOT NULL AND ABS(IMP) < 10000000000000;
        SELECT @n = COUNT(*) FROM stg.MIG_PAGTOT;';
        EXEC sp_executesql @sql, N'@cliente VARCHAR(10), @n INT OUTPUT', @cliente = @cliente, @n = @n OUTPUT;
        IF @n > (SELECT COUNT(*) FROM #d_pag)
            INSERT INTO #aviso (TEXTO) VALUES (CONCAT(N'PAGTOT: ', @n - (SELECT COUNT(*) FROM #d_pag),
                N' registros omitidos por FE_PAG incompleta (no de 8 posiciones), monto ilegible o sin cuenta; pagos.prg compara FE_PAG de 8 posiciones, así que nunca coincidirían con un pago nuevo'));
    END;

    -- ETIQUETAS: tipo -> llave, valor (si se repite, gana el último)
    DECLARE @et TABLE (TIPO VARCHAR(20), LLAVE SYSNAME, VALOR SYSNAME);
    INSERT INTO @et VALUES ('ETI', 'CUENTA', 'ETIQUETA'), ('DM1', 'CUENTA', 'ETIQUETA'), ('TOP', 'CUENTA2', 'ETIQUETA'), ('STATUS', 'CUENTA', 'ESTATUS');
    DECLARE @tipo VARCHAR(20), @ll SYSNAME, @vv SYSNAME;
    DECLARE ce CURSOR LOCAL FAST_FORWARD FOR SELECT e.TIPO, e.LLAVE, e.VALOR FROM @et e JOIN @hay h ON h.F = e.TIPO;
    OPEN ce; FETCH NEXT FROM ce INTO @tipo, @ll, @vv;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @falta = ops.fn_mig_faltan(@tipo, @ll + N', ' + @vv);
        IF @falta IS NOT NULL BEGIN SET @msg = CONCAT(@tipo, N'.csv: faltan las columnas ', @falta); THROW 50903, @msg, 1; END;
        SET @sql = N'INSERT INTO #d_eti (CLIENTE, TIPO, LLAVE, VALOR) SELECT @cliente, @tipo, LEFT(K, 30), LEFT(V, 100) FROM ('
                 + N'SELECT cfg.fn_texto(' + QUOTENAME(@ll) + N') AS K, cfg.fn_texto(' + QUOTENAME(@vv) + N') AS V, '
                 + N'ROW_NUMBER() OVER (PARTITION BY cfg.fn_texto(' + QUOTENAME(@ll) + N') ORDER BY FILA DESC) AS RN FROM stg.' + QUOTENAME('MIG_' + @tipo)
                 + N' WHERE cfg.fn_texto(' + QUOTENAME(@ll) + N') IS NOT NULL AND cfg.fn_texto(' + QUOTENAME(@vv) + N') IS NOT NULL) x WHERE RN = 1;';
        EXEC sp_executesql @sql, N'@cliente VARCHAR(10), @tipo VARCHAR(20)', @cliente = @cliente, @tipo = @tipo;
        INSERT INTO #eti_tipos VALUES (@tipo);
        FETCH NEXT FROM ce INTO @tipo, @ll, @vv;
    END;
    CLOSE ce; DEALLOCATE ce;

    -- EXCLUSIONES
    DECLARE @ex TABLE (FUENTE SYSNAME, TIPO VARCHAR(20), CV SYSNAME, CV2 SYSNAME NULL, MOTIVO NVARCHAR(200), FILTRO VARCHAR(10) NULL);
    INSERT INTO @ex VALUES
        ('EXC486', 'CUENTA', 'CUENTA', NULL, N'Exclusión de cuentas (exc486)', NULL),
        ('DIRMAL', 'DIRECCION', 'CUENTA', 'DIRECC1', N'Dirección mala (dirmal)', 'VALOR'),
        ('EMAILMALO', 'CORREO', 'EMAIL', 'CUENTA', N'Correo malo (EMAILMALO)', 'VALOR2'),
        ('BLACKLIST', 'TELEFONO', 'TEL', NULL, N'Lista negra de teléfonos (REQ 2024-095288)', NULL),
        ('TELBAJ', 'TELEFONO', 'TEL', 'CUENTA', N'Teléfono dado de baja para la cuenta (TELBAJ_G1)', 'VALOR2');
    DECLARE @fx SYSNAME, @cv SYSNAME, @cv2 SYSNAME, @mot NVARCHAR(200), @filtro VARCHAR(10), @antes INT;
    DECLARE cx CURSOR LOCAL FAST_FORWARD FOR SELECT e.FUENTE, e.TIPO, e.CV, e.CV2, e.MOTIVO, e.FILTRO FROM @ex e JOIN @hay h ON h.F = e.FUENTE;
    OPEN cx; FETCH NEXT FROM cx INTO @fx, @tipo, @cv, @cv2, @mot, @filtro;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @falta = ops.fn_mig_faltan(@fx, @cv + ISNULL(N', ' + @cv2, N''));
        IF @falta IS NOT NULL BEGIN SET @msg = CONCAT(@fx, N'.csv: faltan las columnas ', @falta); THROW 50904, @msg, 1; END;
        SET @antes = (SELECT COUNT(*) FROM #d_exc);
        SET @sql = N';WITH x AS (SELECT '
                 + CASE WHEN @fx = 'BLACKLIST' THEN N'cfg.fn_solo_digitos(cfg.fn_texto(' + QUOTENAME(@cv) + N'))'
                        WHEN @tipo = 'CORREO' THEN N'LOWER(cfg.fn_texto(' + QUOTENAME(@cv) + N'))'
                        ELSE N'cfg.fn_texto(' + QUOTENAME(@cv) + N')' END + N' AS V, '
                 + CASE WHEN @cv2 IS NULL THEN N'CAST(NULL AS NVARCHAR(200))' ELSE N'cfg.fn_texto(' + QUOTENAME(@cv2) + N')' END + N' AS V2 '
                 + N'FROM stg.' + QUOTENAME('MIG_' + @fx) + N') '
                 + N'INSERT INTO #d_exc (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ) '
                 + N'SELECT DISTINCT @cliente, @tipo, LEFT(V, 200), LEFT(V2, 200), @mot, @mig FROM x WHERE V IS NOT NULL'
                 + CASE WHEN @fx = 'BLACKLIST' THEN N' AND LEN(V) = 10' ELSE N'' END
                 + CASE @filtro WHEN 'VALOR' THEN N' AND (V LIKE @cliente + ''-%'' OR V IN (SELECT C FROM #cuentas))'
                                WHEN 'VALOR2' THEN N' AND (V2 LIKE @cliente + ''-%'' OR V2 IN (SELECT C FROM #cuentas))' ELSE N'' END + N';';
        EXEC sp_executesql @sql, N'@cliente VARCHAR(10), @tipo VARCHAR(20), @mot NVARCHAR(200), @mig VARCHAR(40)', @cliente = @cliente, @tipo = @tipo, @mot = @mot, @mig = @mig;
        SELECT @n = FILAS FROM #fuente WHERE FUENTE = @fx;
        INSERT INTO #aviso (TEXTO) VALUES (CONCAT(@fx, N': ', (SELECT COUNT(*) FROM #d_exc) - @antes, N' de ', @n, N' registros aplican al ', @cliente));
        IF @fx = 'BLACKLIST'
        BEGIN
            SET @sql = N'SELECT @n = COUNT(*) FROM stg.MIG_BLACKLIST WHERE cfg.fn_texto(TEL) IS NOT NULL AND LEN(cfg.fn_solo_digitos(cfg.fn_texto(TEL))) <> 10;';
            EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @n OUTPUT;
            IF @n > 0 INSERT INTO #aviso (TEXTO) VALUES (CONCAT(N'BLACKLIST: ', @n, N' teléfonos omitidos por no tener 10 dígitos'));
        END;
        FETCH NEXT FROM cx INTO @fx, @tipo, @cv, @cv2, @mot, @filtro;
    END;
    CLOSE cx; DEALLOCATE cx;

    -- LADA y PNC (si se repite, gana el último)
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'LADA')
    BEGIN
        IF ops.fn_mig_faltan('LADA', N'CP, LADA') IS NOT NULL THROW 50905, 'LADA.csv: faltan las columnas CP y/o LADA.', 1;
        EXEC (N'INSERT INTO #d_lada (CP, LADA) SELECT CP, LADA FROM (SELECT RIGHT(''00000'' + cfg.fn_texto(CP), 5) AS CP, LEFT(cfg.fn_texto(LADA), 5) AS LADA, '
            + N'ROW_NUMBER() OVER (PARTITION BY RIGHT(''00000'' + cfg.fn_texto(CP), 5) ORDER BY FILA DESC) AS RN FROM stg.MIG_LADA '
            + N'WHERE cfg.fn_texto(CP) IS NOT NULL AND cfg.fn_texto(LADA) IS NOT NULL) x WHERE RN = 1;');
    END;
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'PNC')
    BEGIN
        IF ops.fn_mig_faltan('PNC', N'LADA, SERIE, N_INI, N_FIN, TIPORED') IS NOT NULL THROW 50906, 'PNC.csv: faltan columnas (LADA, SERIE, N_INI, N_FIN, TIPORED).', 1;
        EXEC (N'INSERT INTO #d_pnc (LADA, SERIE, N_INI, N_FIN, TIPORED) SELECT LADA, SERIE, N_INI, N_FIN, TIPORED FROM ('
            + N'SELECT LEFT(cfg.fn_texto(LADA), 3) AS LADA, LEFT(cfg.fn_texto(SERIE), 4) AS SERIE, TRY_CONVERT(INT, TRY_CONVERT(DECIMAL(18,2), cfg.fn_texto(N_INI))) AS N_INI, '
            + N'TRY_CONVERT(INT, TRY_CONVERT(DECIMAL(18,2), cfg.fn_texto(N_FIN))) AS N_FIN, LEFT(cfg.fn_texto(TIPORED), 10) AS TIPORED, '
            + N'ROW_NUMBER() OVER (PARTITION BY cfg.fn_texto(LADA), cfg.fn_texto(SERIE), TRY_CONVERT(INT, TRY_CONVERT(DECIMAL(18,2), cfg.fn_texto(N_INI))) ORDER BY FILA DESC) AS RN '
            + N'FROM stg.MIG_PNC WHERE cfg.fn_texto(LADA) IS NOT NULL AND cfg.fn_texto(SERIE) IS NOT NULL AND TRY_CONVERT(DECIMAL(18,2), cfg.fn_texto(N_INI)) IS NOT NULL) x '
            + N'WHERE RN = 1 AND N_FIN IS NOT NULL AND TIPORED IS NOT NULL;');
    END;

    /* 3. Resumen */
    CREATE TABLE #res (ORDEN INT, DESTINO VARCHAR(20), TABLA SYSNAME, FILAS INT, FUENTES NVARCHAR(200));
    INSERT INTO #res
    SELECT o, d, t, n, s FROM (VALUES
        (1, 'DAT', 'dat.DAT_486', (SELECT COUNT(*) FROM #d_dat), N'DAT'),
        (2, 'HISTORIA', 'dat.HISTORIA_FOLIO', (SELECT COUNT(*) FROM #d_hist), N'DAT'),
        (3, 'CONSECUTIVO', 'dat.FOLIO_CONSECUTIVO', (SELECT COUNT(*) FROM #d_cons), N'TAB7, DAT, HISTORIA'),
        (4, 'PAGOS', 'dat.PAGO_ARRIBADO', (SELECT COUNT(*) FROM #d_pag), N'PAGTOT'),
        (5, 'ETIQUETAS', 'cfg.ETIQUETA', (SELECT COUNT(*) FROM #d_eti), N'ETI, DM1, TOP, STATUS'),
        (6, 'EXCLUSIONES', 'cfg.EXCLUSION', (SELECT COUNT(*) FROM #d_exc), N'EXC486, DIRMAL, EMAILMALO, BLACKLIST, TELBAJ'),
        (7, 'LADA', 'cfg.LADA', (SELECT COUNT(*) FROM #d_lada), N'LADA'),
        (8, 'PNC', 'cfg.PLAN_NUMERACION', (SELECT COUNT(*) FROM #d_pnc), N'PNC')) v(o, d, t, n, s)
    WHERE d IN (SELECT D FROM @dest);
    INSERT INTO #aviso (TEXTO) SELECT CONCAT(FUENTE, N'.csv no se encontró en ', @carpeta) FROM #fuente WHERE FILAS < 0;

    IF @confirmar = 0
    BEGIN
        SELECT f.FUENTE, CASE WHEN f.FILAS < 0 THEN NULL ELSE f.FILAS END AS FILAS_LEIDAS FROM #fuente f ORDER BY f.FUENTE;
        SELECT DESTINO, TABLA, FILAS, FUENTES FROM #res ORDER BY ORDEN;
        SELECT TEXTO AS AVISO FROM #aviso ORDER BY ID;
        PRINT 'Solo revisión: no se escribió nada. Ejecuta con @confirmar = 1 para cargar.';
    END
    ELSE
    BEGIN
        /* 4. Cargar en una sola transacción */
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'DAT') AND EXISTS (SELECT 1 FROM @hay WHERE F = 'DAT')
        BEGIN
            IF @reemplazar = 0 AND EXISTS (SELECT 1 FROM dat.DAT_486) THROW 50910, 'dat.DAT_486 ya tiene registros; usa @reemplazar = 1. No se cargó nada.', 1;
            DELETE FROM dat.DAT_486;
            INSERT INTO dat.DAT_486 SELECT * FROM #d_dat;
        END;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'HISTORIA') AND EXISTS (SELECT 1 FROM @hay WHERE F = 'DAT')
        BEGIN
            IF @reemplazar = 0 AND EXISTS (SELECT 1 FROM dat.HISTORIA_FOLIO WHERE CLIENTE = @cliente) THROW 50911, 'dat.HISTORIA_FOLIO ya tiene registros; usa @reemplazar = 1. No se cargó nada.', 1;
            DELETE FROM dat.HISTORIA_FOLIO WHERE CLIENTE = @cliente;
            INSERT INTO dat.HISTORIA_FOLIO (CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA)
            SELECT CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA FROM #d_hist;
        END;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'CONSECUTIVO') AND EXISTS (SELECT 1 FROM #d_cons)
        BEGIN
            DELETE FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = @cliente;
            INSERT INTO dat.FOLIO_CONSECUTIVO (CLIENTE, ULTIMO_FOLIO) SELECT CLIENTE, ULTIMO_FOLIO FROM #d_cons;
        END;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'PAGOS') AND EXISTS (SELECT 1 FROM @hay WHERE F = 'PAGTOT')
        BEGIN
            IF @reemplazar = 0 AND EXISTS (SELECT 1 FROM dat.PAGO_ARRIBADO WHERE CLIENTE = @cliente AND ORIGEN = 'PAGTOT') THROW 50912, 'dat.PAGO_ARRIBADO ya tiene pagos de PAGTOT; usa @reemplazar = 1. No se cargó nada.', 1;
            DELETE FROM dat.PAGO_ARRIBADO WHERE CLIENTE = @cliente AND ORIGEN = 'PAGTOT';
            INSERT INTO dat.PAGO_ARRIBADO (CLIENTE, CUENTA, FE_PAG, IMPORTE, FE_REG, ID_CORRIDA, ORIGEN) SELECT CLIENTE, CUENTA, FE_PAG, IMPORTE, FE_REG, ID_CORRIDA, ORIGEN FROM #d_pag;
        END;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'ETIQUETAS') AND EXISTS (SELECT 1 FROM #eti_tipos)
        BEGIN
            DELETE e FROM cfg.ETIQUETA e WHERE e.CLIENTE = @cliente AND e.TIPO IN (SELECT TIPO FROM #eti_tipos);
            INSERT INTO cfg.ETIQUETA (CLIENTE, TIPO, LLAVE, VALOR) SELECT CLIENTE, TIPO, LLAVE, VALOR FROM #d_eti;
        END;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'EXCLUSIONES') AND EXISTS (SELECT 1 FROM @hay h JOIN @ex e ON e.FUENTE = h.F)
        BEGIN
            DELETE FROM cfg.EXCLUSION WHERE CLIENTE = @cliente AND REQ = @mig;
            INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ) SELECT CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ FROM #d_exc;
        END;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'LADA') AND EXISTS (SELECT 1 FROM @hay WHERE F = 'LADA')
        BEGIN
            IF @reemplazar = 0 AND EXISTS (SELECT 1 FROM cfg.LADA) THROW 50913, 'cfg.LADA ya tiene registros; usa @reemplazar = 1. No se cargó nada.', 1;
            DELETE FROM cfg.LADA;
            INSERT INTO cfg.LADA (CP, LADA) SELECT CP, LADA FROM #d_lada;
        END;
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'PNC') AND EXISTS (SELECT 1 FROM @hay WHERE F = 'PNC')
        BEGIN
            IF @reemplazar = 0 AND EXISTS (SELECT 1 FROM cfg.PLAN_NUMERACION) THROW 50914, 'cfg.PLAN_NUMERACION ya tiene registros; usa @reemplazar = 1. No se cargó nada.', 1;
            DELETE FROM cfg.PLAN_NUMERACION;
            INSERT INTO cfg.PLAN_NUMERACION (LADA, SERIE, N_INI, N_FIN, TIPORED) SELECT LADA, SERIE, N_INI, N_FIN, TIPORED FROM #d_pnc;
        END;
        COMMIT TRANSACTION;
        SELECT DESTINO, TABLA, FILAS AS FILAS_CARGADAS FROM #res ORDER BY ORDEN;
        SELECT TEXTO AS AVISO FROM #aviso ORDER BY ID;
        PRINT 'Listo: carga confirmada. Borra los CSV de la carpeta (traen datos de clientes).';
    END;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @drop_e NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(N'DROP TABLE IF EXISTS stg.' + QUOTENAME(N'MIG_' + value) + N';' AS NVARCHAR(MAX)), N' ')
                                         FROM STRING_SPLIT('DAT,TAB7,HISTORIA,PAGTOT,ETI,DM1,TOP,STATUS,EXC486,DIRMAL,EMAILMALO,BLACKLIST,TELBAJ,LADA,PNC', ','));
        EXEC (@drop_e);
        THROW;
    END CATCH;

    /* Las tablas de paso traen datos de clientes: no se quedan */
    DECLARE @drop NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(N'DROP TABLE IF EXISTS stg.' + QUOTENAME(N'MIG_' + FUENTE) + N';' AS NVARCHAR(MAX)), N' ') FROM #fuente);
    EXEC (@drop);
END;
GO
