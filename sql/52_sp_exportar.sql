/* =====================================================================
   Banbaj · 52 Escribir en disco los archivos planos y scripts de CYBER
   ---------------------------------------------------------------------
   Sustituye a tools/exportar_salidas.py (Python): todo corre en SQL Server.

       EXEC ops.sp_exportar_salidas @id_corrida = 125;                    -- todos los archivos de la corrida
       EXEC ops.sp_exportar_salidas @id_corrida = 130, @zip = 'RETIROS';  -- + ZIP con contraseña en C:\
       EXEC ops.sp_exportar_salidas @id_corrida = 130, @zip = 'RETIROS', @enviar_zip = 1;   -- + correo único de devolución
       EXEC ops.sp_exportar_salidas @id_corrida = 125, @solo_mostrar = 1; -- qué escribiría, sin tocar el disco

   - Carpeta: <RUTA_SALIDA>\<AAAAMMDD>_corrida<ID>\ ; los scripts de CYBER en \cyber\.
   - Nombre, codificación y fin de línea de cfg.SALIDA_ARCHIVO (Windows-1252 y CRLF, como COPY TO … SDF).
   - Los archivos se escriben con automatización OLE (ADODB.Stream y Scripting.FileSystemObject).
   - ZIP de retiros: 7-Zip por xp_cmdshell, ZipCrypto (abre en el Explorador de Windows, como hoy).
     Contraseña: credencial ZIP_RETIROS (INSERT INTO cfg.CAPTURA_CREDENCIAL … ('ZIP_RETIROS', 'zip', '*Bajio{MM}{AAAA}')).
     {MM} y {AAAA} se reemplazan por el mes y el año del día.

   Requisitos en el servidor (una vez, lo hace un administrador):
     EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
     EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE;
     EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;            -- solo para el ZIP
     La cuenta del servicio de SQL Server debe poder escribir en RUTA_SALIDA y en C:\ (ZIP).
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Error de automatización OLE: toma el detalle, libera el objeto y lanza el error */
CREATE OR ALTER PROCEDURE ops.sp_oa_error
    @obj INT,
    @hr  INT,
    @que NVARCHAR(400)
AS
BEGIN
    DECLARE @fuente NVARCHAR(255), @desc NVARCHAR(2000), @msg NVARCHAR(4000);
    IF @obj IS NOT NULL
    BEGIN
        EXEC sp_OAGetErrorInfo @obj, @fuente OUT, @desc OUT;
        EXEC sp_OADestroy @obj;
    END;
    SET @msg = CONCAT(N'No se pudo ', @que, N' (0x', CONVERT(VARCHAR(10), CAST(@hr AS VARBINARY(4)), 2), N' ', ISNULL(@desc, N''), N'). ',
                      N'¿Está activado ''Ole Automation Procedures'' y la cuenta de SQL Server puede escribir ahí?');
    THROW 50850, @msg, 1;
END;
GO

/* Crea la carpeta y las que falten arriba de ella (C:\a\b\ o \\servidor\recurso\a\) */
CREATE OR ALTER PROCEDURE ops.sp_crear_carpeta
    @ruta NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @fso INT, @hr INT, @existe INT, @i INT, @parcial NVARCHAR(400);
    SET @ruta = RTRIM(@ruta);
    IF RIGHT(@ruta, 1) <> N'\' SET @ruta += N'\';
    -- la primera carpeta que se puede crear va después de "C:\" o de "\\servidor\recurso\"
    SET @i = CASE WHEN @ruta LIKE N'\\%' THEN CHARINDEX(N'\', @ruta, CHARINDEX(N'\', @ruta, 3) + 1) ELSE 3 END;
    EXEC @hr = sp_OACreate 'Scripting.FileSystemObject', @fso OUT;
    IF @hr <> 0 EXEC ops.sp_oa_error NULL, @hr, N'crear Scripting.FileSystemObject';
    SET @i = CHARINDEX(N'\', @ruta, @i + 1);
    WHILE @i > 0
    BEGIN
        SET @parcial = LEFT(@ruta, @i);
        EXEC @hr = sp_OAMethod @fso, 'FolderExists', @existe OUT, @parcial;
        IF @hr = 0 AND @existe = 0 EXEC @hr = sp_OAMethod @fso, 'CreateFolder', NULL, @parcial;
        IF @hr <> 0 EXEC ops.sp_oa_error @fso, @hr, N'crear la carpeta';
        SET @i = CHARINDEX(N'\', @ruta, @i + 1);
    END;
    EXEC sp_OADestroy @fso;
END;
GO

/* Escribe #archivo_lineas (NUM, LINEA) en @ruta con la codificación y el fin de línea indicados */
CREATE OR ALTER PROCEDURE ops.sp_escribir_archivo
    @ruta     NVARCHAR(400),
    @charset  VARCHAR(30) = 'windows-1252',
    @eol      VARCHAR(4)  = 'CRLF'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @st INT, @hr INT, @buf NVARCHAR(4000) = N'', @linea NVARCHAR(4000), @fin NVARCHAR(2) = CASE WHEN @eol = 'LF' THEN NCHAR(10) ELSE NCHAR(13) + NCHAR(10) END;
    EXEC @hr = sp_OACreate 'ADODB.Stream', @st OUT;
    IF @hr <> 0 EXEC ops.sp_oa_error NULL, @hr, N'crear ADODB.Stream';
    EXEC @hr = sp_OASetProperty @st, 'Type', 2;                 -- texto
    IF @hr = 0 EXEC @hr = sp_OASetProperty @st, 'Charset', @charset;
    IF @hr = 0 EXEC @hr = sp_OAMethod @st, 'Open';
    IF @hr <> 0 EXEC ops.sp_oa_error @st, @hr, N'abrir el archivo';

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT LINEA FROM #archivo_lineas ORDER BY NUM;
    OPEN c; FETCH NEXT FROM c INTO @linea;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF LEN(@buf) + LEN(@linea) + 2 > 3800                    -- sp_OAMethod recibe hasta 4000 caracteres
        BEGIN
            EXEC @hr = sp_OAMethod @st, 'WriteText', NULL, @buf;
            IF @hr <> 0 BREAK;
            SET @buf = N'';
        END;
        SET @buf += @linea + @fin;
        FETCH NEXT FROM c INTO @linea;
    END;
    CLOSE c; DEALLOCATE c;
    IF @hr = 0 AND LEN(@buf + N'x') > 1 EXEC @hr = sp_OAMethod @st, 'WriteText', NULL, @buf;
    IF @hr = 0 EXEC @hr = sp_OAMethod @st, 'SaveToFile', NULL, @ruta, 2;   -- 2 = reemplaza si existe
    IF @hr <> 0 EXEC ops.sp_oa_error @st, @hr, N'escribir el archivo';
    EXEC sp_OAMethod @st, 'Close';
    EXEC sp_OADestroy @st;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_exportar_salidas
    @id_corrida   INT           = NULL,     -- NULL = la última corrida OK del cliente
    @cliente      VARCHAR(10)   = '486',
    @carpeta      NVARCHAR(400) = NULL,     -- NULL = parámetro RUTA_SALIDA
    @solo         NVARCHAR(400) = NULL,     -- archivos separados por coma (ej. SCBPAG,SCBTEL)
    @sin_scripts  BIT           = 0,
    @zip          NVARCHAR(100) = NULL,     -- archivos que van en el ZIP con contraseña (ej. RETIROS)
    @carpeta_zip  NVARCHAR(400) = NULL,     -- NULL = parámetro CARPETA_ZIP (C:\)
    @enviar_zip   BIT           = 0,        -- 1 = correo de devolución: Operación con el ZIP, AEM en copia oculta sin él
    @solo_mostrar BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @fecha DATE, @estatus VARCHAR(15), @ahora DATETIME2(0) = SYSDATETIME(), @msg NVARCHAR(4000), @destino NVARCHAR(400);

    IF @id_corrida IS NULL
        SELECT TOP (1) @id_corrida = ID_CORRIDA FROM ops.CORRIDA WHERE CLIENTE = @cliente AND ESTATUS = 'OK' ORDER BY ID_CORRIDA DESC;
    SELECT @cliente = CLIENTE, @fecha = FECHA_PROCESO, @estatus = ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @fecha IS NULL THROW 50851, 'La corrida no existe (o no hay corridas OK).', 1;
    IF @estatus <> 'OK' PRINT CONCAT('Aviso: la corrida ', @id_corrida, ' está en estatus ', @estatus, '.');

    SET @carpeta = ISNULL(NULLIF(@carpeta, N''), ISNULL(cfg.fn_param(@cliente, 'RUTA_SALIDA'), N'C:\BANBAJ\486\SALIDA\'));
    IF RIGHT(@carpeta, 1) <> N'\' SET @carpeta += N'\';
    SET @destino = CONCAT(@carpeta, CONVERT(CHAR(8), @fecha, 112), N'_corrida', @id_corrida, N'\');
    SET @carpeta_zip = ISNULL(NULLIF(@carpeta_zip, N''), ISNULL(cfg.fn_param(@cliente, 'CARPETA_ZIP'), N'C:\'));
    IF RIGHT(@carpeta_zip, 1) <> N'\' SET @carpeta_zip += N'\';

    DECLARE @solo_t TABLE (A VARCHAR(50) PRIMARY KEY);
    INSERT INTO @solo_t SELECT DISTINCT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(ISNULL(@solo, N''), N',') WHERE LTRIM(value) <> N'';

    /* Plan: un renglón por archivo */
    CREATE TABLE #plan (ORDEN INT IDENTITY(1,1), TIPO VARCHAR(10), ARCHIVO VARCHAR(50), NOMBRE NVARCHAR(260), RUTA NVARCHAR(400),
                        CHARSET VARCHAR(30), EOL VARCHAR(4), ENCABEZADO BIT, SEP VARCHAR(5), LINEAS INT);
    INSERT INTO #plan (TIPO, ARCHIVO, NOMBRE, CHARSET, EOL, ENCABEZADO, SEP, LINEAS)
    SELECT 'ARCHIVO', l.ARCHIVO,
           REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(MAX(s.NOMBRE), l.ARCHIVO + N'.TXT'),
               N'{AAAAMMDD}', CONVERT(CHAR(8), @fecha, 112)),
               N'{MMDDAAAA}', REPLACE(CONVERT(CHAR(10), @fecha, 101), '/', '')),
               N'{HHMMSS}', REPLACE(CONVERT(CHAR(8), @ahora, 108), ':', '')),
               N'{CORRIDA}', CAST(@id_corrida AS NVARCHAR(10))),
           CASE WHEN LOWER(ISNULL(MAX(s.CODIFICACION), 'cp1252')) IN ('utf-8', 'utf8') THEN 'utf-8' ELSE 'windows-1252' END,
           ISNULL(MAX(s.FIN_DE_LINEA), 'CRLF'), ISNULL(MAX(CAST(s.ENCABEZADO AS INT)), 0), ISNULL(MAX(s.SEPARADOR), ','), COUNT(*)
    FROM ops.SALIDA_LINEA l
    LEFT JOIN cfg.SALIDA_ARCHIVO s ON s.CLIENTE = @cliente AND s.ARCHIVO = l.ARCHIVO
    WHERE l.ID_CORRIDA = @id_corrida
      AND (NOT EXISTS (SELECT 1 FROM @solo_t) OR UPPER(l.ARCHIVO) IN (SELECT A FROM @solo_t))
    GROUP BY l.ARCHIVO
    ORDER BY l.ARCHIVO;
    UPDATE #plan SET LINEAS = LINEAS + 1 WHERE ENCABEZADO = 1;

    /* Dos salidas con el mismo nombre en una corrida (ej. DAT_MIS_RET y DAT_MIS_ASIG = DAT486_<fecha>.csv):
       se escribe la que se generó al final (la de la bitácora más reciente), que tiene el DAT final */
    ;WITH g AS (
        SELECT p.ORDEN, ROW_NUMBER() OVER (PARTITION BY p.NOMBRE ORDER BY
                 (SELECT MAX(b.ID) FROM ops.BITACORA b WHERE b.ID_CORRIDA = @id_corrida AND b.PASO = 'SALIDA'
                    AND (b.MENSAJE LIKE p.ARCHIVO + N' %' OR b.MENSAJE LIKE p.ARCHIVO + N':%')) DESC, p.ORDEN DESC) AS RN,
               p.ARCHIVO, p.NOMBRE
        FROM #plan p)
    SELECT ARCHIVO, NOMBRE INTO #omitidos FROM g WHERE RN > 1;
    DELETE p FROM #plan p WHERE p.ARCHIVO IN (SELECT ARCHIVO FROM #omitidos);
    IF EXISTS (SELECT 1 FROM #omitidos)
    BEGIN
        SET @msg = (SELECT STRING_AGG(CONCAT(ARCHIVO, N' (', NOMBRE, N')'), N', ') FROM #omitidos);
        PRINT CONCAT('Se omiten por tener el mismo nombre que una salida posterior: ', @msg);
    END;

    IF @sin_scripts = 0
        INSERT INTO #plan (TIPO, ARCHIVO, NOMBRE, CHARSET, EOL, ENCABEZADO, SEP, LINEAS)
        SELECT 'SCRIPT', SCRIPT, N'cyber\' + SCRIPT + N'.sql', 'windows-1252', 'CRLF', 0, NULL, COUNT(*)
        FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida
        GROUP BY SCRIPT ORDER BY SCRIPT;
    UPDATE #plan SET RUTA = @destino + NOMBRE;

    /* ZIP */
    DECLARE @zip_ruta NVARCHAR(400), @zip_cmd NVARCHAR(4000), @zip_mostrar NVARCHAR(4000), @siete NVARCHAR(400), @archivos_zip NVARCHAR(3000);
    IF NULLIF(@zip, N'') IS NOT NULL
    BEGIN
        SELECT @archivos_zip = STRING_AGG(CAST(N'"' + p.RUTA + N'"' AS NVARCHAR(MAX)), N' ')
        FROM #plan p WHERE p.TIPO = 'ARCHIVO' AND UPPER(p.ARCHIVO) IN (SELECT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(@zip, N','));
        IF @archivos_zip IS NULL
            PRINT CONCAT('ZIP: la corrida no tiene archivos ', @zip, '; no se arma.');
        ELSE
        BEGIN
            SET @zip_ruta = @carpeta_zip
                + CASE WHEN UPPER(LTRIM(RTRIM(@zip))) = 'RETIROS' THEN N'RETIROS_PAG_' + @cliente ELSE REPLACE(UPPER(@zip), N',', N'_') + N'_' + @cliente END
                + N'_' + REPLACE(CONVERT(CHAR(10), @ahora, 101), '/', '') + REPLACE(CONVERT(CHAR(8), @ahora, 108), ':', '') + N'.zip';
            SET @siete = ISNULL(cfg.fn_param(@cliente, 'RUTA_7ZIP'), N'C:\Program Files\7-Zip\7z.exe');
            SET @zip_mostrar = N'""' + @siete + N'" a -tzip -mem=ZipCrypto -p"********" -y "' + @zip_ruta + N'" ' + @archivos_zip + N'"';
        END;
    END;

    IF @solo_mostrar = 1
    BEGIN
        SELECT ORDEN, TIPO, ARCHIVO, RUTA, CHARSET, EOL, ENCABEZADO, LINEAS, CAST(NULL AS NVARCHAR(4000)) AS COMANDO FROM #plan
        UNION ALL
        SELECT 9999, 'ZIP', @zip, @zip_ruta, NULL, NULL, NULL, NULL, @zip_mostrar WHERE @zip_ruta IS NOT NULL
        ORDER BY ORDEN;
        RETURN;
    END;

    /* Escribir */
    EXEC ops.sp_crear_carpeta @destino;
    DECLARE @dir_cyber NVARCHAR(400) = @destino + N'cyber\';
    IF EXISTS (SELECT 1 FROM #plan WHERE TIPO = 'SCRIPT') EXEC ops.sp_crear_carpeta @dir_cyber;
    CREATE TABLE #archivo_lineas (NUM INT NOT NULL, LINEA NVARCHAR(4000) NOT NULL);
    DECLARE @o INT, @tipo VARCHAR(10), @arch VARCHAR(50), @ruta NVARCHAR(400), @cs VARCHAR(30), @eol VARCHAR(4), @enc BIT, @sep VARCHAR(5), @n INT, @escritos INT = 0;
    DECLARE p CURSOR LOCAL FAST_FORWARD FOR SELECT ORDEN, TIPO, ARCHIVO, RUTA, CHARSET, EOL, ENCABEZADO, SEP, LINEAS FROM #plan ORDER BY ORDEN;
    OPEN p; FETCH NEXT FROM p INTO @o, @tipo, @arch, @ruta, @cs, @eol, @enc, @sep, @n;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #archivo_lineas;
        IF @tipo = 'ARCHIVO'
        BEGIN
            IF @enc = 1
                INSERT INTO #archivo_lineas (NUM, LINEA)
                SELECT -1, STRING_AGG(CAST(CAMPO AS NVARCHAR(MAX)), @sep) WITHIN GROUP (ORDER BY ORDEN)
                FROM cfg.SALIDA WHERE CLIENTE = @cliente AND ARCHIVO = @arch AND ACTIVO = 1;
            INSERT INTO #archivo_lineas (NUM, LINEA) SELECT NUM, LINEA FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = @arch;
        END
        ELSE
            INSERT INTO #archivo_lineas (NUM, LINEA) SELECT NUM, SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = @arch;
        EXEC ops.sp_escribir_archivo @ruta, @cs, @eol;
        SET @escritos += 1;
        PRINT CONCAT(LEFT(@ruta + REPLICATE(' ', 70), 70), ' ', @n, ' líneas');
        FETCH NEXT FROM p INTO @o, @tipo, @arch, @ruta, @cs, @eol, @enc, @sep, @n;
    END;
    CLOSE p; DEALLOCATE p;

    /* ZIP con contraseña (7-Zip por xp_cmdshell) */
    IF @zip_ruta IS NOT NULL
    BEGIN
        DECLARE @u NVARCHAR(128), @clave NVARCHAR(256);
        DECLARE @salida TABLE (L NVARCHAR(4000));
        EXEC cfg.sp_credencial_leer 'ZIP_RETIROS', @u OUTPUT, @clave OUTPUT;
        SET @clave = REPLACE(REPLACE(@clave, N'{MM}', RIGHT('0' + CAST(MONTH(@ahora) AS VARCHAR(2)), 2)), N'{AAAA}', CAST(YEAR(@ahora) AS VARCHAR(4)));
        IF @clave LIKE N'%["%&|<>^]%' THROW 50852, 'La contraseña del ZIP no puede llevar " % & | < > ^ (los interpreta la línea de comandos).', 1;
        SET @zip_cmd = REPLACE(@zip_mostrar, N'-p"********"', N'-p"' + @clave + N'"');
        INSERT INTO @salida EXEC master.sys.xp_cmdshell @zip_cmd;
        IF NOT EXISTS (SELECT 1 FROM @salida WHERE L LIKE N'%Everything is Ok%')
        BEGIN
            SET @msg = CONCAT(N'7-Zip no terminó bien: ', (SELECT STRING_AGG(L, N' | ') FROM @salida WHERE L IS NOT NULL),
                              N'. Revisa RUTA_7ZIP y que xp_cmdshell esté activado.');
            THROW 50853, @msg, 1;
        END;
        PRINT CONCAT('ZIP con contraseña: ', @zip_ruta);
        IF @enviar_zip = 1
            EXEC ops.sp_aviso_devolucion @id_corrida, @zip_ruta;
    END;

    SET @msg = CONCAT(@escritos, N' archivos en ', @destino, CASE WHEN @zip_ruta IS NOT NULL THEN N' · ZIP: ' + @zip_ruta ELSE N'' END);
    EXEC ops.sp_log @id_corrida, 'EXPORTAR ARCHIVOS', 'OK', @escritos, @msg;
    SELECT ORDEN, TIPO, ARCHIVO, RUTA, LINEAS FROM #plan ORDER BY ORDEN;
END;
GO
