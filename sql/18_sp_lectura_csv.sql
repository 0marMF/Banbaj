USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 18 Lectura de CSV a tablas de paso
   ---------------------------------------------------------------------
   ops.sp_mig_diagnostico  revisa un CSV sin mostrar datos (renglones,
                           comillas, caracteres raros)
   ops.sp_mig_leer         lee un CSV con encabezado a stg.MIG_<fuente>

   Nacieron para la migración (sql/80) y siguen en uso después de ella:
   las cargas de exclusiones (sql/70) leen el archivo con ops.sp_mig_leer.
   Por eso viven aquí y la limpieza de la migración
   (sql/instalacion/05_limpiar_migracion.sql) no los borra.
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
