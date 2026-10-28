/* =====================================================================
   Banbaj · 20 Stored procedures comunes
   ---------------------------------------------------------------------
   ops.sp_log               bitácora por paso
   ops.sp_corrida_iniciar   abre una corrida (ASIG / ACT)
   ops.sp_corrida_finalizar cierra la corrida
   ops.sp_cargar_archivo    carga dinámica de UN archivo (versión corregida de SQLQuery1)
   ops.sp_cargar_proceso    carga todos los archivos activos del proceso
   ops.sp_homologar         aplica cfg.HOMOLOGACION
   ops.sp_validar           aplica cfg.REGLA de un paso
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_log
    @id_corrida INT,
    @paso       VARCHAR(80),
    @estatus    VARCHAR(15),
    @registros  INT            = NULL,
    @mensaje    NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ops.BITACORA (ID_CORRIDA, PASO, ESTATUS, REGISTROS, MENSAJE)
    VALUES (@id_corrida, @paso, @estatus, @registros, @mensaje);
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_corrida_iniciar
    @cliente      VARCHAR(10),
    @proceso      VARCHAR(10),
    @fecha        DATE    = NULL,
    @hora_llegada TIME(0) = NULL,
    @id_corrida   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM ops.CORRIDA
               WHERE CLIENTE = @cliente AND PROCESO = @proceso AND ESTATUS = 'EN_PROCESO')
        THROW 50010, 'Ya hay una corrida en proceso para este cliente y proceso. Ciérrala con ops.sp_corrida_finalizar antes de iniciar otra.', 1;

    INSERT INTO ops.CORRIDA (CLIENTE, PROCESO, FECHA_PROCESO, HORA_LLEGADA)
    VALUES (@cliente, @proceso, ISNULL(@fecha, CAST(GETDATE() AS DATE)), @hora_llegada);
    SET @id_corrida = SCOPE_IDENTITY();
    EXEC ops.sp_log @id_corrida, 'CORRIDA', 'INICIO';
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_corrida_finalizar
    @id_corrida INT,
    @estatus    VARCHAR(15),
    @mensaje    NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE ops.CORRIDA SET ESTATUS = @estatus, FIN = SYSDATETIME(), MENSAJE = @mensaje
    WHERE ID_CORRIDA = @id_corrida;
    EXEC ops.sp_log @id_corrida, 'CORRIDA', @estatus, NULL, @mensaje;
END;
GO

/* ---------------------------------------------------------------------
   Carga dinámica de un archivo.
   Correcciones respecto a SQLQuery1.sql (cliente 526):
   1. La tabla destino se recrea en cada carga: nunca se mezclan días.
   2. FORMAT='CSV' con comillas para txt y csv: "9,999.99" no recorre columnas.
   3. CODEPAGE y fin de línea por archivo (catálogo).
   4. Encabezados localizados por patrón: soporta fechas en el nombre de la columna.
   5. Conversión con TRY_CONVERT: lo que no convierte va a ops.RECHAZO, no aborta todo.
   6. Una fila de ops.ARCHIVO_CARGADO por archivo con leídos / insertados / rechazados.
   7. El nombre del archivo se busca en la carpeta (xp_dirtree) por patrón; si hay
      varios se toma el último por nombre.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_cargar_archivo
    @id_corrida INT,
    @id_archivo INT,
    @recibido   BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @recibido = 0;

    DECLARE @cliente VARCHAR(10), @codigo VARCHAR(50), @ruta NVARCHAR(400), @patron NVARCHAR(200),
            @sep VARCHAR(5), @comillas BIT, @codepage VARCHAR(10), @fdl VARCHAR(10), @fila_enc INT,
            @ncols INT, @destino SYSNAME, @obligatorio BIT, @fecha DATE, @err NVARCHAR(4000);

    SELECT @cliente = a.CLIENTE, @codigo = a.CODIGO, @ruta = a.RUTA, @patron = a.PATRON_NOMBRE,
           @sep = a.SEPARADOR, @comillas = a.CON_COMILLAS, @codepage = a.CODEPAGE, @fdl = a.FIN_DE_LINEA,
           @fila_enc = a.FILA_ENCABEZADO, @ncols = a.NUM_COLUMNAS, @destino = a.TABLA_DESTINO,
           @obligatorio = a.OBLIGATORIO, @fecha = c.FECHA_PROCESO
    FROM cfg.ARCHIVO a
    JOIN ops.CORRIDA c ON c.ID_CORRIDA = @id_corrida
    WHERE a.ID_ARCHIVO = @id_archivo;

    IF @codigo IS NULL THROW 50020, 'Archivo no encontrado en cfg.ARCHIVO.', 1;

    DECLARE @paso VARCHAR(80) = 'CARGA ' + @codigo;
    DECLARE @dest_schema SYSNAME = ISNULL(PARSENAME(@destino, 2), 'stg'),
            @dest_tabla  SYSNAME = PARSENAME(@destino, 1);
    DECLARE @dest_q NVARCHAR(300) = QUOTENAME(@dest_schema) + N'.' + QUOTENAME(@dest_tabla);
    DECLARE @raw_q  NVARCHAR(300) = N'stg.' + QUOTENAME(N'RAW_' + @codigo);
    DECLARE @rawv_q NVARCHAR(300) = N'stg.' + QUOTENAME(N'v_RAW_' + @codigo);

    /* 1. Localiza el archivo en la carpeta */
    SET @patron = REPLACE(REPLACE(REPLACE(@patron,
                  N'{AAAAMMDD}',   CONVERT(CHAR(8), @fecha, 112)),
                  N'{DD-MM-AAAA}', REPLACE(CONVERT(CHAR(10), @fecha, 105), '.', '-')),
                  N'{AAAA-MM-DD}', CONVERT(CHAR(10), @fecha, 23));

    DECLARE @dir TABLE (subdirectory NVARCHAR(512), depth INT, [file] INT);
    INSERT INTO @dir EXEC master.sys.xp_dirtree @ruta, 1, 1;

    DECLARE @archivo NVARCHAR(512) =
        (SELECT TOP (1) subdirectory FROM @dir
         WHERE [file] = 1 AND subdirectory LIKE @patron COLLATE Latin1_General_CI_AI
         ORDER BY subdirectory DESC);

    IF @archivo IS NULL
    BEGIN
        INSERT INTO ops.ARCHIVO_CARGADO (ID_CORRIDA, ID_ARCHIVO, RUTA, ESTATUS)
        VALUES (@id_corrida, @id_archivo, @ruta + @patron, 'NO_RECIBIDO');
        EXEC ops.sp_log @id_corrida, @paso, 'AVISO', 0, N'No se encontró el archivo con el patrón indicado.';
        IF @obligatorio = 1
            THROW 50021, 'Falta un archivo obligatorio; revisa ops.ARCHIVO_CARGADO.', 1;
        RETURN;
    END;

    DECLARE @path NVARCHAR(1000) = @ruta + @archivo;
    EXEC ops.sp_log @id_corrida, @paso, 'INICIO', NULL, @path;

    /* 2. Staging crudo: ID + c001..cNNN, todo texto */
    DECLARE @sql NVARCHAR(MAX), @cols NVARCHAR(MAX) = N'', @colsdef NVARCHAR(MAX) = N'', @i INT = 1;
    WHILE @i <= @ncols
    BEGIN
        SET @cols    += CASE WHEN @i > 1 THEN N',' ELSE N'' END + N'c' + RIGHT(N'000' + CAST(@i AS NVARCHAR(4)), 3);
        SET @colsdef += N', c' + RIGHT(N'000' + CAST(@i AS NVARCHAR(4)), 3) + N' NVARCHAR(4000) NULL';
        SET @i += 1;
    END;

    SET @sql = N'DROP VIEW IF EXISTS ' + @rawv_q + N'; DROP TABLE IF EXISTS ' + @raw_q + N';'
             + N'CREATE TABLE ' + @raw_q + N' (ID INT IDENTITY(1,1) NOT NULL' + @colsdef + N');';
    EXEC (@sql);
    -- La vista permite que BULK INSERT llene solo las columnas de texto y el
    -- IDENTITY conserve el orden de las filas del archivo.
    SET @sql = N'CREATE VIEW ' + @rawv_q + N' AS SELECT ' + @cols + N' FROM ' + @raw_q + N';';
    EXEC (@sql);

    SET @sql = N'BULK INSERT ' + @rawv_q + N' FROM ' + QUOTENAME(@path, '''') + N' WITH ('
             + CASE WHEN @comillas = 1 THEN N'FORMAT = ''CSV'', FIELDQUOTE = ''"'', ' ELSE N'' END
             + N'FIELDTERMINATOR = ' + QUOTENAME(@sep, '''')
             + N', ROWTERMINATOR = ' + QUOTENAME(@fdl, '''')
             + CASE WHEN NULLIF(@codepage, '') IS NOT NULL THEN N', CODEPAGE = ' + QUOTENAME(@codepage, '''') ELSE N'' END
             + N', FIRSTROW = 1, KEEPNULLS);';
    BEGIN TRY
        EXEC (@sql);
    END TRY
    BEGIN CATCH
        SET @err = N'BULK INSERT falló (revisa NUM_COLUMNAS, separador y codificación): ' + ERROR_MESSAGE();
        INSERT INTO ops.ARCHIVO_CARGADO (ID_CORRIDA, ID_ARCHIVO, RUTA, ESTATUS) VALUES (@id_corrida, @id_archivo, @path, 'ERROR');
        EXEC ops.sp_log @id_corrida, @paso, 'ERROR', NULL, @err;
        THROW 50022, @err, 1;
    END CATCH;

    /* 3. Encabezados -> posición de cada columna del catálogo */
    CREATE TABLE #hdr (POS INT, NOMBRE NVARCHAR(4000));
    SET @sql = N'INSERT INTO #hdr (POS, NOMBRE) SELECT v.POS, cfg.fn_texto(v.NOMBRE) FROM ' + @raw_q
             + N' r CROSS APPLY (VALUES ';
    SET @i = 1;
    WHILE @i <= @ncols
    BEGIN
        SET @sql += CASE WHEN @i > 1 THEN N',' ELSE N'' END
                  + N'(' + CAST(@i AS NVARCHAR(4)) + N', r.c' + RIGHT(N'000' + CAST(@i AS NVARCHAR(4)), 3) + N')';
        SET @i += 1;
    END;
    SET @sql += N') v(POS, NOMBRE) WHERE r.ID = @fila;';
    EXEC sp_executesql @sql, N'@fila INT', @fila = @fila_enc;

    CREATE TABLE #map (CAMPO SYSNAME, POS INT NULL, TIPO_SQL VARCHAR(50), TRANSF NVARCHAR(1000),
                       OBLIGATORIO BIT, DERIVADO BIT);
    INSERT INTO #map (CAMPO, POS, TIPO_SQL, TRANSF, OBLIGATORIO, DERIVADO)
    SELECT  c.CAMPO_DESTINO,
            COALESCE(c.POSICION,
                     (SELECT MIN(h.POS) FROM #hdr h
                      WHERE UPPER(h.NOMBRE) COLLATE Latin1_General_CI_AI LIKE UPPER(c.PATRON_ENCABEZADO) COLLATE Latin1_General_CI_AI)),
            c.TIPO_SQL, c.TRANSFORMACION, c.OBLIGATORIO,
            CASE WHEN c.PATRON_ENCABEZADO IS NULL AND c.POSICION IS NULL THEN 1 ELSE 0 END
    FROM cfg.ARCHIVO_COLUMNA c
    WHERE c.ID_ARCHIVO = @id_archivo AND c.ACTIVO = 1;

    DECLARE @faltan NVARCHAR(4000) =
        (SELECT STRING_AGG(CAMPO, ', ') FROM #map WHERE POS IS NULL AND DERIVADO = 0 AND OBLIGATORIO = 1);
    IF @faltan IS NOT NULL
    BEGIN
        SET @err = N'Encabezados obligatorios no encontrados: ' + @faltan;
        INSERT INTO ops.ARCHIVO_CARGADO (ID_CORRIDA, ID_ARCHIVO, RUTA, ESTATUS) VALUES (@id_corrida, @id_archivo, @path, 'ERROR');
        EXEC ops.sp_log @id_corrida, @paso, 'ERROR', NULL, @err;
        THROW 50023, @err, 1;
    END;
    DECLARE @opcionales NVARCHAR(4000) =
        (SELECT STRING_AGG(CAMPO, ', ') FROM #map WHERE POS IS NULL AND DERIVADO = 0 AND OBLIGATORIO = 0);
    IF @opcionales IS NOT NULL
    BEGIN
        SET @err = N'Encabezados opcionales no encontrados (quedan vacíos): ' + @opcionales;
        EXEC ops.sp_log @id_corrida, @paso, 'AVISO', NULL, @err;
    END

    /* 4. Tabla destino tipada (se recrea) */
    DECLARE @def NVARCHAR(MAX) =
        (SELECT STRING_AGG(CAST(QUOTENAME(CAMPO) + N' ' + TIPO_SQL + N' NULL' AS NVARCHAR(MAX)), N', ') FROM #map);
    SET @sql = N'DROP TABLE IF EXISTS ' + @dest_q + N'; CREATE TABLE ' + @dest_q
             + N' (ID_CORRIDA INT NOT NULL, FILA INT NOT NULL, ' + @def + N', MOTIVO_RECHAZO NVARCHAR(1000) NULL);';
    EXEC (@sql);

    /* 5. Inserta convirtiendo; arma el motivo de rechazo en el mismo paso */
    DECLARE @lista NVARCHAR(MAX), @exprs NVARCHAR(MAX), @motivo NVARCHAR(MAX);
    SELECT
        @lista = STRING_AGG(CAST(QUOTENAME(CAMPO) AS NVARCHAR(MAX)), N', '),
        @exprs = STRING_AGG(CAST(
                    CASE WHEN POS IS NULL THEN N'CAST(NULL AS ' + TIPO_SQL + N')'
                         ELSE N'TRY_CONVERT(' + TIPO_SQL + N', '
                              + REPLACE(TRANSF, N'{v}', N'cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3) + N')')
                              + N')'
                    END + N' AS ' + QUOTENAME(CAMPO) AS NVARCHAR(MAX)), N', '),
        /* Solo las columnas OBLIGATORIAS rechazan el renglón (vacías o no convertibles).
           En las opcionales un valor no convertible queda NULL y se reporta como aviso. */
        @motivo = STRING_AGG(CAST(
                    CASE WHEN POS IS NOT NULL AND OBLIGATORIO = 1 THEN
                        N'CASE WHEN x.' + QUOTENAME(CAMPO) + N' IS NULL AND cfg.fn_texto(r.c'
                        + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3) + N') IS NOT NULL THEN N''' + CAMPO + N' inválido; '' END, '
                        + N'CASE WHEN cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3)
                        + N') IS NULL THEN N''' + CAMPO + N' vacío; '' END'
                    END AS NVARCHAR(MAX)), N', ')
    FROM #map;

    SET @sql = N'INSERT INTO ' + @dest_q + N' (ID_CORRIDA, FILA, ' + @lista + N', MOTIVO_RECHAZO) '
             + N'SELECT @id_corrida, r.ID, ' + (SELECT STRING_AGG(CAST(N'x.' + QUOTENAME(CAMPO) AS NVARCHAR(MAX)), N', ') FROM #map)
             + N', NULLIF(CONCAT(N'''', ' + ISNULL(@motivo, N'N''''') + N'), N'''') '
             + N'FROM ' + @raw_q + N' r CROSS APPLY (SELECT ' + @exprs + N') x '
             + N'WHERE r.ID > @fila AND COALESCE(' + (SELECT STRING_AGG(CAST(N'cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3) + N')' AS NVARCHAR(MAX)), N', ') FROM #map WHERE POS IS NOT NULL) + N', NULL) IS NOT NULL; SET @n = @@ROWCOUNT;';
    DECLARE @leidos INT;
    EXEC sp_executesql @sql, N'@id_corrida INT, @fila INT, @n INT OUTPUT', @id_corrida = @id_corrida, @fila = @fila_enc, @n = @leidos OUTPUT;

    /* 6. Rechazos -> ops.RECHAZO (con el renglón crudo en JSON) y se quitan del destino */
    SET @sql = N'INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, FILA, MOTIVO, DATOS) '
             + N'SELECT d.ID_CORRIDA, @codigo, d.FILA, d.MOTIVO_RECHAZO, '
             + N'(SELECT r.* FROM ' + @raw_q + N' r WHERE r.ID = d.FILA FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) '
             + N'FROM ' + @dest_q + N' d WHERE d.MOTIVO_RECHAZO IS NOT NULL; '
             + N'DELETE FROM ' + @dest_q + N' WHERE MOTIVO_RECHAZO IS NOT NULL; '
             + N'SELECT @n = COUNT(*) FROM ' + @dest_q + N';';
    DECLARE @insertados INT;
    EXEC sp_executesql @sql, N'@codigo VARCHAR(50), @n INT OUTPUT', @codigo = @codigo, @n = @insertados OUTPUT;

    /* Aviso: valores no convertibles en columnas opcionales (quedaron NULL) */
    DECLARE @avisos NVARCHAR(MAX) =
        (SELECT STRING_AGG(CAST(N'SELECT ' + QUOTENAME(CAMPO, '''') + N' AS CAMPO, COUNT(*) AS N FROM ' + @raw_q + N' r '
                + N'CROSS APPLY (SELECT TRY_CONVERT(' + TIPO_SQL + N', '
                + REPLACE(TRANSF, N'{v}', N'cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3) + N')')
                + N') AS V) x WHERE r.ID > @fila AND x.V IS NULL AND cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3)
                + N') NOT IN (N''-'') AND cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3) + N') IS NOT NULL' AS NVARCHAR(MAX)),
                N' UNION ALL ')
         FROM #map WHERE POS IS NOT NULL AND OBLIGATORIO = 0 AND TIPO_SQL NOT LIKE '%CHAR%');
    IF @avisos IS NOT NULL
    BEGIN
        SET @sql = N'SELECT @txt = STRING_AGG(CONCAT(CAMPO, N'': '', N), N'', '') FROM (' + @avisos + N') a WHERE N > 0;';
        DECLARE @txt NVARCHAR(4000);
        EXEC sp_executesql @sql, N'@fila INT, @txt NVARCHAR(4000) OUTPUT', @fila = @fila_enc, @txt = @txt OUTPUT;
        IF @txt IS NOT NULL
        BEGIN
            SET @err = N'Valores no convertibles en columnas opcionales (quedan vacíos): ' + @txt;
            EXEC ops.sp_log @id_corrida, @paso, 'AVISO', NULL, @err;
        END;
    END;

    INSERT INTO ops.ARCHIVO_CARGADO (ID_CORRIDA, ID_ARCHIVO, RUTA, LEIDOS, INSERTADOS, RECHAZADOS, ESTATUS)
    VALUES (@id_corrida, @id_archivo, @path, @leidos, @insertados, @leidos - @insertados, 'CARGADO');
    SET @err = CONCAT(N'Leídos: ', @leidos, N' · rechazados: ', @leidos - @insertados);
    EXEC ops.sp_log @id_corrida, @paso, 'OK', @insertados, @err;
    SET @recibido = 1;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_cargar_proceso
    @id_corrida INT,
    @recibidos  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10);
    SELECT @cliente = CLIENTE, @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;

    SET @recibidos = 0;
    DECLARE @id INT, @ok BIT;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ID_ARCHIVO FROM cfg.ARCHIVO
        WHERE CLIENTE = @cliente AND PROCESO = @proceso AND ACTIVO = 1
        ORDER BY ORDEN, ID_ARCHIVO;
    OPEN cur;
    FETCH NEXT FROM cur INTO @id;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC ops.sp_cargar_archivo @id_corrida, @id, @ok OUTPUT;
        SET @recibidos += @ok;
        FETCH NEXT FROM cur INTO @id;
    END;
    CLOSE cur; DEALLOCATE cur;

    IF @recibidos = 0
        THROW 50024, 'No se recibió ningún archivo para este proceso.', 1;
END;
GO

/* ---------------------------------------------------------------------
   Homologación: ejecuta cfg.HOMOLOGACION en ORDEN sobre las tablas que
   existen en esta corrida (si un segmento no llegó, su tabla no existe
   o no tiene filas de esta corrida y se omite).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_homologar
    @id_corrida INT,
    @tabla      SYSNAME = NULL          -- NULL = todas las del proceso
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @proceso = PROCESO, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;

    DECLARE @id INT, @t SYSNAME, @campo SYSNAME, @valor NVARCHAR(1000), @cond NVARCHAR(1000), @desc NVARCHAR(400),
            @sql NVARCHAR(MAX), @n INT, @total INT = 0, @reglas INT = 0, @err NVARCHAR(4000);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ID, TABLA, CAMPO_DESTINO, VALOR, CONDICION, DESCRIPCION
        FROM cfg.HOMOLOGACION
        WHERE CLIENTE = @cliente AND PROCESO = @proceso AND ACTIVO = 1
          AND (@tabla IS NULL OR TABLA = @tabla)
          AND OBJECT_ID(TABLA) IS NOT NULL
        ORDER BY TABLA, ORDEN, ID;
    OPEN cur;
    FETCH NEXT FROM cur INTO @id, @t, @campo, @valor, @cond, @desc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @valor = REPLACE(REPLACE(@valor, N'{FECHA}', CONVERT(CHAR(8), @fecha, 112)), N'{CLIENTE}', @cliente);
        SET @cond  = REPLACE(REPLACE(@cond,  N'{FECHA}', CONVERT(CHAR(8), @fecha, 112)), N'{CLIENTE}', @cliente);
        SET @sql = N'UPDATE t SET ' + QUOTENAME(@campo) + N' = ' + @valor
                 + N' FROM ' + QUOTENAME(PARSENAME(@t, 2)) + N'.' + QUOTENAME(PARSENAME(@t, 1)) + N' t'
                 + N' WHERE t.ID_CORRIDA = @id_corrida'
                 + CASE WHEN @cond IS NOT NULL THEN N' AND (' + @cond + N')' ELSE N'' END + N'; SET @n = @@ROWCOUNT;';
        BEGIN TRY
            EXEC sp_executesql @sql, N'@id_corrida INT, @n INT OUTPUT', @id_corrida = @id_corrida, @n = @n OUTPUT;
        END TRY
        BEGIN CATCH
            SET @err = CONCAT(N'Homologación ID ', @id, N' (', @t, N'.', @campo, N'): ', ERROR_MESSAGE());
            EXEC ops.sp_log @id_corrida, 'HOMOLOGACION', 'ERROR', NULL, @err;
            THROW 50030, @err, 1;
        END CATCH;
        SET @total += @n; SET @reglas += 1;
        FETCH NEXT FROM cur INTO @id, @t, @campo, @valor, @cond, @desc;
    END;
    CLOSE cur; DEALLOCATE cur;
    SET @err = CONCAT(@reglas, N' reglas aplicadas', ISNULL(N' sobre ' + @tabla, N''));
    EXEC ops.sp_log @id_corrida, 'HOMOLOGACION', 'OK', @total, @err;
END;
GO

/* ---------------------------------------------------------------------
   Validación por paso (cfg.REGLA).
   Las tablas stg.* se filtran por ID_CORRIDA; las tablas dat.* se evalúan completas.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_validar
    @id_corrida INT,
    @paso       VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @proceso = PROCESO, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;

    DECLARE @id INT, @codigo VARCHAR(60), @t SYSNAME, @cond NVARCHAR(2000), @evalua VARCHAR(10), @umbral INT,
            @accion VARCHAR(10), @msg NVARCHAR(400), @plantilla VARCHAR(60),
            @sql NVARCHAR(MAX), @from NVARCHAR(MAX), @n INT, @disparada BIT, @cancelar NVARCHAR(4000) = NULL;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ID, CODIGO, TABLA, CONDICION, EVALUA, UMBRAL, ACCION, MENSAJE, PLANTILLA_CORREO
        FROM cfg.REGLA
        WHERE CLIENTE = @cliente AND PROCESO = @proceso AND PASO = @paso AND ACTIVO = 1
          AND OBJECT_ID(TABLA) IS NOT NULL
        ORDER BY ORDEN, ID;
    OPEN cur;
    FETCH NEXT FROM cur INTO @id, @codigo, @t, @cond, @evalua, @umbral, @accion, @msg, @plantilla;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cond = REPLACE(REPLACE(@cond, N'{FECHA}', CONVERT(CHAR(8), @fecha, 112)), N'{CLIENTE}', @cliente);
        SET @from = N' FROM ' + QUOTENAME(PARSENAME(@t, 2)) + N'.' + QUOTENAME(PARSENAME(@t, 1)) + N' t WHERE ('
                  + @cond + N')'
                  + CASE WHEN PARSENAME(@t, 2) = 'stg' THEN N' AND t.ID_CORRIDA = @id_corrida' ELSE N'' END;

        SET @sql = N'SELECT @n = COUNT(*)' + @from + N';';
        EXEC sp_executesql @sql, N'@id_corrida INT, @n INT OUTPUT', @id_corrida = @id_corrida, @n = @n OUTPUT;

        SET @disparada = CASE WHEN @evalua = 'FILAS' AND @n >= @umbral THEN 1
                              WHEN @evalua = 'SIN_FILAS' AND @n = 0 THEN 1 ELSE 0 END;
        IF @disparada = 1
        BEGIN
            DECLARE @est VARCHAR(15) = CASE WHEN @accion = 'CANCELAR' THEN 'ERROR' ELSE 'AVISO' END;
            EXEC ops.sp_log @id_corrida, @codigo, @est, @n, @msg;

            IF @accion = 'EXCLUIR'
            BEGIN
                SET @sql = N'INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, FILA, MOTIVO, DATOS) '
                         + N'SELECT @id_corrida, @codigo, NULL, @msg, (SELECT t.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)' + @from + N'; '
                         + N'DELETE t' + @from + N';';
                EXEC sp_executesql @sql, N'@id_corrida INT, @codigo VARCHAR(60), @msg NVARCHAR(400)',
                     @id_corrida = @id_corrida, @codigo = @codigo, @msg = @msg;
            END
            ELSE IF @accion = 'DEVOLVER'
            BEGIN
                SET @sql = N'INSERT INTO ops.DEVOLUCION (ID_CORRIDA, CLIENTE, CUENTA, SEGMENTO2, MOTIVO, ORIGEN) '
                         + N'SELECT DISTINCT @id_corrida, @cliente, t.CUENTA, t.SEGMENTO2, @msg, @codigo' + @from
                         + N' AND t.CUENTA IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ops.DEVOLUCION x WHERE x.ID_CORRIDA = @id_corrida AND x.CUENTA = t.CUENTA);';
                EXEC sp_executesql @sql, N'@id_corrida INT, @cliente VARCHAR(10), @codigo VARCHAR(60), @msg NVARCHAR(400)',
                     @id_corrida = @id_corrida, @cliente = @cliente, @codigo = @codigo, @msg = @msg;
            END
            ELSE IF @accion = 'CANCELAR'
                SET @cancelar = CONCAT(@cancelar, @msg, N' (', @n, N'); ');

            IF @plantilla IS NOT NULL
            BEGIN
                DECLARE @json NVARCHAR(MAX) = (SELECT @codigo AS REGLA, @msg AS MENSAJE, @n AS REGISTROS FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
                EXEC mail.sp_enviar @plantilla = @plantilla, @id_corrida = @id_corrida, @valores = @json;
            END;
        END;
        FETCH NEXT FROM cur INTO @id, @codigo, @t, @cond, @evalua, @umbral, @accion, @msg, @plantilla;
    END;
    CLOSE cur; DEALLOCATE cur;

    IF @cancelar IS NOT NULL
        THROW 50040, @cancelar, 1;
END;
GO
