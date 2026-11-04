/* =====================================================================
   Banbaj · 78 Pasos que antes hacía el operador y ahora hace el job (decisión 02/11)
   ---------------------------------------------------------------------
   ops.sp_exportar_auto          escribe los archivos de cada corrida al terminar OK
                                 (EXPORTAR_AUTOMATICO)
   ops.sp_act_cyber              ejecuta en CYBER ACT_SALDOS, ACT_VENCIDO, ACT_PAGMIN y
                                 ACT_PVS_REE al terminar la actualización (ACT_CYBER_AUTOMATICO)
   ops.sp_blanqueo_automatico    blanqueo de status (días DIAS_BLANQUEO_STATUS) en cuanto
                                 el arribo de correos confirma que subió el SCBSDOS
                                 (BLANQUEO_AUTOMATICO)
   ops.sp_confirmar_asignacion   marca el fin del arribo y manda CONFIRMACION_ASIG_486 cuando
                                 el arribo automático terminó OK (CONFIRMACION_AUTOMATICA)
   ops.sp_cuadre_automatico      cuadre de pagos contra CYBER; solo avisa (HALLAZGO_486) si
                                 algún pago no subió (CUADRE_AUTOMATICO, CUADRE_PAGOS_HORA_LIMITE)

   Todo lo que falla queda en la bitácora y llega en el correo de hallazgos al equipo
   de asignaciones; no se reintenta solo. Cada procedimiento se puede correr a mano
   con el número de corrida y solo repite lo que no quedó OK.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Escribe los archivos y scripts de la corrida (ops.sp_exportar_salidas) si EXPORTAR_AUTOMATICO = 1 */
CREATE OR ALTER PROCEDURE ops.sp_exportar_auto
    @id_corrida INT,
    @solo       NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @msg NVARCHAR(4000), @acc NVARCHAR(4000);
    SELECT @cliente = CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @cliente IS NULL OR ISNULL(cfg.fn_param(@cliente, 'EXPORTAR_AUTOMATICO'), '0') <> '1' RETURN;
    BEGIN TRY
        EXEC ops.sp_exportar_salidas @id_corrida, @solo = @solo;
        SET @msg = CONCAT(N'Archivos escritos', ISNULL(N' (' + @solo + N')', N''));
        EXEC ops.sp_log @id_corrida, 'EXPORTAR AUTOMATICO', 'OK', NULL, @msg;
        EXEC ops.sp_aviso_archivos @id_corrida, @solo;     -- aviso a asignaciones: ya pueden arribar
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'EXPORTAR AUTOMATICO', 'ERROR', NULL, @msg;
        SET @acc = CONCAT(N'Revisar la carpeta RUTA_SALIDA y los permisos de la cuenta del servicio de SQL Server; luego EXEC ops.sp_exportar_salidas ', @id_corrida,
                          CASE WHEN @solo IS NULL THEN N'' ELSE N', @solo = N''' + @solo + N'''' END, N';');
        EXEC mail.sp_hallazgo @id_corrida, N'No se pudieron escribir los archivos', @msg, @acc;
    END CATCH;
END;
GO

/* Scripts de la actualización en CYBER por el servidor vinculado (antes se corrían a mano en Oracle).
   Solo ejecuta los que no han quedado OK; @solo_mostrar = 1 enseña cuáles faltan. */
CREATE OR ALTER PROCEDURE ops.sp_act_cyber
    @id_corrida   INT,
    @solo_mostrar BIT = 0,
    @resultado    NVARCHAR(400) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @srv SYSNAME, @s VARCHAR(40), @n INT, @msg NVARCHAR(4000),
            @err INT = 0, @tabla NVARCHAR(MAX), @acc NVARCHAR(4000), @paso VARCHAR(80);
    SELECT @cliente = CLIENTE, @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ACT' THROW 50772, 'Indica una corrida de actualización.', 1;
    SET @srv = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER');

    SELECT v.ORDEN, v.SCRIPT,
           (SELECT COUNT(*) FROM ops.CYBER_SCRIPT c WHERE c.ID_CORRIDA = @id_corrida AND c.SCRIPT = v.SCRIPT) AS LINEAS,
           CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA b WHERE b.ID_CORRIDA = @id_corrida AND b.PASO = 'ACT CYBER ' + v.SCRIPT AND b.ESTATUS = 'OK')
                THEN 'HECHO' ELSE 'PENDIENTE' END AS ESTADO
    INTO #p
    FROM (VALUES (1, 'ACT_SALDOS'), (2, 'ACT_VENCIDO'), (3, 'ACT_PAGMIN'), (4, 'ACT_PVS_REE')) v(ORDEN, SCRIPT);
    DELETE FROM #p WHERE LINEAS = 0;

    IF @solo_mostrar = 1
    BEGIN
        SELECT ORDEN, SCRIPT, LINEAS, ESTADO FROM #p ORDER BY ORDEN;
        RETURN;
    END;
    IF @@TRANCOUNT > 0 THROW 50773, 'La ejecución en CYBER no puede correr dentro de una transacción.', 1;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT SCRIPT FROM #p WHERE ESTADO = 'PENDIENTE' ORDER BY ORDEN;
    OPEN c; FETCH NEXT FROM c INTO @s;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
            BEGIN
                SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'. Captura la credencial CYBER_ORACLE y corre EXEC cfg.sp_cyber_conectar;');
                THROW 50823, @msg, 1;
            END;
            EXEC ops.sp_cyber_ejecutar @id_corrida, @s, @sentencias = @n OUTPUT;
            SET @msg = CONCAT(@s, N' ejecutado en CYBER');
            SET @paso = 'ACT CYBER ' + @s;
            EXEC ops.sp_log @id_corrida, @paso, 'OK', @n, @msg;
        END TRY
        BEGIN CATCH
            SET @msg = ERROR_MESSAGE();
            SET @paso = 'ACT CYBER ' + @s;
            EXEC ops.sp_log @id_corrida, @paso, 'ERROR', NULL, @msg;
            SET @err += 1;
        END CATCH;
        FETCH NEXT FROM c INTO @s;
    END;
    CLOSE c; DEALLOCATE c;

    SET @resultado = CASE WHEN @err = 0 THEN N'ACTUALIZACION EN CYBER OK' ELSE N'ACTUALIZACION EN CYBER CON ERRORES' END;
    IF @err > 0
    BEGIN
        SET @tabla = (SELECT b.PASO AS [Script], b.ESTATUS AS [Estatus], ISNULL(b.MENSAJE, N'') AS [Mensaje]
                      FROM ops.BITACORA b
                      WHERE b.ID_CORRIDA = @id_corrida AND b.PASO LIKE 'ACT CYBER %'
                        AND b.ID = (SELECT MAX(x.ID) FROM ops.BITACORA x WHERE x.ID_CORRIDA = b.ID_CORRIDA AND x.PASO = b.PASO)
                      ORDER BY b.ID FOR JSON PATH);
        SET @msg = CONCAT(@err, N' script(s) de la actualización no se pudieron ejecutar en CYBER (saldos, vencido, pago mínimo o PVS/REE).');
        SET @acc = CONCAT(N'Corregir la causa (ver la tabla) y correr EXEC ops.sp_act_cyber ', @id_corrida, N'; solo repite lo que no quedó OK.');
        EXEC mail.sp_hallazgo @id_corrida, N'Actualización en CYBER con error', @msg, @acc, @tabla;
    END;
    SELECT @resultado AS ACT_CYBER, @id_corrida AS CORRIDA;
END;
GO

/* Blanqueo de status automático: una vez por asignación, cuando el SCBSDOS ya subió
   (las cuentas reasignadas tienen que estar activas en DELQMST para bajar su status). */
CREATE OR ALTER PROCEDURE ops.sp_blanqueo_automatico
    @id_corrida INT,
    @forzar     BIT = 0          -- 1 = lo repite aunque ya se haya intentado
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @fecha DATE, @dias VARCHAR(20), @d1 INT, @d2 INT,
            @n INT, @k INT, @msg NVARCHAR(4000), @acc NVARCHAR(4000), @archivos NVARCHAR(400);
    SELECT @cliente = CLIENTE, @proceso = PROCESO, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ASIG' THROW 50610, 'Indica una corrida de asignación.', 1;
    IF ISNULL(cfg.fn_param(@cliente, 'BLANQUEO_AUTOMATICO'), '0') <> '1' AND @forzar = 0 RETURN;
    IF @forzar = 0 AND EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'BLANQUEO AUTOMATICO') RETURN;

    SET @dias = ISNULL(cfg.fn_param(@cliente, 'DIAS_BLANQUEO_STATUS'), '1-10');
    SELECT @d1 = TRY_CONVERT(INT, LEFT(@dias, CHARINDEX('-', @dias + '-') - 1)),
           @d2 = TRY_CONVERT(INT, SUBSTRING(@dias, CHARINDEX('-', @dias + '-') + 1, 10));
    IF DAY(@fecha) NOT BETWEEN ISNULL(@d1, 1) AND ISNULL(@d2, 31)
    BEGIN
        SET @msg = CONCAT(N'Hoy no toca blanquear status (días ', @dias, N')');
        EXEC ops.sp_log @id_corrida, 'BLANQUEO AUTOMATICO', 'OK', 0, @msg;
        RETURN;
    END;

    BEGIN TRY
        EXEC ops.sp_bajar_cyber 'STATUS', @id_corrida = @id_corrida;      -- baja los status y arma el script BLANQUEO_STATUS
        SET @n = (SELECT COUNT(*) FROM ops.STATUS_CYBER WHERE ID_CORRIDA = @id_corrida AND BLANQUEA = 1);
        IF @n > 0
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'BLANQUEO_STATUS', @sentencias = @k OUTPUT;
        SET @archivos = (SELECT STRING_AGG(ARCHIVO, ',') FROM cfg.SALIDA_ARCHIVO WHERE CLIENTE = @cliente AND PROCESO = 'BLANQUEO' AND ACTIVO = 1);
        IF @archivos IS NOT NULL EXEC ops.sp_exportar_auto @id_corrida, @solo = @archivos;
        SET @msg = CONCAT(N'Status blanqueados en CYBER: ', @n);
        EXEC ops.sp_log @id_corrida, 'BLANQUEO AUTOMATICO', 'OK', @n, @msg;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'BLANQUEO AUTOMATICO', 'ERROR', NULL, @msg;
        SET @acc = CONCAT(N'Corregir la causa y correr EXEC ops.sp_blanqueo_automatico ', @id_corrida, N', @forzar = 1;');
        EXEC mail.sp_hallazgo @id_corrida, N'Blanqueo de status con error', @msg, @acc;
    END CATCH;
END;
GO

/* Fin del arribo de la asignación: marca la hora de fin y manda CONFIRMACION_ASIG_486 cuando correos
   y teléfonos quedaron OK en CYBER (y el blanqueo ya se intentó, si está automático). Una vez por corrida. */
CREATE OR ALTER PROCEDURE ops.sp_confirmar_asignacion
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    IF ISNULL(cfg.fn_param(@cliente, 'CONFIRMACION_AUTOMATICA'), '0') <> '1' RETURN;
    IF EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'CONFIRMACION AUTOMATICA') RETURN;
    IF NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'ARRIBO CORREOS' AND ESTATUS = 'OK')
       OR NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'ARRIBO TELEFONOS' AND ESTATUS = 'OK')
        RETURN;
    IF ISNULL(cfg.fn_param(@cliente, 'BLANQUEO_AUTOMATICO'), '0') = '1'
       AND NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'BLANQUEO AUTOMATICO')
        RETURN;

    IF NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'ARRIBO FIN')
        EXEC ops.sp_marcar_arribo @id_corrida, 'FIN', NULL, N'Marcado por el arribo automático';
    EXEC ops.sp_avisar @id_corrida, 'CONFIRMACION_ASIG_486';
    EXEC ops.sp_log @id_corrida, 'CONFIRMACION AUTOMATICA', 'OK', NULL, N'Fin del arribo marcado y CONFIRMACION_ASIG_486 enviada';
END;
GO

/* Cuadre de pagos automático: cada vuelta del job baja de CYBER los pagos del día y los compara con lo que
   se arribó en el SCBPAG de la actualización. Termina cuando todo subió (sin correo) o, si a la hora
   CUADRE_PAGOS_HORA_LIMITE todavía faltan, deja el cuadre (ops.sp_cuadrar_pagos) y avisa al equipo de
   asignaciones con la lista de pagos que no subieron. */
CREATE OR ALTER PROCEDURE ops.sp_cuadre_automatico
    @fecha     DATE = NULL,
    @cliente   VARCHAR(10) = '486',
    @sin_bajar BIT = 0,              -- 1 = usa lo que ya está en stg.CYBER_PAGO (pruebas)
    @hora      TIME(0) = NULL,       -- NULL = ahora (pruebas)
    @resultado NVARCHAR(400) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));
    SET @hora = ISNULL(@hora, CAST(GETDATE() AS TIME(0)));
    DECLARE @id INT, @arr INT, @no INT, @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @limite TIME(0) = ISNULL(TRY_CONVERT(TIME(0), cfg.fn_param(@cliente, 'CUADRE_PAGOS_HORA_LIMITE')), '17:00'),
            @msg NVARCHAR(4000), @acc NVARCHAR(4000), @tabla NVARCHAR(MAX);

    IF ISNULL(cfg.fn_param(@cliente, 'CUADRE_AUTOMATICO'), '0') <> '1'
    BEGIN
        SET @resultado = N'CUADRE AUTOMATICO APAGADO';
        RETURN;
    END;
    SELECT TOP (1) @id = ID_CORRIDA FROM ops.CORRIDA
    WHERE CLIENTE = @cliente AND PROCESO = 'ACT' AND FECHA_PROCESO = @fecha AND ESTATUS = 'OK' ORDER BY ID_CORRIDA DESC;
    IF @id IS NULL
    BEGIN
        SET @resultado = N'SIN ACTUALIZACION OK DEL DIA';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'CUADRE AUTOMATICO')
    BEGIN
        SET @resultado = N'CUADRE TERMINADO';
        RETURN;
    END;
    SET @arr = (SELECT COUNT(*) FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id AND ORIGEN = 'CORRIDA');
    IF @arr = 0
    BEGIN
        EXEC ops.sp_log @id, 'CUADRE AUTOMATICO', 'OK', 0, N'La actualización no arribó pagos';
        SET @resultado = N'CUADRE TERMINADO';
        RETURN;
    END;

    IF @sin_bajar = 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
        BEGIN
            SET @resultado = N'SIN SERVIDOR VINCULADO A CYBER';
            RETURN;
        END;
        EXEC ops.sp_bajar_cyber 'PAGOS', @fecha = @fecha, @solo_bajar = 1;   -- sin @id_corrida: no llena la bitácora en cada vuelta
    END;

    /* Mismo emparejamiento que ops.sp_cuadrar_pagos: CUENTA2 + importe, uno a uno */
    ;WITH arr AS (SELECT CUENTA2, IMPORTE, ROW_NUMBER() OVER (PARTITION BY CUENTA2, IMPORTE ORDER BY ID) AS RN
                  FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id AND ORIGEN = 'CORRIDA'),
          cyb AS (SELECT LTRIM(RTRIM(CUENTA)) AS CUENTA2, cfg.fn_importe(MONTO) AS IMPORTE,
                         ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(CUENTA)), cfg.fn_importe(MONTO) ORDER BY (SELECT NULL)) AS RN
                  FROM stg.CYBER_PAGO WHERE NULLIF(LTRIM(RTRIM(CUENTA)), N'') IS NOT NULL)
    SELECT @no = COUNT(*) FROM arr a
    WHERE NOT EXISTS (SELECT 1 FROM cyb c WHERE c.CUENTA2 = a.CUENTA2 AND c.IMPORTE = a.IMPORTE AND c.RN = a.RN);

    IF @no > 0 AND @hora < @limite AND @fecha >= CAST(GETDATE() AS DATE)
    BEGIN
        SET @resultado = CONCAT(N'ESPERANDO PAGOS EN CYBER (', @arr - @no, N' de ', @arr, N')');
        TRUNCATE TABLE stg.CYBER_PAGO;
        RETURN;
    END;

    /* Cierre: deja el cuadre en ops.RECHAZO y en la bitácora (CUADRE PAGOS) */
    EXEC ops.sp_cuadrar_pagos @id, @silencioso = 1;
    SET @no = (SELECT COUNT(*) FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'CUADRE_PAGOS');
    IF @no = 0
    BEGIN
        SET @msg = CONCAT(N'Los ', @arr, N' pagos arribados están en CYBER');
        EXEC ops.sp_log @id, 'CUADRE AUTOMATICO', 'OK', 0, @msg;
        SET @resultado = N'PAGOS CUADRADOS';
        RETURN;
    END;
    SET @msg = CONCAT(@no, N' de ', @arr, N' pagos arribados en el SCBPAG no aparecen en CYBER a las ', CONVERT(CHAR(5), @hora, 108), N'.');
    EXEC ops.sp_log @id, 'CUADRE AUTOMATICO', 'AVISO', @no, @msg;
    SET @tabla = (SELECT TOP (100) JSON_VALUE(DATOS, '$.CUENTA2') AS [Cuenta], JSON_VALUE(DATOS, '$.IMPORTE') AS [Importe]
                  FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'CUADRE_PAGOS' ORDER BY ID FOR JSON PATH);
    SET @acc = CONCAT(N'Revisar si se subió el SCBPAG de la corrida ', @id, N' y si CYBER lo rechazó. La lista completa: ',
                      N'SELECT DATOS FROM ops.RECHAZO WHERE ID_CORRIDA = ', @id, N' AND ORIGEN = ''CUADRE_PAGOS''',
                      CASE WHEN @no > 100 THEN N' (el correo trae los primeros 100).' ELSE N'.' END);
    EXEC mail.sp_hallazgo @id, N'Pagos que no subieron a CYBER', @msg, @acc, @tabla;
    SET @resultado = CONCAT(N'PAGOS SIN SUBIR: ', @no);
END;
GO

/* Lo que sigue al arribo de la asignación: blanqueo de status (cuando ya subió el SCBSDOS y se arribaron
   los correos) y confirmación (cuando correos y teléfonos quedaron OK). Lo llama ops.sp_arribo_automatico. */
CREATE OR ALTER PROCEDURE ops.sp_arribo_posterior
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @msg NVARCHAR(4000);
    IF EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'ARRIBO CORREOS' AND ESTATUS = 'OK')
    BEGIN
        BEGIN TRY
            EXEC ops.sp_blanqueo_automatico @id_corrida;
        END TRY
        BEGIN CATCH
            SET @msg = ERROR_MESSAGE();
            EXEC ops.sp_log @id_corrida, 'BLANQUEO AUTOMATICO', 'ERROR', NULL, @msg;
        END CATCH;
    END;
    BEGIN TRY
        EXEC ops.sp_confirmar_asignacion @id_corrida;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'CONFIRMACION AUTOMATICA', 'ERROR', NULL, @msg;
    END CATCH;
END;
GO

/* Aviso de archivos listos para arribar (decisión 03/11): en cuanto se escriben los planos que el equipo de
   asignaciones sube a CYBER con el cargador (ARCHIVOS_ARRIBO), les llega ARCHIVOS_LISTOS_486 con la carpeta,
   cada archivo con sus líneas y qué sigue. Lo llaman ops.sp_exportar_auto, ops.sp_retiro_cerrar y el arribo
   de teléfonos (SCBACTH_SINTEL). El mismo grupo de archivos no se avisa dos veces en la corrida.
   A mano: EXEC ops.sp_aviso_archivos <corrida>; */
CREATE OR ALTER PROCEDURE ops.sp_aviso_archivos
    @id_corrida  INT,
    @solo        NVARCHAR(400) = NULL,   -- solo estos archivos (ej. GESCAR_SINTEL)
    @solo_prueba BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @fecha DATE, @carpeta NVARCHAR(400), @lista NVARCHAR(400),
            @tabla NVARCHAR(MAX), @sigue NVARCHAR(2000), @json NVARCHAR(MAX), @clave NVARCHAR(400);
    SELECT @cliente = CLIENTE, @proceso = PROCESO, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @cliente IS NULL THROW 50774, 'La corrida no existe.', 1;
    IF @solo_prueba = 0 AND ISNULL(cfg.fn_param(@cliente, 'AVISO_ARCHIVOS'), '0') <> '1' RETURN;

    SELECT a.ARCHIVO, a.ORDEN,
           REPLACE(REPLACE(ISNULL(a.NOMBRE, a.ARCHIVO + N'.TXT'), N'{AAAAMMDD}', CONVERT(CHAR(8), @fecha, 112)),
                   N'{MMDDAAAA}', REPLACE(CONVERT(CHAR(10), @fecha, 101), '/', '')) AS NOMBRE,
           (SELECT COUNT(*) FROM ops.SALIDA_LINEA l WHERE l.ID_CORRIDA = @id_corrida AND l.ARCHIVO = a.ARCHIVO) AS LINEAS,
           ISNULL(a.DESCRIPCION, N'') AS DESCRIPCION
    INTO #a
    FROM cfg.SALIDA_ARCHIVO a
    WHERE a.CLIENTE = @cliente
      AND a.ARCHIVO IN (SELECT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'ARCHIVOS_ARRIBO'), N''), N','))
      AND (@solo IS NULL OR a.ARCHIVO IN (SELECT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(@solo, N',')))
      AND EXISTS (SELECT 1 FROM ops.SALIDA_LINEA l WHERE l.ID_CORRIDA = @id_corrida AND l.ARCHIVO = a.ARCHIVO);
    IF NOT EXISTS (SELECT 1 FROM #a) RETURN;

    SET @lista = (SELECT STRING_AGG(NOMBRE, N', ') WITHIN GROUP (ORDER BY ORDEN) FROM #a);
    SET @clave = LEFT(CONCAT(N'Archivos listos para arribar: ', @lista), 400);
    IF @solo_prueba = 0 AND EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'AVISO ARCHIVOS' AND MENSAJE = @clave) RETURN;

    SET @carpeta = ISNULL(cfg.fn_param(@cliente, 'RUTA_SALIDA'), N'C:\BANBAJ\486\SALIDA\');
    IF RIGHT(@carpeta, 1) <> N'\' SET @carpeta += N'\';
    SET @carpeta = CONCAT(@carpeta, CONVERT(CHAR(8), @fecha, 112), N'_corrida', @id_corrida, N'\');
    SET @tabla = mail.fn_tabla_html((SELECT NOMBRE AS [Archivo], CAST(LINEAS AS NVARCHAR(12)) AS [Líneas], DESCRIPCION AS [Qué es]
                                     FROM #a ORDER BY ORDEN FOR JSON PATH));
    /* Qué sigue depende de qué está automático: hoy solo se generan archivos y las depuraciones en CYBER son manuales */
    DECLARE @auto_arribo BIT = CASE WHEN cfg.fn_param(@cliente, 'ARRIBO_AUTOMATICO') = '1' THEN 1 ELSE 0 END,
            @auto_act    BIT = CASE WHEN cfg.fn_param(@cliente, 'ACT_CYBER_AUTOMATICO') = '1' THEN 1 ELSE 0 END,
            @auto_ret    BIT = CASE WHEN cfg.fn_param(@cliente, 'RETIRO_CYBER_AUTOMATICO') = '1' THEN 1 ELSE 0 END;
    SET @sigue = CASE
        WHEN EXISTS (SELECT 1 FROM #a WHERE ARCHIVO IN ('SCBSDOS', 'SCBTEL'))
            THEN N'Subir primero SCBSDOS y SCBTEL con el cargador de CYBER y después los gescar. '
               + CASE WHEN @auto_arribo = 1
                      THEN N'En cuanto suben, el job arriba solo correos y teléfonos, genera SCBACTH_SINTEL.TXT (llega otro aviso) y manda la confirmación de la asignación.'
                      ELSE CONCAT(N'Después correr las depuraciones a mano: EXEC ops.sp_arribar_cyber ', @id_corrida, N', ''CORREOS''; y EXEC ops.sp_arribar_cyber ', @id_corrida,
                                  N', ''TELEFONOS''; (este último genera SCBACTH_SINTEL.TXT y llega otro aviso). Al terminar, EXEC ops.sp_avisar ', @id_corrida, N', ''CONFIRMACION_ASIG_486'';') END
        WHEN EXISTS (SELECT 1 FROM #a WHERE ARCHIVO = 'SCBPAG')
            THEN N'Subir SCBPAG con el cargador de CYBER. '
               + CASE WHEN @auto_act = 1 THEN N'Los saldos, vencido, pago mínimo y PVS/REE ya se ejecutan solos.'
                      ELSE CONCAT(N'Correr los scripts de saldos, vencido, pago mínimo y PVS/REE: EXEC ops.sp_act_cyber ', @id_corrida, N'; (o los .sql de la carpeta cyber\).') END
               + N' Si a la hora límite algún pago no aparece en CYBER, llega un hallazgo.'
        WHEN EXISTS (SELECT 1 FROM #a WHERE ARCHIVO = 'GESCAR_SINTEL')
            THEN N'Subir SCBACTH_SINTEL.TXT (gescar de cuentas sin teléfono) con el cargador de CYBER.'
        ELSE N'Subir estos archivos con el cargador de CYBER.' END
        + CASE WHEN NOT EXISTS (SELECT 1 FROM #a WHERE ARCHIVO = 'GESCAR_RETIRO') THEN N''
               WHEN @auto_ret = 1 THEN N' Hubo retiro: subir también SCBACTH_486.TXT; el retiro en CYBER y la copia de la devolución ya se hicieron solos.'
               ELSE CONCAT(N' Hubo retiro: subir también SCBACTH_486.TXT y aplicar el retiro en CYBER con la copia de la devolución: EXEC ops.sp_retiro_cerrar ', @id_corrida, N', @con_cyber = 1;') END;

    SET @json = (SELECT @proceso AS PROCESO, @carpeta AS CARPETA, @lista AS ARCHIVOS, @sigue AS SIGUE, @tabla AS HTML_TABLA
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    IF @solo_prueba = 0 EXEC ops.sp_log @id_corrida, 'AVISO ARCHIVOS', 'OK', NULL, @clave;
    EXEC mail.sp_enviar @plantilla = 'ARCHIVOS_LISTOS_486', @id_corrida = @id_corrida, @valores = @json, @solo_prueba = @solo_prueba;
END;
GO
