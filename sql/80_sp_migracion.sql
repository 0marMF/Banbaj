USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 80 Migración inicial desde los DBF (una sola vez)
   ---------------------------------------------------------------------
   Sustituye a tools/migrar_dbf.py: todo corre en SQL Server.

   1. En FoxPro, exportar cada DBF a CSV con cyber/486/EXPORTAR_MIGRACION.prg
      (deja C:\MIGRA486\<FUENTE>.csv: DAT, TAB7, HISTORIA, PAGTOT, ETI, DM1, TOP,
      STATUS, EXC486, DIRMAL, EMAILMALO, BLACKLIST, PURGA), solo con los campos que se usan.
      La carpeta debe ser visible para el servicio de SQL Server.
   2. Revisar (no escribe nada):   EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';
   3. Cargar:                      EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;
      Si los destinos ya tienen datos hay que pedir @reemplazar = 1.
      @solo = N'DAT,HISTORIA,…' limita los destinos.
   4. Borrar los CSV de C:\MIGRA486 (traen datos de clientes).

   Destinos (en una sola transacción; si algo falla no queda nada a medias):
     DAT          DAT.csv                              -> dat.DAT_486
     HISTORIA     DAT.csv (activas) + HISTORIA.csv (cada asignación anterior como baja: fechas de
                  asignación, reasignación y retiro, y en DATOS_BAJA saldos, correos, teléfonos y
                  dirección; sirve para reasignar con el mismo folio y ubicar pagos de cuentas
                  retiradas)  -> dat.HISTORIA_FOLIO   (DEVOL no se migra)
                  PURGA.csv: no se usa (03/11). Los periodos anteriores quedan sin fechas de asignación,
                  reasignación y retiro; se llenan con las corridas de Banbaj.
     CONSECUTIVO  máximo folio de TAB7, DAT e HISTORIA -> dat.FOLIO_CONSECUTIVO
     PAGOS        PAGTOT.csv (CUENTA, MONT, FE_PAG, FE_REG) -> dat.PAGO_ARRIBADO
     ETIQUETAS    ETI, DM1, TOP, STATUS                -> cfg.ETIQUETA
     EXCLUSIONES  EXC486, DIRMAL, EMAILMALO, BLACKLIST -> cfg.EXCLUSION
                  BLACKLIST (TEL | FE_AGRE | OS | SOLICITUD): TEL de 10 dígitos, OS = requerimiento,
                  FE_AGRE = fecha, SOLICITUD = quién lo pidió. STATUS 'X' excluye, vacío no; el DBF
                  no trae STATUS, así que todo cuenta como 'X'.
   Ya no se migran (01/11): TELBAJ y PNC se leen de CYBER en cada asignación
   (ops.sp_telefonos_refrescar_cyber) y LADA no la usa ningún proceso.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Revisa un CSV tal como lo ve el servidor, sin mostrar datos: renglones, fecha del archivo, renglones con
   un número de comillas distinto al de casi todos (comillas dentro de un campo) y caracteres raros. Con @fila
   regresa ese renglón y sus vecinos enmascarados (letra = x, dígito = 9), con sus comillas y campos.
   El renglón 1 es el encabezado, igual que en el mensaje de SQL Server y en el Bloc de notas. */
CREATE OR ALTER PROCEDURE ops.sp_mig_diagnostico
    @archivo  NVARCHAR(500),
    @fila     INT            = NULL,
    @codepage VARCHAR(10)    = 'ACP',
    @resumen  NVARCHAR(3000) = NULL OUTPUT,
    @mostrar  BIT            = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX), @n INT, @moda INT, @k INT, @lista NVARCHAR(400), @raros NVARCHAR(1000), @info NVARCHAR(400) = N'',
            @fdl NVARCHAR(20) = N'0x0a', @carpeta NVARCHAR(500), @nombre NVARCHAR(260),
            @cp NVARCHAR(100) = CASE WHEN NULLIF(@codepage, '') IS NOT NULL THEN N', CODEPAGE = ' + QUOTENAME(@codepage, '''') ELSE N'' END;

    /* Fecha y tamaño del archivo que lee el servidor (si el usuario tiene VIEW SERVER STATE) */
    SET @nombre = RIGHT(@archivo, CHARINDEX(N'\', REVERSE(REPLACE(@archivo, N'/', N'\')) + N'\') - 1);
    SET @carpeta = LEFT(@archivo, LEN(@archivo) - LEN(@nombre));
    BEGIN TRY
        SELECT @info = CONCAT(N', modificado el ', CONVERT(VARCHAR(16), last_write_time, 120), N', ', size_in_bytes, N' bytes')
        FROM sys.dm_os_enumerate_filesystem(@carpeta, @nombre) WHERE is_directory = 0;
    END TRY
    BEGIN CATCH
        SET @info = N'';
    END CATCH;

    /* El archivo renglón por renglón, sin interpretar comillas */
    DROP VIEW IF EXISTS stg.vMIG_LINEAS;
    DROP TABLE IF EXISTS stg.MIG_LINEAS;
    CREATE TABLE stg.MIG_LINEAS (N INT IDENTITY(1,1) NOT NULL PRIMARY KEY, L NVARCHAR(MAX) NULL);
    EXEC (N'CREATE VIEW stg.vMIG_LINEAS AS SELECT L FROM stg.MIG_LINEAS;');
    BEGIN TRY
        CREATE TABLE #dh (L NVARCHAR(4000));
        SET @sql = N'BULK INSERT #dh FROM ' + QUOTENAME(@archivo, '''') + N' WITH (FIRSTROW = 1, LASTROW = 1, ROWTERMINATOR = ''0x0a'', FIELDTERMINATOR = ''\t\t\t''' + @cp + N');';
        EXEC (@sql);
        SELECT @fdl = CASE WHEN RIGHT(L, 1) = NCHAR(13) THEN N'0x0d0a' ELSE N'0x0a' END FROM #dh;
        SET @sql = N'BULK INSERT stg.vMIG_LINEAS FROM ' + QUOTENAME(@archivo, '''')
                 + N' WITH (ROWTERMINATOR = ''' + @fdl + N''', FIELDTERMINATOR = ''\t\t\t'', TABLOCK' + @cp + N');';
        EXEC (@sql);

        SELECT N, L, (DATALENGTH(L) - DATALENGTH(REPLACE(L, N'"', N''))) / 2 AS COMILLAS,
               PATINDEX(N'%[^ -~ÁÉÍÓÚÜÑáéíóúüñ°ºª¿¡]%', L COLLATE Latin1_General_100_BIN2) AS P
        INTO #dl FROM stg.MIG_LINEAS;
        SET @n = (SELECT COUNT(*) FROM #dl);
        SET @moda = (SELECT TOP (1) COMILLAS FROM #dl WHERE N > 1 GROUP BY COMILLAS ORDER BY COUNT(*) DESC, COMILLAS);
        SELECT @k = COUNT(*) FROM #dl WHERE N > 1 AND COMILLAS <> @moda;
        SET @lista = (SELECT STRING_AGG(CAST(N AS VARCHAR(12)), ', ') WITHIN GROUP (ORDER BY N)
                      FROM (SELECT TOP (5) N FROM #dl WHERE N > 1 AND COMILLAS <> @moda ORDER BY N) x);
        SET @raros = (SELECT STRING_AGG(CONCAT(N'U+', RIGHT(CONVERT(VARCHAR(10), CAST(C AS VARBINARY(4)), 2), 4), N' en ', R,
                                               N' renglones (primero el ', PRIMERO, N')'), N'; ')
                      FROM (SELECT TOP (8) UNICODE(SUBSTRING(L, P, 1)) AS C, COUNT(*) AS R, MIN(N) AS PRIMERO
                            FROM #dl WHERE P > 0 GROUP BY UNICODE(SUBSTRING(L, P, 1)) ORDER BY COUNT(*) DESC) x);
        SET @resumen = CONCAT(N'El servidor ve ', @n, N' renglones', @info, N'. Casi todos traen ', @moda, N' comillas; con otro número: ',
                              @k, CASE WHEN @k > 0 THEN CONCAT(N' (renglones ', @lista, CASE WHEN @k > 5 THEN N'…' END,
                                                               N': comillas dentro de un campo)') END,
                              N'. Caracteres raros: ', ISNULL(@raros, N'ninguno'), N'.');

        IF @mostrar = 1
        BEGIN
            PRINT @resumen;
            IF @fila IS NOT NULL
            BEGIN
                /* El renglón y sus vecinos, enmascarados, con los campos contados fuera de comillas */
                DECLARE @letras NVARCHAR(100) = N'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÁÉÍÓÚÜÑáéíóúüñ';
                CREATE TABLE #dm (N INT, COMILLAS INT, CAMPOS INT, RAROS NVARCHAR(400), ENMASCARADO NVARCHAR(MAX));
                DECLARE @i INT, @s NVARCHAR(MAX), @j INT, @largo INT, @dentro BIT, @campos INT, @r NVARCHAR(400), @ch NCHAR(1), @e NVARCHAR(MAX), @u VARCHAR(10);
                DECLARE cl CURSOR LOCAL FAST_FORWARD FOR SELECT N, L FROM #dl WHERE N BETWEEN @fila - 2 AND @fila + 2 ORDER BY N;
                OPEN cl; FETCH NEXT FROM cl INTO @i, @s;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    SELECT @j = 1, @largo = DATALENGTH(@s) / 2, @dentro = 0, @campos = 1, @r = N'', @e = N'';
                    WHILE @j <= @largo
                    BEGIN
                        SET @ch = SUBSTRING(@s, @j, 1);
                        IF @ch = N'"' SET @dentro = 1 - @dentro;
                        ELSE IF @ch = N',' AND @dentro = 0 SET @campos += 1;
                        IF @ch COLLATE Latin1_General_100_BIN2 LIKE N'[0-9]' SET @e += N'9';
                        ELSE IF CHARINDEX(@ch COLLATE Latin1_General_100_BIN2, @letras COLLATE Latin1_General_100_BIN2) > 0 SET @e += N'x';
                        ELSE IF @ch COLLATE Latin1_General_100_BIN2 LIKE N'[ -~]' SET @e += @ch;
                        ELSE
                        BEGIN
                            SET @u = RIGHT(CONVERT(VARCHAR(10), CAST(UNICODE(@ch) AS VARBINARY(4)), 2), 4);
                            SET @e += CONCAT(N'<U+', @u, N'>');
                            IF LEN(@r) < 350 SET @r += CONCAT(N'U+', @u, N' en el campo ', @campos, N'; ');
                        END;
                        SET @j += 1;
                    END;
                    INSERT INTO #dm VALUES (@i, (DATALENGTH(@s) - DATALENGTH(REPLACE(@s, N'"', N''))) / 2, @campos, NULLIF(@r, N''), @e);
                    FETCH NEXT FROM cl INTO @i, @s;
                END;
                CLOSE cl; DEALLOCATE cl;
                SELECT N AS RENGLON, COMILLAS, CAMPOS, RAROS, ENMASCARADO FROM #dm ORDER BY N;
            END;
        END;
    END TRY
    BEGIN CATCH
        DROP VIEW IF EXISTS stg.vMIG_LINEAS;
        DROP TABLE IF EXISTS stg.MIG_LINEAS;
        THROW;
    END CATCH;
    DROP VIEW IF EXISTS stg.vMIG_LINEAS;
    DROP TABLE IF EXISTS stg.MIG_LINEAS;
END;
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
    DECLARE @fdl NVARCHAR(20) = N'0x0a';
    SELECT @fdl = CASE WHEN RIGHT(L, 1) = NCHAR(13) THEN N'0x0d0a' ELSE N'0x0a' END,      -- FoxPro escribe CRLF
           @hdr = REPLACE(REPLACE(REPLACE(L, NCHAR(13), N''), N'"', N''), NCHAR(65279), N'') FROM #h;
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
             + N' WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''' + @fdl + N''', TABLOCK' + @cp + N');';
    BEGIN TRY
        EXEC (@sql);
    END TRY
    BEGIN CATCH
        /* SQL Server no pudo leer el CSV: se revisa el archivo tal como lo ve el servidor (el mensaje no lleva datos) */
        DECLARE @orig NVARCHAR(4000) = ERROR_MESSAGE(), @resumen NVARCHAR(3000), @msg NVARCHAR(4000);
        EXEC (N'DROP VIEW IF EXISTS ' + @vista + N'; DROP TABLE IF EXISTS ' + @tabla + N';');
        BEGIN TRY
            EXEC ops.sp_mig_diagnostico @archivo, NULL, @codepage, @resumen OUTPUT, @mostrar = 0;
        END TRY
        BEGIN CATCH
            SET @resumen = CONCAT(N'No se pudo revisar el archivo: ', ERROR_MESSAGE());
        END CATCH;
        SET @msg = LEFT(CONCAT(@archivo, N': SQL Server no pudo leer el CSV (', LEFT(@orig, 300), N'). ', @resumen,
                               N' Renglones enmascarados: EXEC ops.sp_mig_diagnostico N''', @archivo, N''', <renglón>;'), 4000);
        THROW 50905, @msg, 1;
    END CATCH;
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
    INSERT INTO @dest SELECT value FROM STRING_SPLIT('DAT,HISTORIA,CONSECUTIVO,PAGOS,ETIQUETAS,EXCLUSIONES', ',')
    WHERE @solo IS NULL OR value IN (SELECT UPPER(LTRIM(RTRIM(s.value))) FROM STRING_SPLIT(@solo, ',') s);
    CREATE TABLE #aviso (ID INT IDENTITY(1,1), TEXTO NVARCHAR(1000));
    CREATE TABLE #fuente (FUENTE SYSNAME PRIMARY KEY, FILAS INT);

    BEGIN TRY
    /* 1. Leer los CSV */
    DECLARE cf CURSOR LOCAL FAST_FORWARD FOR
        SELECT value FROM STRING_SPLIT('DAT,TAB7,HISTORIA,PURGA,PAGTOT,ETI,DM1,TOP,STATUS,EXC486,DIRMAL,EMAILMALO,BLACKLIST', ',');
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
    SELECT TOP (0) CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA, DATOS_BAJA INTO #d_hist FROM dat.HISTORIA_FOLIO;
    CREATE TABLE #d_cons (CLIENTE VARCHAR(10), ULTIMO_FOLIO INT);
    CREATE TABLE #d_pag (CLIENTE VARCHAR(10), CUENTA VARCHAR(25), FE_PAG DATE, IMPORTE DECIMAL(15,2), FE_REG DATE, ID_CORRIDA INT, ORIGEN VARCHAR(10));
    CREATE TABLE #d_eti (CLIENTE VARCHAR(10), TIPO VARCHAR(20), LLAVE VARCHAR(30), VALOR NVARCHAR(100));
    CREATE TABLE #eti_tipos (TIPO VARCHAR(20));
    CREATE TABLE #d_exc (CLIENTE VARCHAR(10), TIPO VARCHAR(20), VALOR NVARCHAR(200), VALOR2 NVARCHAR(200), MOTIVO NVARCHAR(200), REQ VARCHAR(40),
                         ACTIVO BIT NOT NULL DEFAULT 1, FE_ALTA DATETIME2(0) NULL);
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
                                  THEN N'COALESCE(TRY_CONVERT(DATE, cfg.fn_texto(m.' + QUOTENAME(c.name) + N'), 112), TRY_CONVERT(DATE, cfg.fn_texto(m.' + QUOTENAME(c.name) + N'), 111), TRY_CONVERT(DATE, cfg.fn_texto(m.' + QUOTENAME(c.name)
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
               CASE WHEN d.SUB_CTE IN ('NVA', 'REA') THEN d.SUB_CTE ELSE 'NVA' END, 'A', d.FE_ASIG, NULL, NULL
        FROM #d_dat d WHERE TRY_CONVERT(INT, d.FOLIO) IS NOT NULL;
    END;

    -- HISTORIA.csv: cada asignación anterior queda como baja en el histórico (decisión 01/11).
    -- Se guardan las fechas de asignación (FE_ALTA; si SUB_CTE = REA es la reasignación) y de retiro (FE_BAJA),
    -- y en DATOS_BAJA (JSON) las fechas, saldos, correos, teléfonos y dirección que traiga el archivo.
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'HISTORIA')
    BEGIN
        SET @falta = ops.fn_mig_faltan('HISTORIA', N'CUENTA, FOLIO');
        IF @falta IS NOT NULL BEGIN SET @msg = CONCAT(N'HISTORIA.csv: faltan las columnas ', @falta); THROW 50907, @msg, 1; END;
        DECLARE @h_alta SYSNAME = (SELECT TOP (1) c FROM (VALUES (1, N'FE_ASIG'), (2, N'FECHA'), (3, N'FE_ALTA')) v(o, c) WHERE COL_LENGTH('stg.MIG_HISTORIA', c) IS NOT NULL ORDER BY o),
                @h_baja SYSNAME = (SELECT TOP (1) c FROM (VALUES (1, N'FE_BAJA'), (2, N'FE_RET'), (3, N'FE_RETIRO'), (4, N'FE_DEV')) v(o, c) WHERE COL_LENGTH('stg.MIG_HISTORIA', c) IS NOT NULL ORDER BY o),
                @h_json NVARCHAR(MAX);
        /* Campos que se conservan en DATOS_BAJA si vienen en el archivo */
        SELECT @h_json = STRING_AGG(CAST(N'cfg.fn_texto(' + QUOTENAME(c) + N') AS ' + QUOTENAME(c) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY o)
        FROM (VALUES (1, N'FE_ASIG'), (2, N'FE_REA'), (3, N'FE_REASIG'), (4, N'FE_BAJA'), (5, N'FE_RET'), (6, N'FE_RETIRO'), (7, N'FE_DEV'),
                     (10, N'SDO_ACT'), (11, N'SDO_VDO'), (12, N'PAG_MIN'), (13, N'CAPITAL'), (14, N'SALDO1'), (15, N'SALDO2'), (16, N'SALDO3'),
                     (20, N'MAIL'), (21, N'CORREO1'), (22, N'CORREO2'),
                     (30, N'TEL1'), (31, N'TEL2'), (32, N'TEL3'), (33, N'TEL4'), (34, N'TEL5'), (35, N'TEL6'), (36, N'TEL7'), (37, N'TEL8'),
                     (38, N'TEL9'), (39, N'TEL10'), (40, N'TEL11'), (41, N'TEL12'), (42, N'TEL13'), (43, N'TEL14'), (44, N'TEL15'), (45, N'TEL16'),
                     (50, N'DIRECC1'), (51, N'DIRECC2'), (52, N'DIRECC3'), (53, N'DIRECC4'), (54, N'DIRECC5'), (55, N'ESTADO'), (56, N'EDO'),
                     (60, N'SEGMENTO'), (61, N'STATUS'), (62, N'TRAMO'), (63, N'ETIQUETA')) v(o, c)
        WHERE COL_LENGTH('stg.MIG_HISTORIA', c) IS NOT NULL;
        DECLARE @fx_alta NVARCHAR(600) = CASE WHEN @h_alta IS NULL THEN N'CAST(NULL AS DATE)'
                ELSE N'COALESCE(TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_alta) + N'), 112), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_alta) + N'), 111), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_alta) + N'), 23), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_alta) + N'), 103))' END,
                @fx_baja NVARCHAR(600) = CASE WHEN @h_baja IS NULL THEN N'CAST(NULL AS DATE)'
                ELSE N'COALESCE(TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_baja) + N'), 112), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_baja) + N'), 111), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_baja) + N'), 23), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@h_baja) + N'), 103))' END;
        SET @sql = N';WITH h AS (
                SELECT LEFT(cfg.fn_texto(CUENTA), 20) AS CUENTA, TRY_CONVERT(INT, cfg.fn_texto(FOLIO)) AS FOLIO,
                       ' + CASE WHEN COL_LENGTH('stg.MIG_HISTORIA', 'CUENTA2') IS NOT NULL THEN N'LEFT(cfg.fn_texto(CUENTA2), 28)' ELSE N'CAST(NULL AS VARCHAR(28))' END + N' AS CUENTA2,
                       ' + CASE WHEN COL_LENGTH('stg.MIG_HISTORIA', 'SEGMENTO2') IS NOT NULL THEN N'LEFT(cfg.fn_texto(SEGMENTO2), 20)' ELSE N'CAST(NULL AS VARCHAR(20))' END + N' AS SEGMENTO2,
                       ' + CASE WHEN COL_LENGTH('stg.MIG_HISTORIA', 'RIESGO') IS NOT NULL THEN N'LEFT(cfg.fn_texto(RIESGO), 35)' ELSE N'CAST(NULL AS VARCHAR(35))' END + N' AS RIESGO,
                       ' + CASE WHEN COL_LENGTH('stg.MIG_HISTORIA', 'SUB_CTE') IS NOT NULL THEN N'cfg.fn_texto(SUB_CTE)' ELSE N'CAST(NULL AS NVARCHAR(3))' END + N' AS SUB_CTE0,
                       ' + @fx_alta + N' AS FE_ALTA, ' + @fx_baja + N' AS FE_BAJA,
                       ' + CASE WHEN @h_json IS NULL THEN N'CAST(NULL AS NVARCHAR(MAX))' ELSE N'(SELECT ' + @h_json + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)' END + N' AS DATOS, FILA
                FROM stg.MIG_HISTORIA),
            u0 AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY CUENTA, FOLIO, FE_ALTA ORDER BY FILA DESC) AS RN FROM h WHERE CUENTA IS NOT NULL AND FOLIO > 0),
            /* historia.dbf no trae SUB_CTE: la primera asignación de la cuenta es NVA y las siguientes son REA */
            u AS (SELECT *, COALESCE(SUB_CTE0, CASE WHEN ROW_NUMBER() OVER (PARTITION BY CUENTA, RN ORDER BY FE_ALTA, FILA) = 1 THEN ''NVA'' ELSE ''REA'' END) AS SUB_CTE FROM u0)
            INSERT INTO #d_hist (CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA, DATOS_BAJA)
            SELECT @cliente, u.CUENTA, u.FOLIO, ISNULL(u.CUENTA2, CONCAT(@cliente, ''-'', u.FOLIO)), u.SEGMENTO2, u.RIESGO,
                   CASE WHEN u.SUB_CTE IN (''NVA'', ''REA'') THEN u.SUB_CTE ELSE ''NVA'' END, ''B'',
                   NULL, NULL,     -- decisión 03/11: las fechas de asignación, reasignación y retiro del histórico migrado quedan vacías
                   ''MIGRACION (historia.dbf)'', u.DATOS
            FROM u
            WHERE u.RN = 1
              /* el periodo vigente ya entró como activo desde el DAT */
              AND NOT EXISTS (SELECT 1 FROM #d_hist a WHERE a.ESTATUS = ''A'' AND a.CUENTA = u.CUENTA AND a.FOLIO = u.FOLIO
                                AND u.FE_BAJA IS NULL AND (u.FE_ALTA IS NULL OR u.FE_ALTA >= a.FE_ALTA));';
        EXEC sp_executesql @sql, N'@cliente VARCHAR(10)', @cliente = @cliente;
        SET @n = @@ROWCOUNT;
        INSERT INTO #aviso (TEXTO) SELECT CONCAT(N'HISTORIA: ', @n, N' asignaciones anteriores quedan como baja en el histórico (de ', FILAS, N' renglones)') FROM #fuente WHERE FUENTE = 'HISTORIA';
        INSERT INTO #aviso (TEXTO) VALUES (CONCAT(N'HISTORIA: las fechas de asignación, reasignación y retiro de los periodos anteriores quedan vacías (', ISNULL(@h_alta, N'sin fecha'),
                                                  N' solo ordena NVA/REA) · se conservan: ', ISNULL(REPLACE(REPLACE(REPLACE(@h_json, N'cfg.fn_texto(', N''), N') AS ', N'='), N'[', N''), N'(nada)')));
    END;

    -- PURGA (decisión 03/11): no se usa. No trae fecha de retiro y las fechas del histórico migrado quedan vacías;
    -- se empiezan a llenar con las corridas de Banbaj.
    IF EXISTS (SELECT 1 FROM @hay WHERE F = 'PURGA')
        INSERT INTO #aviso (TEXTO) VALUES (N'PURGA: no se usa; las fechas de retiro del histórico migrado quedan vacías');

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
        ('BLACKLIST', 'TELEFONO', 'TEL', NULL, N'Lista negra de teléfonos (blacklist_486)', NULL);
    /* BLACKLIST_486.DBF: TEL | FE_AGRE | OS | SOLICITUD (sin STATUS). El teléfono puede venir como TELEFONO o TEL
       y la fecha como FE_AGRE o FECHA. */
    DECLARE @bl_fecha SYSNAME = CASE WHEN COL_LENGTH('stg.MIG_BLACKLIST', 'FE_AGRE') IS NOT NULL THEN N'FE_AGRE'
                                     WHEN COL_LENGTH('stg.MIG_BLACKLIST', 'FECHA') IS NOT NULL THEN N'FECHA' END;
    IF COL_LENGTH('stg.MIG_BLACKLIST', 'TEL') IS NULL AND COL_LENGTH('stg.MIG_BLACKLIST', 'TELEFONO') IS NOT NULL
        UPDATE @ex SET CV = 'TELEFONO' WHERE FUENTE = 'BLACKLIST';
    DECLARE @fx SYSNAME, @cv SYSNAME, @cv2 SYSNAME, @mot NVARCHAR(200), @filtro VARCHAR(10), @antes INT;
    DECLARE cx CURSOR LOCAL FAST_FORWARD FOR SELECT e.FUENTE, e.TIPO, e.CV, e.CV2, e.MOTIVO, e.FILTRO FROM @ex e JOIN @hay h ON h.F = e.FUENTE;
    OPEN cx; FETCH NEXT FROM cx INTO @fx, @tipo, @cv, @cv2, @mot, @filtro;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @falta = ops.fn_mig_faltan(@fx, @cv + ISNULL(N', ' + @cv2, N''));
        IF @falta IS NOT NULL BEGIN SET @msg = CONCAT(@fx, N'.csv: faltan las columnas ', @falta); THROW 50904, @msg, 1; END;
        SET @antes = (SELECT COUNT(*) FROM #d_exc);
        IF @fx = 'BLACKLIST'
            /* TELEFONO, OS (requerimiento), FECHA y STATUS: 'X' excluye, vacío no. Sin columna STATUS, todo es 'X'. */
            SET @sql = N';WITH x AS (SELECT cfg.fn_solo_digitos(cfg.fn_texto(' + QUOTENAME(@cv) + N')) AS V, '
                     + CASE WHEN COL_LENGTH('stg.MIG_BLACKLIST', 'OS') IS NOT NULL THEN N'LEFT(cfg.fn_texto(OS), 40)' ELSE N'CAST(NULL AS VARCHAR(40))' END + N' AS OS, '
                     + CASE WHEN @bl_fecha IS NOT NULL
                            THEN N'COALESCE(TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@bl_fecha) + N'), 112), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@bl_fecha) + N'), 111), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@bl_fecha) + N'), 23), TRY_CONVERT(DATE, cfg.fn_texto(' + QUOTENAME(@bl_fecha) + N'), 103))'
                            ELSE N'CAST(NULL AS DATE)' END + N' AS FE, '
                     + CASE WHEN COL_LENGTH('stg.MIG_BLACKLIST', 'SOLICITUD') IS NOT NULL THEN N'LEFT(cfg.fn_texto(SOLICITUD), 150)' ELSE N'CAST(NULL AS NVARCHAR(150))' END + N' AS SOL, '
                     + CASE WHEN COL_LENGTH('stg.MIG_BLACKLIST', 'STATUS') IS NOT NULL THEN N'CASE WHEN UPPER(cfg.fn_texto(STATUS)) = ''X'' THEN 1 ELSE 0 END' ELSE N'1' END + N' AS ACT, '
                     + N'ROW_NUMBER() OVER (PARTITION BY cfg.fn_solo_digitos(cfg.fn_texto(' + QUOTENAME(@cv) + N')) ORDER BY FILA DESC) AS RN FROM stg.MIG_BLACKLIST) '
                     + N'INSERT INTO #d_exc (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ, ACTIVO, FE_ALTA) '
                     + N'SELECT @cliente, @tipo, V, NULL, ISNULL(N''Solicita: '' + SOL, @mot), OS, ACT, FE FROM x WHERE RN = 1 AND LEN(V) = 10;';
        ELSE
        SET @sql = N';WITH x AS (SELECT '
                 + CASE WHEN @tipo = 'CORREO' THEN N'LOWER(cfg.fn_texto(' + QUOTENAME(@cv) + N'))'
                        ELSE N'cfg.fn_texto(' + QUOTENAME(@cv) + N')' END + N' AS V, '
                 + CASE WHEN @cv2 IS NULL THEN N'CAST(NULL AS NVARCHAR(200))' ELSE N'cfg.fn_texto(' + QUOTENAME(@cv2) + N')' END + N' AS V2 '
                 + N'FROM stg.' + QUOTENAME('MIG_' + @fx) + N') '
                 + N'INSERT INTO #d_exc (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ) '
                 + N'SELECT DISTINCT @cliente, @tipo, LEFT(V, 200), LEFT(V2, 200), @mot, NULL FROM x WHERE V IS NOT NULL'
                 + CASE @filtro WHEN 'VALOR' THEN N' AND (V LIKE @cliente + ''-%'' OR V IN (SELECT C FROM #cuentas))'
                                WHEN 'VALOR2' THEN N' AND (V2 LIKE @cliente + ''-%'' OR V2 IN (SELECT C FROM #cuentas))' ELSE N'' END + N';';
        EXEC sp_executesql @sql, N'@cliente VARCHAR(10), @tipo VARCHAR(20), @mot NVARCHAR(200), @mig VARCHAR(40)', @cliente = @cliente, @tipo = @tipo, @mot = @mot, @mig = @mig;
        SELECT @n = FILAS FROM #fuente WHERE FUENTE = @fx;
        INSERT INTO #aviso (TEXTO) VALUES (CONCAT(@fx, N': ', (SELECT COUNT(*) FROM #d_exc) - @antes, N' de ', @n, N' registros aplican al ', @cliente));
        IF @fx = 'BLACKLIST'
        BEGIN
            SET @sql = N'SELECT @n = COUNT(*) FROM stg.MIG_BLACKLIST WHERE cfg.fn_texto(' + QUOTENAME(@cv) + N') IS NOT NULL AND LEN(cfg.fn_solo_digitos(cfg.fn_texto(' + QUOTENAME(@cv) + N'))) <> 10;';
            EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @n OUTPUT;
            IF @n > 0 INSERT INTO #aviso (TEXTO) VALUES (CONCAT(N'BLACKLIST: ', @n, N' teléfonos omitidos por no tener 10 dígitos'));
            INSERT INTO #aviso (TEXTO)
            SELECT CONCAT(N'BLACKLIST: ', SUM(CASE WHEN ACTIVO = 1 THEN 1 ELSE 0 END), N' con estatus X (se excluyen) y ', SUM(CASE WHEN ACTIVO = 0 THEN 1 ELSE 0 END),
                          N' con estatus vacío (no se excluyen)', CASE WHEN COL_LENGTH('stg.MIG_BLACKLIST', 'STATUS') IS NULL THEN N'; el archivo no trae STATUS: todos cuentan como X' ELSE N'' END)
            FROM #d_exc WHERE TIPO = 'TELEFONO' AND VALOR2 IS NULL;
        END;
        FETCH NEXT FROM cx INTO @fx, @tipo, @cv, @cv2, @mot, @filtro;
    END;
    CLOSE cx; DEALLOCATE cx;

    /* 3. Resumen */
    CREATE TABLE #res (ORDEN INT, DESTINO VARCHAR(20), TABLA SYSNAME, FILAS INT, FUENTES NVARCHAR(200));
    INSERT INTO #res
    SELECT o, d, t, n, s FROM (VALUES
        (1, 'DAT', 'dat.DAT_486', (SELECT COUNT(*) FROM #d_dat), N'DAT'),
        (2, 'HISTORIA', 'dat.HISTORIA_FOLIO', (SELECT COUNT(*) FROM #d_hist), N'DAT, HISTORIA'),
        (3, 'CONSECUTIVO', 'dat.FOLIO_CONSECUTIVO', (SELECT COUNT(*) FROM #d_cons), N'TAB7, DAT, HISTORIA'),
        (4, 'PAGOS', 'dat.PAGO_ARRIBADO', (SELECT COUNT(*) FROM #d_pag), N'PAGTOT'),
        (5, 'ETIQUETAS', 'cfg.ETIQUETA', (SELECT COUNT(*) FROM #d_eti), N'ETI, DM1, TOP, STATUS'),
        (6, 'EXCLUSIONES', 'cfg.EXCLUSION', (SELECT COUNT(*) FROM #d_exc), N'EXC486, DIRMAL, EMAILMALO, BLACKLIST')) v(o, d, t, n, s)
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
        IF EXISTS (SELECT 1 FROM @dest WHERE D = 'HISTORIA') AND EXISTS (SELECT 1 FROM @hay WHERE F IN ('DAT', 'HISTORIA'))
        BEGIN
            IF @reemplazar = 0 AND EXISTS (SELECT 1 FROM dat.HISTORIA_FOLIO WHERE CLIENTE = @cliente) THROW 50911, 'dat.HISTORIA_FOLIO ya tiene registros; usa @reemplazar = 1. No se cargó nada.', 1;
            DELETE FROM dat.HISTORIA_FOLIO WHERE CLIENTE = @cliente;
            INSERT INTO dat.HISTORIA_FOLIO (CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA, DATOS_BAJA)
            SELECT CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA, DATOS_BAJA FROM #d_hist;
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
            DELETE FROM cfg.EXCLUSION WHERE CLIENTE = @cliente AND (ORIGEN = @mig OR (ORIGEN IS NULL AND REQ = @mig));
            INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ, ACTIVO, FE_ALTA, ORIGEN)
            SELECT CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ, ACTIVO, ISNULL(FE_ALTA, SYSDATETIME()), @mig FROM #d_exc;
        END;
        COMMIT TRANSACTION;
        /* 20/11: lo migrado trae la llave de FoxPro (en TDC la cuenta armada); pasa a la llave por riesgo */
        IF EXISTS (SELECT 1 FROM @dest WHERE D IN ('DAT', 'HISTORIA'))
            EXEC ops.sp_llave_riesgo_migrar @cliente = @cliente, @confirmar = 1;
        SELECT DESTINO, TABLA, FILAS AS FILAS_CARGADAS FROM #res ORDER BY ORDEN;
        SELECT TEXTO AS AVISO FROM #aviso ORDER BY ID;
        PRINT 'Listo: carga confirmada. Borra los CSV de la carpeta (traen datos de clientes).';
    END;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @drop_e NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(N'DROP TABLE IF EXISTS stg.' + QUOTENAME(N'MIG_' + value) + N';' AS NVARCHAR(MAX)), N' ')
                                         FROM STRING_SPLIT('DAT,TAB7,HISTORIA,PURGA,PAGTOT,ETI,DM1,TOP,STATUS,EXC486,DIRMAL,EMAILMALO,BLACKLIST', ','));
        EXEC (@drop_e);
        THROW;
    END CATCH;

    /* Las tablas de paso traen datos de clientes: no se quedan */
    DECLARE @drop NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(N'DROP TABLE IF EXISTS stg.' + QUOTENAME(N'MIG_' + FUENTE) + N';' AS NVARCHAR(MAX)), N' ') FROM #fuente);
    EXEC (@drop);
END;
GO

/* ---------------------------------------------------------------------
   Cambio de llave por riesgo (20/11). Desde esta versión la llave única del DAT y del histórico (CUENTA) es el
   riesgo en todos los segmentos: con ella se reparten folios y se reconocen reasignadas y retiros. En Consumo e
   Hipotecario ya lo era (CUENTA = crédito = RIESGO); en TDC era la cuenta armada (últimos 4 dígitos de
   PRIME+4DIG + RFC), que ahora se guarda en CTA_BANCO y sigue yendo a CYBER (DMSSNUM, SCBPAG, etiquetas).

   Este procedimiento pasa a la llave nueva lo que ya está cargado (lo que tenga CTA_BANCO vacío):
     - DAT: CTA_BANCO = la CUENTA de antes; en TDC, CUENTA = RIESGO.
     - Histórico: igual, renglón por renglón.
     - Último renglón de la base maestra (vistas): en Consumo e Hipotecario la llave era DES_PROD y pasa a RIESGO.
   Una cuenta TDC sin RIESGO, con RIESGO de más de 20 caracteres o con un RIESGO que ya usa otra cuenta se queda
   con su llave de antes (sale en el resumen): esa cuenta no se va a reconocer en la siguiente base.
   Las corridas de antes ya no se pueden revertir (su respaldo trae la llave vieja): queda LLAVE_RIESGO_MIGRADA.
   Se puede volver a correr: solo toma lo que falta. Lo llama ops.sp_migrar_486 al terminar.
   EXEC ops.sp_llave_riesgo_migrar;                    -- revisa (no cambia nada)
   EXEC ops.sp_llave_riesgo_migrar @confirmar = 1;     -- aplica
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_llave_riesgo_migrar
    @cliente   VARCHAR(10) = '486',
    @confirmar BIT         = 0,
    @mostrar   BIT         = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = @cliente AND ESTATUS = 'EN_PROCESO')
        THROW 50920, 'Hay una corrida en proceso; espera a que termine.', 1;

    /* DAT: cuentas sin pasar */
    SELECT d.CUENTA AS ANT, LTRIM(RTRIM(d.RIESGO)) AS RIESGO, d.SEGMENTO2,
           CAST(CASE WHEN ISNULL(d.SEGMENTO2, '') <> 'TDC' THEN 'SIN CAMBIO (llave = crédito)'
                     WHEN NULLIF(LTRIM(RTRIM(d.RIESGO)), '') IS NULL THEN 'TDC SIN RIESGO (se queda la llave de antes)'
                     WHEN LEN(LTRIM(RTRIM(d.RIESGO))) > 20 THEN 'TDC RIESGO DE MAS DE 20 (se queda la llave de antes)'
                     WHEN LTRIM(RTRIM(d.RIESGO)) = d.CUENTA THEN 'SIN CAMBIO (llave = crédito)'
                     ELSE 'TDC CAMBIA A RIESGO' END AS VARCHAR(60)) AS ESTADO
    INTO #dat
    FROM dat.DAT_486 d WHERE d.CLIENTE = @cliente AND d.CTA_BANCO IS NULL;
    /* RIESGO repetido entre las que cambian, o que ya es la llave de otra cuenta que no cambia */
    UPDATE x SET ESTADO = 'TDC RIESGO REPETIDO (se queda la llave de antes)'
    FROM #dat x
    WHERE x.ESTADO = 'TDC CAMBIA A RIESGO'
      AND ((SELECT COUNT(*) FROM #dat y WHERE y.ESTADO = 'TDC CAMBIA A RIESGO' AND y.RIESGO = x.RIESGO) > 1
           OR EXISTS (SELECT 1 FROM dat.DAT_486 o WHERE o.CLIENTE = @cliente AND o.CUENTA = x.RIESGO
                        AND NOT EXISTS (SELECT 1 FROM #dat z WHERE z.ANT = o.CUENTA AND z.ESTADO = 'TDC CAMBIA A RIESGO')));

    /* Histórico: renglones TDC sin pasar; los de una cuenta del DAT que se queda con la llave de antes, también se quedan */
    SELECT h.ID, h.CUENTA AS ANT, LTRIM(RTRIM(h.RIESGO)) AS RIESGO,
           CAST(CASE WHEN ISNULL(h.SEGMENTO2, '') <> 'TDC' THEN 'SIN CAMBIO'
                     WHEN NULLIF(LTRIM(RTRIM(h.RIESGO)), '') IS NULL OR LEN(LTRIM(RTRIM(h.RIESGO))) > 20 THEN 'TDC SE QUEDA (sin RIESGO válido)'
                     WHEN EXISTS (SELECT 1 FROM #dat k WHERE k.ANT = h.CUENTA AND k.ESTADO LIKE 'TDC%' AND k.ESTADO <> 'TDC CAMBIA A RIESGO') THEN 'TDC SE QUEDA (su cuenta del DAT se queda)'
                     WHEN LTRIM(RTRIM(h.RIESGO)) = h.CUENTA THEN 'SIN CAMBIO'
                     ELSE 'TDC CAMBIA A RIESGO' END AS VARCHAR(60)) AS ESTADO
    INTO #his
    FROM dat.HISTORIA_FOLIO h WHERE h.CLIENTE = @cliente AND h.CTA_BANCO IS NULL;

    /* Base maestra por cuenta (Consumo e Hipotecario): DES_PROD -> RIESGO */
    SELECT b.CODIGO, b.LLAVE AS ANT, CAST(MIN(LTRIM(RTRIM(d.RIESGO))) AS NVARCHAR(60)) AS NUEVA
    INTO #bmc
    FROM dat.BASE_MAESTRA_CUENTA b
    JOIN cfg.ARCHIVO a ON a.CLIENTE = b.CLIENTE AND a.CODIGO = b.CODIGO AND a.LLAVE_DAT = 'RIESGO' AND a.SEGMENTO2 <> 'TDC'
    JOIN dat.DAT_486 d ON d.CLIENTE = b.CLIENTE AND d.SEGMENTO2 = a.SEGMENTO2 AND d.DES_PROD = b.LLAVE
    WHERE b.CLIENTE = @cliente AND NULLIF(LTRIM(RTRIM(d.RIESGO)), '') IS NOT NULL AND LTRIM(RTRIM(d.RIESGO)) <> b.LLAVE
    GROUP BY b.CODIGO, b.LLAVE;
    DELETE x FROM #bmc x
    WHERE (SELECT COUNT(*) FROM #bmc y WHERE y.CODIGO = x.CODIGO AND y.NUEVA = x.NUEVA) > 1
       OR EXISTS (SELECT 1 FROM dat.BASE_MAESTRA_CUENTA o WHERE o.CLIENTE = @cliente AND o.CODIGO = x.CODIGO AND o.LLAVE = x.NUEVA);

    IF @mostrar = 1
    BEGIN
        SELECT 'DAT' AS TABLA, ESTADO, SEGMENTO2, COUNT(*) AS CUENTAS FROM #dat GROUP BY ESTADO, SEGMENTO2
        UNION ALL SELECT 'HISTORICO', ESTADO, NULL, COUNT(*) FROM #his GROUP BY ESTADO
        UNION ALL SELECT 'BASE MAESTRA POR CUENTA', 'CONSUMO / HIPOTECARIO A RIESGO', NULL, COUNT(*) FROM #bmc
        ORDER BY 1, 2, 3;
        IF @confirmar = 0 PRINT 'Solo revisión: no se cambió nada. Ejecuta con @confirmar = 1 para aplicar.';
    END;
    IF @confirmar = 0 RETURN;

    DECLARE @ult INT = ISNULL((SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE CLIENTE = @cliente), 0);
    BEGIN TRANSACTION;
        UPDATE d SET CTA_BANCO = LEFT(x.ANT, 20), CUENTA = CASE WHEN x.ESTADO = 'TDC CAMBIA A RIESGO' THEN x.RIESGO ELSE d.CUENTA END
        FROM dat.DAT_486 d JOIN #dat x ON x.ANT = d.CUENTA
        WHERE d.CLIENTE = @cliente AND d.CTA_BANCO IS NULL;
        UPDATE h SET CTA_BANCO = LEFT(x.ANT, 20), CUENTA = CASE WHEN x.ESTADO = 'TDC CAMBIA A RIESGO' THEN x.RIESGO ELSE h.CUENTA END
        FROM dat.HISTORIA_FOLIO h JOIN #his x ON x.ID = h.ID;
        /* Devoluciones pendientes de revisar: con la llave nueva */
        UPDATE v SET CUENTA = x.RIESGO
        FROM ops.DEVOLUCION v JOIN #dat x ON x.ANT = v.CUENTA AND x.ESTADO = 'TDC CAMBIA A RIESGO'
        WHERE v.CLIENTE = @cliente AND v.PROCESADA = 0;
        UPDATE b SET LLAVE = x.NUEVA
        FROM dat.BASE_MAESTRA_CUENTA b JOIN #bmc x ON x.CODIGO = b.CODIGO AND x.ANT = b.LLAVE
        WHERE b.CLIENTE = @cliente;
        IF EXISTS (SELECT 1 FROM cfg.PARAMETRO WHERE CLIENTE = @cliente AND CLAVE = 'LLAVE_RIESGO_MIGRADA')
            UPDATE cfg.PARAMETRO SET VALOR = CAST(@ult AS VARCHAR(20)) WHERE CLIENTE = @cliente AND CLAVE = 'LLAVE_RIESGO_MIGRADA'
              AND ISNULL(TRY_CONVERT(INT, VALOR), 0) < @ult;
        ELSE
            INSERT INTO cfg.PARAMETRO (CLIENTE, CLAVE, VALOR, DESCRIPCION)
            VALUES (@cliente, 'LLAVE_RIESGO_MIGRADA', CAST(@ult AS VARCHAR(20)),
                    N'Última corrida antes del cambio de llave por riesgo (20/11): esa y las anteriores ya no se pueden revertir. Lo escribe ops.sp_llave_riesgo_migrar');
    COMMIT TRANSACTION;
    IF @mostrar = 1
        SELECT 'APLICADO' AS RESULTADO,
               (SELECT COUNT(*) FROM #dat WHERE ESTADO = 'TDC CAMBIA A RIESGO') AS DAT_TDC_A_RIESGO,
               (SELECT COUNT(*) FROM #dat WHERE ESTADO LIKE 'TDC%' AND ESTADO <> 'TDC CAMBIA A RIESGO') AS DAT_TDC_SE_QUEDAN,
               (SELECT COUNT(*) FROM #his WHERE ESTADO = 'TDC CAMBIA A RIESGO') AS HISTORICO_A_RIESGO,
               (SELECT COUNT(*) FROM #bmc) AS BASE_MAESTRA_A_RIESGO;
END;
GO
