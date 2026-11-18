USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 22 Validación de la entrada, layout editable y catálogos (decisión 17/11)
   ---------------------------------------------------------------------
   Antes de tocar el DAT, la actualización y la asignación revisan cada archivo:
   1. Layout: cada campo que toma el proceso (cfg.ARCHIVO_COLUMNA) tiene que estar
      en el archivo. Lo revisa ops.sp_cargar_archivo (sql/20).
   2. Datos: reglas de cfg.VALIDACION_DATO sobre el texto tal como llegó
      (importes, teléfonos, correos, catálogos, cuentas repetidas, volumen).
   Si algo no pasa, ops.sp_cargar_proceso avisa al equipo de asignaciones con todo
   lo encontrado (VALIDACION_ENTRADA_486) y detiene la corrida (50025, CANCELADA).
   El equipo corrige y vuelve a correr el proceso a mano.

   ops.sp_validar_datos_archivo     reglas de datos de un archivo (lo llama sql/20)
   ops.sp_validacion_entrada_avisar correo al equipo y mensaje del error
   cfg.sp_layout_cambiar            cambia el encabezado de un campo (y lo prueba contra el último archivo)
   cfg.sp_catalogo_alta             agrega o cambia un valor de un catálogo de etiquetado
   cfg.v_LAYOUT                     layout vigente y si cada campo está en el último archivo
   cfg.v_CATALOGO                   catálogos con sus valores

   Errores: 50041-50049. Diagrama: docs/flujo/09_validacion_entrada.md
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   Reglas de datos de un archivo. Usa #map (CAMPO, POS) del llamador
   (ops.sp_cargar_archivo) y la tabla cruda stg.RAW_<codigo>.
   Deja en ops.VALIDACION_ENTRADA cada regla con anomalías (DETIENE = 1 si
   supera la tolerancia) y un renglón en la bitácora por archivo.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_validar_datos_archivo
    @id_corrida INT,
    @id_archivo INT,
    @raw_q      NVARCHAR(300),
    @fila       INT
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('tempdb..#map') IS NULL RETURN;

    DECLARE @cliente VARCHAR(10), @codigo VARCHAR(50);
    SELECT @cliente = CLIENTE, @codigo = CODIGO FROM cfg.ARCHIVO WHERE ID_ARCHIVO = @id_archivo;

    /* Renglones con datos: después del encabezado y con al menos un campo del catálogo */
    DECLARE @datos NVARCHAR(MAX) =
        (SELECT N'r.ID > @fila AND COALESCE(' + STRING_AGG(CAST(N'cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(POS AS NVARCHAR(4)), 3) + N')' AS NVARCHAR(MAX)), N', ') + N', NULL) IS NOT NULL'
         FROM #map WHERE POS IS NOT NULL);
    IF @datos IS NULL RETURN;

    DECLARE @id INT, @campo SYSNAME, @tipo VARCHAR(15), @valor NVARCHAR(100), @pct_max DECIMAL(5,2), @pos INT,
            @col NVARCHAR(100), @eval NVARCHAR(1000), @anom NVARCHAR(1000), @esperado NVARCHAR(400),
            @sql NVARCHAR(MAX), @rev INT, @ano INT, @pct DECIMAL(7,2), @ej NVARCHAR(1000), @detiene BIT,
            @min INT, @max INT, @ant INT, @reglas INT = 0;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT v.ID, v.CAMPO, v.TIPO, v.VALOR, v.PCT_MAX, m.POS
        FROM cfg.VALIDACION_DATO v
        LEFT JOIN #map m ON m.CAMPO = v.CAMPO
        WHERE v.CLIENTE = @cliente AND v.CODIGO = @codigo AND v.ACTIVO = 1
          AND (m.POS IS NOT NULL OR v.TIPO = 'VOLUMEN')
        ORDER BY v.CAMPO, v.TIPO;
    OPEN cur;
    FETCH NEXT FROM cur INTO @id, @campo, @tipo, @valor, @pct_max, @pos;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @rev = 0, @ano = 0, @ej = NULL, @esperado = NULL, @pct = NULL, @reglas += 1;
        SET @col = N'cfg.fn_texto(r.c' + RIGHT(N'000' + CAST(ISNULL(@pos, 1) AS NVARCHAR(4)), 3) + N')';

        IF @tipo = 'VOLUMEN'
        BEGIN
            /* Renglones contra la última carga buena del mismo archivo (corrida OK) */
            SET @sql = N'SELECT @rev = COUNT(*) FROM ' + @raw_q + N' r WHERE ' + @datos + N';';
            EXEC sp_executesql @sql, N'@fila INT, @rev INT OUTPUT', @fila = @fila, @rev = @rev OUTPUT;
            SET @ant = (SELECT TOP (1) ac.LEIDOS FROM ops.ARCHIVO_CARGADO ac
                        JOIN ops.CORRIDA c ON c.ID_CORRIDA = ac.ID_CORRIDA
                        WHERE ac.CODIGO = @codigo AND ac.ESTATUS = 'CARGADO' AND c.ESTATUS = 'OK' AND ac.ID_CORRIDA <> @id_corrida
                          AND ac.LEIDOS > 0
                        ORDER BY ac.ID_CORRIDA DESC);
            SET @min = ISNULL(TRY_CONVERT(INT, LEFT(@valor, CHARINDEX(N'-', @valor + N'-') - 1)), 0);
            SET @max = ISNULL(TRY_CONVERT(INT, NULLIF(SUBSTRING(@valor, CHARINDEX(N'-', @valor + N'-') + 1, 20), N'')), 100000);
            IF @ant IS NOT NULL
            BEGIN
                SET @pct = CAST(@rev * 100.0 / @ant AS DECIMAL(7,2));
                IF @pct < @min OR @pct > @max
                    INSERT INTO ops.VALIDACION_ENTRADA (ID_CORRIDA, CODIGO, TIPO, CAMPO, ESPERADO, REVISADOS, ANOMALOS, PCT, PCT_MAX, EJEMPLOS, DETIENE)
                    VALUES (@id_corrida, @codigo, @tipo, N'*', CONCAT(N'Entre ', @min, N' % y ', @max, N' % de la última carga buena'),
                            @rev, NULL, @pct, NULL, CONCAT(N'Trae ', @rev, N' renglones; la última carga buena trajo ', @ant), 1);
            END;
            GOTO siguiente;
        END;

        IF @tipo = 'LLAVE_UNICA'
        BEGIN
            SET @esperado = N'Sin cuentas repetidas';
            SET @sql = N'SELECT @rev = COUNT(*), @ano = ISNULL(SUM(CASE WHEN N > 1 THEN 1 ELSE 0 END), 0) FROM (SELECT x.V, COUNT(*) OVER (PARTITION BY x.V) AS N FROM '
                     + @raw_q + N' r CROSS APPLY (SELECT ' + @col + N' AS V) x WHERE ' + @datos + N' AND x.V IS NOT NULL) t;'
                     + N'SELECT @ej = STRING_AGG(CONCAT(N''renglón '', ID, N'': '', cfg.fn_enmascarar(V)), N''; '') WITHIN GROUP (ORDER BY ID) FROM (SELECT TOP (5) ID, V FROM '
                     + N'(SELECT r.ID, x.V, COUNT(*) OVER (PARTITION BY x.V) AS N FROM ' + @raw_q + N' r CROSS APPLY (SELECT ' + @col + N' AS V) x WHERE '
                     + @datos + N' AND x.V IS NOT NULL) t WHERE N > 1 ORDER BY ID) e;';
            EXEC sp_executesql @sql, N'@fila INT, @rev INT OUTPUT, @ano INT OUTPUT, @ej NVARCHAR(1000) OUTPUT',
                 @fila = @fila, @rev = @rev OUTPUT, @ano = @ano OUTPUT, @ej = @ej OUTPUT;
        END
        ELSE
        BEGIN
            /* @eval: qué valores se revisan · @anom: cuándo un valor revisado es anómalo */
            SET @eval = CASE WHEN @tipo = 'NO_VACIO' THEN N'1 = 1'
                             WHEN @tipo IN ('TELEFONO', 'CORREO') THEN N'x.V IS NOT NULL AND x.V NOT IN (N''0'', N''-'')'
                             ELSE N'x.V IS NOT NULL AND x.V <> N''-''' END;
            IF @tipo = 'TELEFONO'
            BEGIN
                SET @min = ISNULL(TRY_CONVERT(INT, LEFT(ISNULL(@valor, N'10-12'), CHARINDEX(N'-', ISNULL(@valor, N'10-12') + N'-') - 1)), 10);
                SET @max = ISNULL(TRY_CONVERT(INT, NULLIF(SUBSTRING(ISNULL(@valor, N'10-12'), CHARINDEX(N'-', ISNULL(@valor, N'10-12') + N'-') + 1, 20), N'')), @min);
            END;
            SET @anom = CASE @tipo
                WHEN 'IMPORTE'     THEN N'cfg.fn_importe(x.V) IS NULL'
                WHEN 'NO_NEGATIVO' THEN N'cfg.fn_importe(x.V) < 0'
                WHEN 'MAXIMO'      THEN N'cfg.fn_importe(x.V) > ' + CAST(ISNULL(TRY_CONVERT(DECIMAL(18,2), @valor), 999999999999) AS NVARCHAR(30))
                WHEN 'ENTERO'      THEN N'cfg.fn_entero(x.V) IS NULL'
                WHEN 'TELEFONO'    THEN N'(x.V LIKE N''%[A-Za-z]%'' OR LEN(ISNULL(cfg.fn_solo_digitos(x.V), '''')) NOT BETWEEN '
                                        + CAST(@min AS NVARCHAR(5)) + N' AND ' + CAST(@max AS NVARCHAR(5)) + N')'
                WHEN 'CORREO'      THEN N'(x.V NOT LIKE N''%_@_%._%'' OR x.V LIKE N''%@%@%'' OR x.V LIKE N''% %'' OR x.V LIKE N''%[,;]%'')'
                WHEN 'CATALOGO'    THEN N'cfg.fn_catalogo(@cliente, @valor, x.V) IS NULL'
                WHEN 'NO_VACIO'    THEN N'(x.V IS NULL OR x.V = N''-'')'
            END;
            SET @esperado = CASE @tipo
                WHEN 'IMPORTE'     THEN N'Importe'
                WHEN 'NO_NEGATIVO' THEN N'Importe sin negativos'
                WHEN 'MAXIMO'      THEN N'Importe hasta ' + FORMAT(ISNULL(TRY_CONVERT(DECIMAL(18,2), @valor), 0), N'N0')
                WHEN 'ENTERO'      THEN N'Número entero'
                WHEN 'TELEFONO'    THEN CONCAT(N'Solo dígitos, de ', @min, CASE WHEN @max <> @min THEN CONCAT(N' a ', @max) END, N' (0 y - = vacío)')
                WHEN 'CORREO'      THEN N'nombre@dominio.algo (0 y - = vacío)'
                WHEN 'CATALOGO'    THEN N'Valor del catálogo ' + ISNULL(@valor, N'')
                WHEN 'NO_VACIO'    THEN N'Con dato'
            END;
            IF @anom IS NULL GOTO siguiente;
            SET @sql = N'SELECT @rev = COUNT(*), @ano = ISNULL(SUM(CASE WHEN ' + @anom + N' THEN 1 ELSE 0 END), 0) FROM ' + @raw_q
                     + N' r CROSS APPLY (SELECT ' + @col + N' AS V) x WHERE ' + @datos + N' AND (' + @eval + N');';
            /* Ejemplos: en catálogos el valor tal cual (es una etiqueta, no un dato personal); en lo demás, enmascarado */
            IF @tipo = 'CATALOGO'
                SET @sql += N'SELECT @ej = STRING_AGG(CONCAT(N''"'', V, N''" ('', N, N'')''), N'', '') FROM (SELECT TOP (10) x.V, COUNT(*) AS N FROM ' + @raw_q
                          + N' r CROSS APPLY (SELECT ' + @col + N' AS V) x WHERE ' + @datos + N' AND (' + @eval + N') AND ' + @anom
                          + N' GROUP BY x.V ORDER BY COUNT(*) DESC) e;';
            ELSE
                SET @sql += N'SELECT @ej = STRING_AGG(CONCAT(N''renglón '', ID, N'': '', ISNULL(cfg.fn_enmascarar(V), N''(vacío)'')), N''; '') WITHIN GROUP (ORDER BY ID) FROM (SELECT TOP (5) r.ID, x.V FROM ' + @raw_q
                          + N' r CROSS APPLY (SELECT ' + @col + N' AS V) x WHERE ' + @datos + N' AND (' + @eval + N') AND ' + @anom
                          + N' ORDER BY r.ID) e;';
            EXEC sp_executesql @sql, N'@fila INT, @cliente VARCHAR(10), @valor NVARCHAR(100), @rev INT OUTPUT, @ano INT OUTPUT, @ej NVARCHAR(1000) OUTPUT',
                 @fila = @fila, @cliente = @cliente, @valor = @valor, @rev = @rev OUTPUT, @ano = @ano OUTPUT, @ej = @ej OUTPUT;
        END;

        IF @ano > 0
        BEGIN
            SET @pct = CAST(@ano * 100.0 / NULLIF(@rev, 0) AS DECIMAL(7,2));
            SET @detiene = CASE WHEN ISNULL(@pct, 100) > @pct_max THEN 1 ELSE 0 END;
            INSERT INTO ops.VALIDACION_ENTRADA (ID_CORRIDA, CODIGO, TIPO, CAMPO, ESPERADO, REVISADOS, ANOMALOS, PCT, PCT_MAX, EJEMPLOS, DETIENE)
            VALUES (@id_corrida, @codigo, @tipo, @campo, @esperado, @rev, @ano, @pct, @pct_max, LEFT(@ej, 1000), @detiene);
        END;

        siguiente:
        FETCH NEXT FROM cur INTO @id, @campo, @tipo, @valor, @pct_max, @pos;
    END;
    CLOSE cur; DEALLOCATE cur;

    /* Un renglón en la bitácora por archivo */
    DECLARE @paso VARCHAR(80) = 'VALIDACION DATOS ' + @codigo, @msg NVARCHAR(4000), @est VARCHAR(15);
    SELECT @msg = STRING_AGG(CAST(CONCAT(CAMPO, N' ', TIPO, N': ', ISNULL(CAST(ANOMALOS AS NVARCHAR(12)), N''),
                                         CASE WHEN ANOMALOS IS NOT NULL THEN CONCAT(N' de ', REVISADOS) END,
                                         N' (', PCT, N' %', CASE WHEN PCT_MAX IS NOT NULL THEN CONCAT(N', tolera ', PCT_MAX, N' %') END, N')',
                                         CASE WHEN DETIENE = 1 THEN N' DETIENE' END) AS NVARCHAR(MAX)), N'; '),
           @est = CASE WHEN MAX(CAST(DETIENE AS INT)) = 1 THEN 'ERROR' ELSE 'AVISO' END
    FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = @id_corrida AND CODIGO = @codigo AND TIPO <> 'LAYOUT';
    SET @msg = CONCAT(@reglas, N' reglas revisadas', CASE WHEN @msg IS NOT NULL THEN N' · ' + @msg ELSE N', sin anomalías' END);
    SET @est = ISNULL(@est, 'OK');
    EXEC ops.sp_log @id_corrida, @paso, @est, @reglas, @msg;
END;
GO

/* ---------------------------------------------------------------------
   Correo al equipo de asignaciones con todo lo que no pasó la validación
   de la entrada y qué hacer (VALIDACION_ENTRADA_486). Devuelve el mensaje
   con el que ops.sp_cargar_proceso detiene la corrida.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_validacion_entrada_avisar
    @id_corrida  INT,
    @mensaje     NVARCHAR(2048) = NULL OUTPUT,
    @solo_prueba BIT            = 0          -- 1 = devuelve el correo armado sin enviarlo ni anotar la bitácora
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @proceso = PROCESO, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;

    DECLARE @nombre NVARCHAR(30) = CASE @proceso WHEN 'ASIG' THEN N'Asignación' WHEN 'ACT' THEN N'Actualización' ELSE @proceso END,
            @comando NVARCHAR(200) = CONCAT(N'EXEC ops.', CASE @proceso WHEN 'ASIG' THEN N'sp_asignacion_486' ELSE N'sp_actualizacion_486' END,
                                            N' @fecha = ''', CONVERT(CHAR(10), @fecha, 23), N''';'),
            @hay_layout BIT = 0, @hay_catalogo BIT = 0, @hay_datos BIT = 0,
            @t NVARCHAR(MAX), @html_layout NVARCHAR(MAX) = N'', @html_nuevos NVARCHAR(MAX) = N'', @html_datos NVARCHAR(MAX) = N'',
            @pasos NVARCHAR(MAX) = N'', @resumen NVARCHAR(MAX), @json NVARCHAR(MAX), @n INT;

    SELECT @hay_layout   = MAX(CASE WHEN TIPO = 'LAYOUT' AND DETIENE = 1 THEN 1 ELSE 0 END),
           @hay_catalogo = MAX(CASE WHEN TIPO = 'CATALOGO' AND DETIENE = 1 THEN 1 ELSE 0 END),
           @hay_datos    = MAX(CASE WHEN TIPO NOT IN ('LAYOUT', 'CATALOGO') AND DETIENE = 1 THEN 1 ELSE 0 END),
           @n            = SUM(CASE WHEN DETIENE = 1 THEN 1 ELSE 0 END)
    FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = @id_corrida;

    /* Resumen de una línea por archivo (asunto del error y bitácora) */
    SELECT @resumen = STRING_AGG(CAST(CONCAT(CODIGO, N': ', P) AS NVARCHAR(MAX)), N' · ')
    FROM (SELECT CODIGO,
                 STRING_AGG(CAST(CASE WHEN TIPO = 'LAYOUT' THEN N'falta ' + CAMPO
                                      WHEN TIPO = 'VOLUMEN' THEN CONCAT(N'volumen ', PCT, N' % de la última carga')
                                      ELSE CONCAT(CAMPO, N' ', TIPO, N' ', PCT, N' %') END AS NVARCHAR(MAX)), N', ') AS P
          FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = @id_corrida AND DETIENE = 1 GROUP BY CODIGO) x;

    /* Encabezados que no se encontraron */
    IF @hay_layout = 1
    BEGIN
        SET @t = (SELECT CODIGO AS [Archivo], CAMPO AS [Campo], ESPERADO AS [Encabezado que se busca]
                  FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = @id_corrida AND TIPO = 'LAYOUT' AND DETIENE = 1
                  ORDER BY CODIGO, CAMPO FOR JSON PATH, INCLUDE_NULL_VALUES);
        SET @html_layout = N'<p><b>Encabezados que no se encontraron en el archivo</b> (% = cualquier texto, como la fecha)</p>' + mail.fn_tabla_html(@t);
        /* Encabezados del archivo que la matriz no usa y que no venían en la última carga buena: ahí suele estar el que cambió de nombre */
        SET @t = (SELECT TOP (40) f.CODIGO AS [Archivo], CAST(h.[key] AS INT) + 1 AS [Columna], h.[value] AS [Encabezado]
                  FROM (SELECT DISTINCT CODIGO FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = @id_corrida AND TIPO = 'LAYOUT' AND DETIENE = 1) f
                  JOIN ops.ARCHIVO_CARGADO ac ON ac.ID_CORRIDA = @id_corrida AND ac.CODIGO = f.CODIGO
                  CROSS APPLY OPENJSON(ac.ENCABEZADOS) h
                  OUTER APPLY (SELECT TOP (1) p.ENCABEZADOS FROM ops.ARCHIVO_CARGADO p JOIN ops.CORRIDA c ON c.ID_CORRIDA = p.ID_CORRIDA
                               WHERE p.CODIGO = f.CODIGO AND p.ESTATUS = 'CARGADO' AND c.ESTATUS = 'OK' AND p.ENCABEZADOS IS NOT NULL
                               ORDER BY p.ID_CORRIDA DESC) ant
                  WHERE NULLIF(h.[value], N'') IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO
                                    WHERE a.CLIENTE = @cliente AND a.CODIGO = f.CODIGO AND c.ACTIVO = 1 AND c.PATRON_ENCABEZADO IS NOT NULL
                                      AND UPPER(h.[value]) COLLATE Latin1_General_CI_AI LIKE UPPER(c.PATRON_ENCABEZADO) COLLATE Latin1_General_CI_AI)
                    AND (ant.ENCABEZADOS IS NULL
                         OR NOT EXISTS (SELECT 1 FROM OPENJSON(ant.ENCABEZADOS) ph
                                        WHERE cfg.fn_patron_encabezado(ph.[value]) = cfg.fn_patron_encabezado(h.[value])))
                  ORDER BY f.CODIGO, CAST(h.[key] AS INT)
                  FOR JSON PATH, INCLUDE_NULL_VALUES);
        IF @t IS NOT NULL
            SET @html_nuevos = N'<p><b>Encabezados del archivo que la matriz no usa</b> (nuevos respecto a la última carga buena, si la hay)</p>' + mail.fn_tabla_html(@t);
        SET @pasos += N'<li><b>Encabezado que no se encontró:</b> búsquenlo en el archivo. Si el banco le cambió el nombre, actualicen la matriz con '
                   +  N'<code>EXEC cfg.sp_layout_cambiar ''ARCHIVO'', ''CAMPO'', N''encabezado como viene en el archivo'';</code> '
                   +  N'(con la fecha tal cual: se convierte sola en %). Si el banco lo quitó por error, pidan el archivo corregido.</li>';
    END;

    /* Datos que no pasaron (y los avisos que sí se toleraron) */
    SET @t = (SELECT CODIGO AS [Archivo], CAMPO AS [Campo], TIPO AS [Regla], ESPERADO AS [Se espera],
                     CAST(REVISADOS AS NVARCHAR(12)) AS [Revisados], CAST(ANOMALOS AS NVARCHAR(12)) AS [Anómalos],
                     CONCAT(PCT, N' %') AS [%], CASE WHEN PCT_MAX IS NOT NULL THEN CONCAT(PCT_MAX, N' %') ELSE N'' END AS [Tolera],
                     CASE WHEN DETIENE = 1 THEN N'Detiene' ELSE N'Aviso' END AS [Resultado], ISNULL(EJEMPLOS, N'') AS [Ejemplos]
              FROM ops.VALIDACION_ENTRADA
              WHERE ID_CORRIDA = @id_corrida AND NOT (TIPO = 'LAYOUT' AND DETIENE = 1)
              ORDER BY DETIENE DESC, CODIGO, CAMPO, TIPO
              FOR JSON PATH, INCLUDE_NULL_VALUES);
    IF @t IS NOT NULL
        SET @html_datos = N'<p><b>Revisión de los datos</b> (los ejemplos van enmascarados: letra = x, dígito = 9; renglón = línea del archivo)</p>' + mail.fn_tabla_html(@t);
    IF @hay_catalogo = 1
        SET @pasos += N'<li><b>Valor fuera de catálogo</b> (segmento, estatus, cartera…): si es un valor nuevo válido, agréguenlo con '
                   +  N'<code>EXEC cfg.sp_catalogo_alta ''CATALOGO'', N''VALOR'', N''ETIQUETA'';</code> (ver <code>SELECT * FROM cfg.v_CATALOGO;</code>). '
                   +  N'Si no debería venir, pidan el archivo corregido.</li>';
    IF @hay_datos = 1
        SET @pasos += N'<li><b>Datos con anomalías:</b> si el archivo viene mal (columna corrida, texto en saldos o teléfonos, saldos fuera de rango, '
                   +  N'menos renglones de lo normal), pidan al banco uno corregido y déjenlo en la carpeta del día. Si la regla es demasiado estricta, '
                   +  N'ajusten su tolerancia en <code>cfg.VALIDACION_DATO</code> (PCT_MAX o VALOR) o apáguenla (ACTIVO = 0).</li>';
    SET @pasos += N'<li>Cuando esté corregido, vuelvan a correr el proceso: <code>' + @comando + N'</code> El DAT no se tocó.</li>';

    SET @json = (SELECT @nombre AS PROCESO, ISNULL(@resumen, N'') AS RESUMEN, @comando AS COMANDO,
                        @html_layout AS HTML_LAYOUT, @html_nuevos AS HTML_NUEVOS, @html_datos AS HTML_DATOS, @pasos AS HTML_PASOS
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC mail.sp_enviar @plantilla = 'VALIDACION_ENTRADA_486', @id_corrida = @id_corrida, @valores = @json, @solo_prueba = @solo_prueba;

    SET @mensaje = LEFT(CONCAT(N'Validación de la entrada: ', @resumen, N'. Se avisó al equipo de asignaciones (VALIDACION_ENTRADA_486). ',
                               N'Corrige la matriz, el catálogo, la tolerancia o el archivo y vuelve a correr: ', @comando), 2048);
    IF @solo_prueba = 0
        EXEC ops.sp_log @id_corrida, 'VALIDACION ENTRADA', 'ERROR', @n, @mensaje;
END;
GO

/* ---------------------------------------------------------------------
   Cambio de layout por el equipo: encabezado (como viene en el archivo, con
   su fecha) o patrón LIKE, y si el campo se usa. Lo prueba contra los
   encabezados del último archivo recibido. Queda en cfg.LAYOUT_HISTORIAL
   y la semilla lo respeta.
     EXEC cfg.sp_layout_cambiar 'MAESTRA_TDC', 'SALDO2', N'MONTO A CUBRIR PLAZOS PAGO LIQUIDACION';
     EXEC cfg.sp_layout_cambiar 'MAESTRA_CONSUMO', 'PVS', N'DIAS MORA AL 13/11/2026';   -- la fecha se vuelve %
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE cfg.sp_layout_cambiar
    @codigo     VARCHAR(50),
    @campo      SYSNAME,
    @encabezado NVARCHAR(200) = NULL,       -- tal como viene en el archivo
    @patron     NVARCHAR(200) = NULL,       -- o el patrón LIKE ya armado
    @activo     BIT           = NULL,
    @cliente    VARCHAR(10)   = '486'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_archivo INT, @id INT, @antes NVARCHAR(200), @nuevo NVARCHAR(200), @enc NVARCHAR(MAX), @fe DATETIME2(0);
    SELECT @id_archivo = ID_ARCHIVO FROM cfg.ARCHIVO WHERE CLIENTE = @cliente AND CODIGO = @codigo;
    IF @id_archivo IS NULL
        THROW 50041, 'No existe ese archivo en cfg.ARCHIVO (ver SELECT DISTINCT ARCHIVO FROM cfg.v_LAYOUT).', 1;
    SELECT @id = ID, @antes = PATRON_ENCABEZADO FROM cfg.ARCHIVO_COLUMNA WHERE ID_ARCHIVO = @id_archivo AND CAMPO_DESTINO = @campo;
    IF @id IS NULL
        THROW 50042, 'Ese archivo no tiene ese campo (ver SELECT * FROM cfg.v_LAYOUT WHERE ARCHIVO = ...).', 1;
    IF @encabezado IS NULL AND @patron IS NULL AND @activo IS NULL
        THROW 50043, 'Indica @encabezado (como viene en el archivo), @patron o @activo.', 1;

    SET @nuevo = COALESCE(@patron, cfg.fn_patron_encabezado(@encabezado), @antes);
    UPDATE cfg.ARCHIVO_COLUMNA SET PATRON_ENCABEZADO = @nuevo, ACTIVO = ISNULL(@activo, ACTIVO) WHERE ID = @id;

    SELECT TOP (1) @enc = ENCABEZADOS, @fe = FECHA FROM ops.ARCHIVO_CARGADO
    WHERE CODIGO = @codigo AND ENCABEZADOS IS NOT NULL ORDER BY FECHA DESC, ID_CORRIDA DESC;
    SELECT @codigo AS ARCHIVO, @campo AS CAMPO, @antes AS PATRON_ANTES, @nuevo AS PATRON_NUEVO,
           (SELECT ACTIVO FROM cfg.ARCHIVO_COLUMNA WHERE ID = @id) AS ACTIVO,
           @fe AS ULTIMO_ARCHIVO,
           CASE WHEN @enc IS NULL THEN N'Todavía no hay archivo cargado para probarlo'
                ELSE ISNULL((SELECT STRING_AGG(CONCAT(N'columna ', CAST(h.[key] AS INT) + 1, N': ', h.[value]), N' | ')
                             FROM OPENJSON(@enc) h
                             WHERE UPPER(h.[value]) COLLATE Latin1_General_CI_AI LIKE UPPER(@nuevo) COLLATE Latin1_General_CI_AI),
                            N'NO coincide con ningún encabezado del último archivo') END AS EN_EL_ULTIMO_ARCHIVO;
END;
GO

/* ---------------------------------------------------------------------
   Alta o cambio de un valor de catálogo por el equipo.
     EXEC cfg.sp_catalogo_alta 'ESTATUS_CONSUMO', N'PAGO SOSTENIDO', N'REE';
     EXEC cfg.sp_catalogo_alta 'ESTATUS_CONSUMO', N'VIGENTE', N'VIG', @activo = 0;   -- lo quita
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE cfg.sp_catalogo_alta
    @catalogo   VARCHAR(40),
    @origen     NVARCHAR(200),
    @destino    NVARCHAR(200) = N'',
    @orden      INT           = NULL,
    @activo     BIT           = 1,
    @comentario NVARCHAR(400) = NULL,
    @cliente    VARCHAR(10)   = '486'
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM cfg.CATALOGO_DEF WHERE CLIENTE = @cliente AND CATALOGO = @catalogo)
        THROW 50044, 'No existe ese catálogo (ver SELECT DISTINCT CATALOGO, DESCRIPCION FROM cfg.v_CATALOGO).', 1;
    SET @origen = cfg.fn_texto(@origen);
    IF @origen IS NULL
        THROW 50045, 'Indica el valor como viene del banco (@origen).', 1;

    IF EXISTS (SELECT 1 FROM cfg.CATALOGO WHERE CLIENTE = @cliente AND CATALOGO = @catalogo AND VALOR_ORIGEN = @origen)
        UPDATE cfg.CATALOGO
        SET VALOR_DESTINO = ISNULL(@destino, N''), ORDEN = ISNULL(@orden, ORDEN), ACTIVO = ISNULL(@activo, 1),
            COMENTARIO = ISNULL(@comentario, COMENTARIO)
        WHERE CLIENTE = @cliente AND CATALOGO = @catalogo AND VALOR_ORIGEN = @origen;
    ELSE
        INSERT INTO cfg.CATALOGO (CLIENTE, CATALOGO, VALOR_ORIGEN, VALOR_DESTINO, ORDEN, ACTIVO, COMENTARIO, ALTA_POR)
        VALUES (@cliente, @catalogo, @origen, ISNULL(@destino, N''), ISNULL(@orden, 100), ISNULL(@activo, 1), @comentario, 'EQUIPO');

    SELECT CATALOGO, VALOR_ORIGEN, VALOR_DESTINO, ORDEN, ACTIVO, ALTA_POR, USUARIO, FE_MOD
    FROM cfg.CATALOGO WHERE CLIENTE = @cliente AND CATALOGO = @catalogo ORDER BY ACTIVO DESC, ORDEN, VALOR_ORIGEN;
END;
GO

/* Layout vigente: qué encabezado busca cada campo y en qué columna lo encontró en el último archivo */
CREATE OR ALTER VIEW cfg.v_LAYOUT
AS
SELECT a.CLIENTE, a.PROCESO, a.CODIGO AS ARCHIVO, a.PATRON_NOMBRE, c.CAMPO_DESTINO AS CAMPO, c.PATRON_ENCABEZADO,
       c.OBLIGATORIO, c.PERMITE_VACIO, c.ACTIVO, c.EDITADO_POR, c.FE_EDICION,
       u.FECHA AS ULTIMO_ARCHIVO, p.COLUMNA AS COLUMNA_EN_ULTIMO_ARCHIVO,
       CASE WHEN c.PATRON_ENCABEZADO IS NULL AND c.POSICION IS NULL THEN 'DERIVADO'
            WHEN c.ACTIVO = 0 THEN 'INACTIVO'
            WHEN u.ENCABEZADOS IS NULL THEN 'SIN ARCHIVO'
            WHEN p.COLUMNA IS NULL THEN 'NO ENCONTRADO'
            ELSE 'OK' END AS ESTADO
FROM cfg.ARCHIVO a
JOIN cfg.ARCHIVO_COLUMNA c ON c.ID_ARCHIVO = a.ID_ARCHIVO
OUTER APPLY (SELECT TOP (1) x.ENCABEZADOS, x.FECHA FROM ops.ARCHIVO_CARGADO x
             WHERE x.CODIGO = a.CODIGO AND x.ENCABEZADOS IS NOT NULL ORDER BY x.FECHA DESC, x.ID_CORRIDA DESC) u
OUTER APPLY (SELECT MIN(CAST(h.[key] AS INT)) + 1 AS COLUMNA FROM OPENJSON(u.ENCABEZADOS) h
             WHERE UPPER(h.[value]) COLLATE Latin1_General_CI_AI LIKE UPPER(c.PATRON_ENCABEZADO) COLLATE Latin1_General_CI_AI) p;
GO

/* Catálogos de etiquetado con sus valores; VALIDA = 1 si un valor fuera del catálogo detiene el proceso */
CREATE OR ALTER VIEW cfg.v_CATALOGO
AS
SELECT d.CLIENTE, d.CATALOGO, d.DESCRIPCION, d.ORIGEN, d.DESTINO,
       c.VALOR_ORIGEN, c.VALOR_DESTINO, c.ORDEN, c.ACTIVO, c.ALTA_POR, c.USUARIO, c.FE_MOD,
       CASE WHEN EXISTS (SELECT 1 FROM cfg.VALIDACION_DATO v WHERE v.CLIENTE = d.CLIENTE AND v.TIPO = 'CATALOGO'
                         AND v.VALOR = d.CATALOGO AND v.ACTIVO = 1) THEN 1 ELSE 0 END AS VALIDA
FROM cfg.CATALOGO_DEF d
LEFT JOIN cfg.CATALOGO c ON c.CLIENTE = d.CLIENTE AND c.CATALOGO = d.CATALOGO;
GO
