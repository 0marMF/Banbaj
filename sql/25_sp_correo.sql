/* =====================================================================
   Banbaj · 25 Correo dinámico
   ---------------------------------------------------------------------
   mail.sp_enviar               arma destinatarios desde mail.DESTINATARIO,
                                reemplaza marcadores y envía por Database Mail
   mail.sp_destinatario_alta    agrega (o reactiva) un correo en una lista
   mail.sp_destinatario_baja    da de baja un correo (no se borra: queda historial)

   Marcadores en ASUNTO y CUERPO_HTML:
     {{FECHA}}           fecha de hoy dd/mm/aaaa
     {{FECHA_PROCESO}}   fecha de la corrida dd/mm/aaaa
     {{ID_CORRIDA}} {{CLIENTE}}
     {{FRAG:<codigo>}}   HTML de mail.FRAGMENTO (firma, aviso de confidencialidad)
     {{<LLAVE>}}         cualquier llave del JSON @valores, ej. {"REGISTROS":15}

   Un error de correo NO detiene el proceso: se registra en mail.ENVIO y
   el SP regresa 1. El adjunto debe ser una ruta visible para el servicio
   de SQL Server; el zip con contraseña se arma antes, en un paso del job.
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE mail.sp_enviar
    @plantilla   VARCHAR(60),
    @id_corrida  INT           = NULL,
    @valores     NVARCHAR(MAX) = NULL,     -- JSON plano {"LLAVE":"valor"}
    @adjuntos    NVARCHAR(MAX) = NULL,     -- rutas separadas por ';'
    @solo_prueba BIT           = 0         -- 1 = no envía; devuelve el correo armado
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @lista VARCHAR(60), @perfil SYSNAME, @asunto NVARCHAR(255), @cuerpo NVARCHAR(MAX), @imp VARCHAR(6),
            @para NVARCHAR(MAX), @cc NVARCHAR(MAX), @cco NVARCHAR(MAX), @mid INT,
            @cliente VARCHAR(10), @fecha_proc DATE, @k NVARCHAR(400), @v NVARCHAR(MAX);

    SELECT @lista = LISTA, @perfil = PERFIL_DBMAIL, @asunto = ASUNTO, @cuerpo = CUERPO_HTML, @imp = IMPORTANCIA
    FROM mail.PLANTILLA WHERE CODIGO = @plantilla AND ACTIVO = 1;

    IF @lista IS NULL
    BEGIN
        INSERT INTO mail.ENVIO (ID_CORRIDA, PLANTILLA, ESTATUS, ERROR)
        VALUES (@id_corrida, @plantilla, 'ERROR', N'Plantilla inexistente o inactiva');
        RETURN 1;
    END;

    SELECT @para = PARA, @cc = CC, @cco = CCO FROM mail.v_LISTA_RESUELTA WHERE LISTA = @lista;
    IF @para IS NULL AND @cc IS NULL AND @cco IS NULL
    BEGIN
        INSERT INTO mail.ENVIO (ID_CORRIDA, PLANTILLA, ASUNTO, ESTATUS, ERROR)
        VALUES (@id_corrida, @plantilla, @asunto, 'SIN_DESTINO', N'La lista ' + @lista + N' no tiene destinatarios vigentes');
        RETURN 1;
    END;

    /* Fragmentos */
    DECLARE frag CURSOR LOCAL FAST_FORWARD FOR SELECT CODIGO, HTML FROM mail.FRAGMENTO;
    OPEN frag; FETCH NEXT FROM frag INTO @k, @v;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cuerpo = REPLACE(@cuerpo, N'{{FRAG:' + @k + N'}}', @v);
        FETCH NEXT FROM frag INTO @k, @v;
    END;
    CLOSE frag; DEALLOCATE frag;

    /* Marcadores fijos */
    SELECT @cliente = CLIENTE, @fecha_proc = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    SET @asunto = REPLACE(REPLACE(REPLACE(REPLACE(@asunto,
                  N'{{FECHA}}', CONVERT(CHAR(10), GETDATE(), 103)),
                  N'{{FECHA_PROCESO}}', ISNULL(CONVERT(CHAR(10), @fecha_proc, 103), N'')),
                  N'{{ID_CORRIDA}}', ISNULL(CAST(@id_corrida AS NVARCHAR(12)), N'')),
                  N'{{CLIENTE}}', ISNULL(@cliente, N''));
    SET @cuerpo = REPLACE(REPLACE(REPLACE(REPLACE(@cuerpo,
                  N'{{FECHA}}', CONVERT(CHAR(10), GETDATE(), 103)),
                  N'{{FECHA_PROCESO}}', ISNULL(CONVERT(CHAR(10), @fecha_proc, 103), N'')),
                  N'{{ID_CORRIDA}}', ISNULL(CAST(@id_corrida AS NVARCHAR(12)), N'')),
                  N'{{CLIENTE}}', ISNULL(@cliente, N''));

    /* Marcadores del JSON (el valor se escapa para HTML en el cuerpo) */
    IF ISJSON(@valores) = 1
    BEGIN
        DECLARE val CURSOR LOCAL FAST_FORWARD FOR SELECT [key], [value] FROM OPENJSON(@valores);
        OPEN val; FETCH NEXT FROM val INTO @k, @v;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @asunto = REPLACE(@asunto, N'{{' + @k + N'}}', ISNULL(@v, N''));
            SET @cuerpo = REPLACE(@cuerpo, N'{{' + @k + N'}}',
                          CASE WHEN @k LIKE N'HTML[_]%' THEN ISNULL(@v, N'')       -- HTML_*: ya viene armado y escapado (mail.sp_hallazgo)
                               ELSE REPLACE(REPLACE(REPLACE(ISNULL(@v, N''), N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;') END);
            FETCH NEXT FROM val INTO @k, @v;
        END;
        CLOSE val; DEALLOCATE val;
    END;

    IF @solo_prueba = 1
    BEGIN
        INSERT INTO mail.ENVIO (ID_CORRIDA, PLANTILLA, PARA, CC, CCO, ASUNTO, ADJUNTOS, ESTATUS)
        VALUES (@id_corrida, @plantilla, @para, @cc, @cco, @asunto, @adjuntos, 'PRUEBA');
        SELECT @para AS PARA, @cc AS CC, @cco AS CCO, @asunto AS ASUNTO, @cuerpo AS CUERPO_HTML, @adjuntos AS ADJUNTOS;
        RETURN 0;
    END;

    BEGIN TRY
        EXEC msdb.dbo.sp_send_dbmail
             @profile_name          = @perfil,
             @recipients            = @para,
             @copy_recipients       = @cc,
             @blind_copy_recipients = @cco,
             @subject               = @asunto,
             @body                  = @cuerpo,
             @body_format           = 'HTML',
             @importance            = @imp,
             @file_attachments      = @adjuntos,
             @mailitem_id           = @mid OUTPUT;
        INSERT INTO mail.ENVIO (ID_CORRIDA, PLANTILLA, PARA, CC, CCO, ASUNTO, ADJUNTOS, MAILITEM_ID, ESTATUS)
        VALUES (@id_corrida, @plantilla, @para, @cc, @cco, @asunto, @adjuntos, @mid, 'ENVIADO');
        IF @id_corrida IS NOT NULL EXEC ops.sp_log @id_corrida, 'CORREO', 'OK', NULL, @plantilla;
        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
        INSERT INTO mail.ENVIO (ID_CORRIDA, PLANTILLA, PARA, CC, CCO, ASUNTO, ADJUNTOS, ESTATUS, ERROR)
        VALUES (@id_corrida, @plantilla, @para, @cc, @cco, @asunto, @adjuntos, 'ERROR', @err);
        IF @id_corrida IS NOT NULL EXEC ops.sp_log @id_corrida, 'CORREO', 'AVISO', NULL, @err;
        RETURN 1;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE mail.sp_destinatario_alta
    @lista   VARCHAR(60),
    @email   VARCHAR(320),
    @tipo    VARCHAR(3)    = 'TO',
    @nombre  NVARCHAR(150) = NULL,
    @desde   DATE          = NULL,
    @hasta   DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @email = LOWER(LTRIM(RTRIM(@email)));
    IF NOT EXISTS (SELECT 1 FROM mail.LISTA WHERE CODIGO = @lista)
        THROW 50060, 'La lista no existe en mail.LISTA.', 1;

    IF EXISTS (SELECT 1 FROM mail.DESTINATARIO WHERE LISTA = @lista AND EMAIL = @email AND TIPO = @tipo)
        UPDATE mail.DESTINATARIO
        SET ACTIVO = 1, NOMBRE = ISNULL(@nombre, NOMBRE),
            VIGENTE_DESDE = ISNULL(@desde, CAST(GETDATE() AS DATE)), VIGENTE_HASTA = @hasta
        WHERE LISTA = @lista AND EMAIL = @email AND TIPO = @tipo;
    ELSE
        INSERT INTO mail.DESTINATARIO (LISTA, EMAIL, NOMBRE, TIPO, VIGENTE_DESDE, VIGENTE_HASTA)
        VALUES (@lista, @email, @nombre, @tipo, ISNULL(@desde, CAST(GETDATE() AS DATE)), @hasta);
END;
GO

CREATE OR ALTER PROCEDURE mail.sp_destinatario_baja
    @lista  VARCHAR(60),
    @email  VARCHAR(320),
    @tipo   VARCHAR(3) = NULL          -- NULL = en todos los tipos de esa lista
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE mail.DESTINATARIO
    SET ACTIVO = 0, VIGENTE_HASTA = CAST(GETDATE() AS DATE)
    WHERE LISTA = @lista AND EMAIL = LOWER(LTRIM(RTRIM(@email))) AND (@tipo IS NULL OR TIPO = @tipo);
    IF @@ROWCOUNT = 0
        THROW 50061, 'El correo no está en esa lista.', 1;
END;
GO

/* Tabla HTML a partir de un arreglo JSON de objetos (una columna por llave), con los valores escapados.
   La usan el correo de hallazgos y el de archivos listos. */
CREATE OR ALTER FUNCTION mail.fn_tabla_html (@tabla_json NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @th NVARCHAR(MAX), @tr NVARCHAR(MAX);
    IF ISJSON(@tabla_json) = 0 OR LEFT(LTRIM(@tabla_json), 1) <> N'[' RETURN N'';
    SELECT @th = STRING_AGG(CAST(N'<th style="border:1px solid #999;padding:4px 8px;background:#e8eef7;text-align:left">'
                 + REPLACE(REPLACE(REPLACE([key], N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;') + N'</th>' AS NVARCHAR(MAX)), N'')
    FROM OPENJSON(JSON_QUERY(@tabla_json, '$[0]'));
    SELECT @tr = STRING_AGG(CAST(N'<tr>' + c.TD + N'</tr>' AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY CAST(r.[key] AS INT))
    FROM OPENJSON(@tabla_json) r
    CROSS APPLY (SELECT STRING_AGG(CAST(N'<td style="border:1px solid #999;padding:4px 8px">'
                     + REPLACE(REPLACE(REPLACE(ISNULL(v.[value], N''), N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;') + N'</td>' AS NVARCHAR(MAX)), N'') AS TD
                 FROM OPENJSON(r.[value]) v) c
    WHERE r.[type] = 5;
    IF @th IS NULL RETURN N'';
    RETURN N'<table style="border-collapse:collapse;font-family:Arial;font-size:12px;margin:8px 0"><tr>' + @th + N'</tr>' + ISNULL(@tr, N'') + N'</table>';
END;
GO

/* Correo de hallazgos (decisión 02/11): avisa al equipo de asignaciones (plantilla HALLAZGO_486,
   lista ASIGNACIONES_486) lo que Banbaj encontró y no pudo resolver solo: un retiro que supera el
   tope y se vuelve manual, un arribo a CYBER o un cierre de retiro que falló.
   El correo dice qué pasó, trae una tabla con el detalle (@tabla_json: arreglo de objetos, una
   columna por llave) y qué hacer. El mismo hallazgo no se repite en la misma corrida.
   Queda registro en ops.BITACORA (paso HALLAZGO). */
CREATE OR ALTER PROCEDURE mail.sp_hallazgo
    @id_corrida  INT,
    @tipo        NVARCHAR(100),             -- título corto (va en el asunto)
    @detalle     NVARCHAR(4000),            -- qué pasó
    @accion      NVARCHAR(4000) = NULL,     -- qué hacer
    @tabla_json  NVARCHAR(MAX)  = NULL,     -- [{"Segmento":"TDC","A retirar":"120"}, …]
    @solo_prueba BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @tabla NVARCHAR(MAX) = N'',
            @json NVARCHAR(MAX), @clave NVARCHAR(400) = LEFT(CONCAT(@tipo, N': ', @detalle), 400);
    SELECT @cliente = CLIENTE, @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    SET @cliente = ISNULL(@cliente, '486');

    IF @solo_prueba = 0 AND EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'HALLAZGO' AND MENSAJE = @clave)
        RETURN 0;

    SET @tabla = mail.fn_tabla_html(@tabla_json);

    SET @json = (SELECT @tipo AS TIPO, @detalle AS DETALLE, ISNULL(@accion, N'Revisar la bitácora de la corrida.') AS ACCION,
                        ISNULL(@proceso, N'') AS PROCESO, @tabla AS HTML_TABLA
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    IF @solo_prueba = 0 EXEC ops.sp_log @id_corrida, 'HALLAZGO', 'AVISO', NULL, @clave;
    EXEC mail.sp_enviar @plantilla = 'HALLAZGO_486', @id_corrida = @id_corrida, @valores = @json, @solo_prueba = @solo_prueba;
    RETURN 0;
END;
GO
