/* =====================================================================
   Banbaj · 50 Archivos planos de salida
   ---------------------------------------------------------------------
   ops.sp_generar_salida   arma las líneas de un archivo con los campos de
                           cfg.SALIDA sobre el ORIGEN de cfg.SALIDA_ARCHIVO
                           y las guarda en ops.SALIDA_LINEA
   ops.sp_generar_salidas  genera todos los archivos activos de un grupo
                           (ASIG, ACT, RETIRO)

   Los archivos se escriben en disco con tools/exportar_salidas.py (o bcp),
   en una sola codificación (H-05), y se arriban a mano a CYBER.
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_generar_salida
    @id_corrida INT,
    @archivo    VARCHAR(50) = 'SCBSDOS'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    DECLARE @modo VARCHAR(12) = ISNULL(cfg.fn_param(@cliente, 'NEGATIVO_MODO'), 'ABS_LEGADO');
    DECLARE @hora CHAR(8) = CONVERT(CHAR(8), SYSDATETIME(), 108);
    DECLARE @origen NVARCHAR(2000), @orden NVARCHAR(400), @sep VARCHAR(5),
            @ancho INT, @partes NVARCHAR(MAX), @sql NVARCHAR(MAX), @n INT, @malas INT;

    DECLARE @comillas BIT = 0;
    SELECT @origen = ORIGEN, @orden = ORDEN_LINEAS, @sep = SEPARADOR, @comillas = COMILLAS
    FROM cfg.SALIDA_ARCHIVO WHERE CLIENTE = @cliente AND ARCHIVO = @archivo;
    SET @origen = ISNULL(@origen, N'dat.DAT_486 d WHERE d.CLIENTE = @cliente');
    SET @orden  = ISNULL(@orden, N'd.CUENTA2');

    IF @sep IS NULL
        /* Ancho fijo: cada campo se recorta o rellena a su ANCHO */
        SELECT @ancho = SUM(ANCHO),
               @partes = STRING_AGG(CAST(
                   CASE FORMATO
                       WHEN 'IMPORTE'        THEN N'cfg.fn_pad_importe(' + EXPRESION + N', ' + CAST(ANCHO AS NVARCHAR(5)) + N', @modo)'
                       WHEN 'IMPORTE_SIGNO'  THEN N'cfg.fn_pad_importe(' + EXPRESION + N', ' + CAST(ANCHO AS NVARCHAR(5)) + N', ''SIGNO'')'
                       WHEN 'FECHA_MMDDAAAA' THEN N'LEFT(CONCAT(cfg.fn_fecha_mmddaaaa(' + EXPRESION + N'), SPACE(' + CAST(ANCHO AS NVARCHAR(5)) + N')), ' + CAST(ANCHO AS NVARCHAR(5)) + N')'
                       ELSE CASE ALINEACION
                           WHEN 'D' THEN N'RIGHT(CONCAT(SPACE(' + CAST(ANCHO AS NVARCHAR(5)) + N'), CAST((' + EXPRESION + N') AS NVARCHAR(4000))), ' + CAST(ANCHO AS NVARCHAR(5)) + N')'
                           ELSE N'LEFT(CONCAT(CAST((' + EXPRESION + N') AS NVARCHAR(4000)), SPACE(' + CAST(ANCHO AS NVARCHAR(5)) + N')), ' + CAST(ANCHO AS NVARCHAR(5)) + N')'
                       END
                   END AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY ORDEN)
        FROM cfg.SALIDA
        WHERE CLIENTE = @cliente AND ARCHIVO = @archivo AND ACTIVO = 1;
    ELSE
    BEGIN
        DECLARE @sep_sql NVARCHAR(20) = N', N''' + REPLACE(@sep, '''', '''''') + N''', ';
        /* Delimitado: campos sin espacios sobrantes, sin comillas (como COPY TO … DELIMITED WITH "") */
        SELECT @partes = STRING_AGG(CAST(
                   CASE WHEN @comillas = 1 THEN N'CONCAT(N''"'', REPLACE(ISNULL(' ELSE N'' END +
                   CASE FORMATO
                       WHEN 'IMPORTE'        THEN N'CONVERT(NVARCHAR(30), CAST(' + EXPRESION + N' AS DECIMAL(18,2)))'
                       WHEN 'IMPORTE_SIGNO'  THEN N'CONVERT(NVARCHAR(30), CAST(' + EXPRESION + N' AS DECIMAL(18,2)))'
                       WHEN 'FECHA_MMDDAAAA' THEN N'cfg.fn_fecha_mmddaaaa(' + EXPRESION + N')'
                       ELSE N'LTRIM(RTRIM(CAST((' + EXPRESION + N') AS NVARCHAR(4000))))'
                   END +
                   CASE WHEN @comillas = 1 THEN N', N''''), N''"'', N''""''), N''"'')' ELSE N'' END AS NVARCHAR(MAX)), @sep_sql) WITHIN GROUP (ORDER BY ORDEN)
        FROM cfg.SALIDA
        WHERE CLIENTE = @cliente AND ARCHIVO = @archivo AND ACTIVO = 1;
    END;

    IF @partes IS NULL
        THROW 50200, 'No hay campos en cfg.SALIDA para ese archivo.', 1;

    SET @partes = REPLACE(@partes, N'{CLIENTE}', @cliente);

    DELETE FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = @archivo;

    /* CONCAT ignora NULL: un campo vacío queda vacío y no recorre columnas */
    SET @sql = N'INSERT INTO ops.SALIDA_LINEA (ID_CORRIDA, ARCHIVO, NUM, LINEA) '
             + N'SELECT @id_corrida, @archivo, ROW_NUMBER() OVER (ORDER BY ' + @orden + N'), CONCAT(N'''', ' + @partes + N') '
             + N'FROM ' + @origen + N'; SET @n = @@ROWCOUNT;';
    EXEC sp_executesql @sql,
         N'@id_corrida INT, @archivo VARCHAR(50), @cliente VARCHAR(10), @fecha DATE, @hora CHAR(8), @modo VARCHAR(12), @n INT OUTPUT',
         @id_corrida = @id_corrida, @archivo = @archivo, @cliente = @cliente, @fecha = @fecha, @hora = @hora, @modo = @modo, @n = @n OUTPUT;

    IF @sep IS NULL
    BEGIN
        /* Todas las líneas deben medir exactamente la suma de los anchos */
        SELECT @malas = COUNT(*) FROM ops.SALIDA_LINEA
        WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = @archivo AND DATALENGTH(LINEA) / 2 <> @ancho;

        IF @malas > 0
        BEGIN
            SET @sql = CONCAT(@archivo, N': líneas con ancho distinto de ', @ancho);
            EXEC ops.sp_log @id_corrida, 'SALIDA', 'ERROR', @malas, @sql;
            THROW 50201, 'Hay líneas con ancho incorrecto; revisa ANCHO y EXPRESION en cfg.SALIDA.', 1;
        END;
        SET @sql = CONCAT(@archivo, N' · ', @ancho, N' caracteres por línea');
    END
    ELSE
        SET @sql = CONCAT(@archivo, N' · delimitado por ''', @sep, N'''');

    EXEC ops.sp_log @id_corrida, 'SALIDA', 'OK', @n, @sql;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_generar_salidas
    @id_corrida INT,
    @proceso    VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida), @archivo VARCHAR(50);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ARCHIVO FROM cfg.SALIDA_ARCHIVO
        WHERE CLIENTE = @cliente AND PROCESO = @proceso AND ACTIVO = 1
        ORDER BY ORDEN, ARCHIVO;
    OPEN cur;
    FETCH NEXT FROM cur INTO @archivo;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC ops.sp_generar_salida @id_corrida, @archivo;
        FETCH NEXT FROM cur INTO @archivo;
    END;
    CLOSE cur; DEALLOCATE cur;
END;
GO
