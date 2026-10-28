/* =====================================================================
   Banbaj · 50 Salidas de ancho fijo (SCBSDOS y las que se agreguen)
   ---------------------------------------------------------------------
   ops.sp_generar_salida arma una línea por cuenta del DAT con los campos
   de cfg.SALIDA y la guarda en ops.SALIDA_LINEA. El archivo se exporta
   con bcp desde un paso del job (ver sql/LEEME.md), en una sola
   codificación (H-05).
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_generar_salida
    @id_corrida INT,
    @archivo    VARCHAR(50) = 'SCBSDOS'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @modo VARCHAR(12) = ISNULL(cfg.fn_param(@cliente, 'NEGATIVO_MODO'), 'ABS_LEGADO');
    DECLARE @ancho INT, @partes NVARCHAR(MAX), @sql NVARCHAR(MAX), @n INT, @malas INT;

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

    IF @partes IS NULL
        THROW 50200, 'No hay campos en cfg.SALIDA para ese archivo.', 1;

    SET @partes = REPLACE(@partes, N'{CLIENTE}', @cliente);

    DELETE FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = @archivo;

    SET @sql = N'INSERT INTO ops.SALIDA_LINEA (ID_CORRIDA, ARCHIVO, NUM, LINEA) '
             + N'SELECT @id_corrida, @archivo, ROW_NUMBER() OVER (ORDER BY d.CUENTA2), CONCAT(N'''', ' + @partes + N') '
             + N'FROM dat.DAT_486 d WHERE d.CLIENTE = @cliente; SET @n = @@ROWCOUNT;';
    EXEC sp_executesql @sql, N'@id_corrida INT, @archivo VARCHAR(50), @cliente VARCHAR(10), @modo VARCHAR(12), @n INT OUTPUT',
         @id_corrida = @id_corrida, @archivo = @archivo, @cliente = @cliente, @modo = @modo, @n = @n OUTPUT;

    /* Todas las líneas deben medir exactamente la suma de los anchos */
    SELECT @malas = COUNT(*) FROM ops.SALIDA_LINEA
    WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = @archivo AND DATALENGTH(LINEA) / 2 <> @ancho;

    IF @malas > 0
    BEGIN
        EXEC ops.sp_log @id_corrida, 'SALIDA', 'ERROR', @malas, CONCAT(@archivo, N': líneas con ancho distinto de ', @ancho);
        THROW 50201, 'Hay líneas con ancho incorrecto; revisa ANCHO y EXPRESION en cfg.SALIDA.', 1;
    END;

    EXEC ops.sp_log @id_corrida, 'SALIDA', 'OK', @n, CONCAT(@archivo, N' · ', @ancho, N' caracteres por línea');
END;
GO
