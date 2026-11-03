/* =====================================================================
   Banbaj · 60 Orquestadores (un SP por proceso)
   ---------------------------------------------------------------------
   ops.sp_asignacion_486      reemplaza paso.prg (+ asig_bases, asi486)
   ops.sp_actualizacion_486   reemplaza saldos.prg y pagos.prg
   ops.sp_retiro_solicitud    retiro fuera de proceso por folio o riesgo (sql/32)

   Avisos a Operación: ops.sp_avisar después del arribo (sql/70).
   Los archivos planos quedan en ops.SALIDA_LINEA y los scripts de CYBER en
   ops.CYBER_SCRIPT; se escriben con ops.sp_exportar_salidas y se arriban a mano.

   @aplicar_retiro = 0 (default): las devoluciones quedan en ops.DEVOLUCION
   para revisión y se aplican después con EXEC ops.sp_retiro @id_corrida.
   Así se conserva la confirmación que hoy hace el operador.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Homologa cada tabla de entrada cargada en la corrida */
CREATE OR ALTER PROCEDURE ops.sp_homologar_entradas
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t SYSNAME;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT a.TABLA_DESTINO
        FROM cfg.ARCHIVO a
        JOIN ops.ARCHIVO_CARGADO c ON c.ID_ARCHIVO = a.ID_ARCHIVO AND c.ID_CORRIDA = @id_corrida AND c.ESTATUS = 'CARGADO'
        ORDER BY a.ORDEN;
    OPEN cur;
    FETCH NEXT FROM cur INTO @t;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC ops.sp_homologar @id_corrida, @t;
        FETCH NEXT FROM cur INTO @t;
    END;
    CLOSE cur; DEALLOCATE cur;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_asignacion_486
    @fecha             DATE    = NULL,
    @hora_llegada      TIME(0) = NULL,
    @forzar_devolucion BIT     = 0,
    @aplicar_retiro    BIT     = 0,
    @id_corrida        INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @recibidos INT, @msg NVARCHAR(4000), @json NVARCHAR(MAX);
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));

    /* La asignación siempre llega después de la actualización del día */
    IF ISNULL(cfg.fn_param('486', 'ASIG_REQUIERE_ACT'), '1') = '1'
       AND NOT EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = '486' AND PROCESO = 'ACT' AND FECHA_PROCESO = @fecha AND ESTATUS = 'OK')
        THROW 50110, 'Primero debe terminar OK la actualización del mismo día (parámetro ASIG_REQUIERE_ACT).', 1;

    EXEC ops.sp_corrida_iniciar '486', 'ASIG', @fecha, @hora_llegada, @id_corrida OUTPUT;
    /* Correo de inicio de asignación a Operación (decisión 30/10) */
    SET @json = (SELECT @id_corrida AS CORRIDA, ISNULL(CONVERT(VARCHAR(5), @hora_llegada, 108), 'sin registrar') AS HORA_LLEGADA FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC mail.sp_enviar @plantilla = 'INICIO_ASIG_486', @id_corrida = @id_corrida, @valores = @json;

    BEGIN TRY
        EXEC ops.sp_respaldo           @id_corrida;
        EXEC ops.sp_cargar_proceso     @id_corrida, @recibidos OUTPUT;
        EXEC ops.sp_homologar_entradas @id_corrida;
        EXEC ops.sp_validar            @id_corrida, 'POST_CARGA';
        EXEC ops.sp_asig_unir_layout   @id_corrida;
        EXEC ops.sp_homologar          @id_corrida, 'stg.LAYOUT_486';
        EXEC ops.sp_asig_devolucion    @id_corrida, @forzar_devolucion;
        EXEC ops.sp_asig_existentes    @id_corrida;                    -- existentes: teléfonos tal como llegan
        EXEC ops.sp_telefonos_refrescar_cyber @id_corrida;             -- quejas (telbaj) y plan de numeración vigentes de CYBER
        EXEC ops.sp_asig_normalizar_telefonos @id_corrida;             -- nuevas y reasignadas: op9.prg (AREA + TELEFONO)
        EXEC ops.sp_validar            @id_corrida, 'PRE_ALTA';
        EXEC ops.sp_asig_alta          @id_corrida;
        IF @aplicar_retiro = 1
            EXEC ops.sp_retiro         @id_corrida;                    -- genera también los archivos del retiro
        EXEC ops.sp_telefonos          @id_corrida;                    -- solo en asignación: CYBER purga y agrega
        EXEC ops.sp_correos            @id_corrida;                    -- email.PRG / act_mail.prg: CYBER purga y agrega
        EXEC ops.sp_generar_salidas    @id_corrida, 'ASIG';            -- SCBSDOS, SCBTEL, sub_mst, sub_mail, gescar NVA y REA

        SET @msg = CONCAT(N'Archivos: ', @recibidos,
                          N' · devoluciones: ', (SELECT COUNT(*) FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id_corrida),
                          CASE WHEN @aplicar_retiro = 0 THEN N' (pendientes de aplicar con ops.sp_retiro)' ELSE N'' END);
        EXEC ops.sp_corrida_finalizar @id_corrida, 'OK', @msg;
        /* Fin de asignación: se manda después de arribar a CYBER con EXEC ops.sp_avisar @id_corrida, 'CONFIRMACION_ASIG_486'
           Si hubo devolución: EXEC ops.sp_exportar_salidas @id_corrida, @zip = 'RETIROS', @enviar_zip = 1 (correo único de devolución) */
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @msg = ERROR_MESSAGE();
        DECLARE @estatus VARCHAR(15) = CASE WHEN ERROR_NUMBER() IN (50040, 50100) THEN 'CANCELADA' ELSE 'ERROR' END;
        EXEC ops.sp_corrida_finalizar @id_corrida, @estatus, @msg;
        EXEC ops.sp_retroceso_automatico @id_corrida;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_actualizacion_486
    @fecha          DATE    = NULL,
    @hora_llegada   TIME(0) = NULL,
    @aplicar_retiro BIT     = 0,
    @id_corrida     INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @recibidos INT, @msg NVARCHAR(4000), @json NVARCHAR(MAX);
    EXEC ops.sp_corrida_iniciar '486', 'ACT', @fecha, @hora_llegada, @id_corrida OUTPUT;

    BEGIN TRY
        EXEC ops.sp_respaldo           @id_corrida;
        EXEC ops.sp_cargar_proceso     @id_corrida, @recibidos OUTPUT;
        EXEC ops.sp_homologar_entradas @id_corrida;
        EXEC ops.sp_validar            @id_corrida, 'POST_CARGA';     -- pagos negativos (se excluyen y se avisa), pagos a T-1 (alerta)
        EXEC ops.sp_act_preparar       @id_corrida;
        EXEC ops.sp_validar            @id_corrida, 'RETIRO';         -- criterios de retiro -> ops.DEVOLUCION
        EXEC ops.sp_act_aplicar        @id_corrida;
        EXEC ops.sp_act_pagos          @id_corrida;
        EXEC ops.sp_homologar          @id_corrida, 'dat.DAT_486';     -- estructura.prg: REE por segmento, tramo y tipo
        IF @aplicar_retiro = 1
            EXEC ops.sp_retiro         @id_corrida;
        EXEC ops.sp_act_script_pvs_ree @id_corrida;                    -- PVS y REE a CYBER por script (ya no se arriba SCBSDOS en la actualización)
        EXEC ops.sp_generar_salidas    @id_corrida, 'ACT';             -- SCBPAG

        SET @msg = CONCAT(N'Archivos: ', @recibidos,
                          N' · devoluciones: ', (SELECT COUNT(*) FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id_corrida),
                          CASE WHEN @aplicar_retiro = 0 THEN N' (pendientes de aplicar con ops.sp_retiro)' ELSE N'' END);
        EXEC ops.sp_corrida_finalizar @id_corrida, 'OK', @msg;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @msg = ERROR_MESSAGE();
        DECLARE @estatus VARCHAR(15) = CASE WHEN ERROR_NUMBER() IN (50040, 50100) THEN 'CANCELADA' ELSE 'ERROR' END;
        EXEC ops.sp_corrida_finalizar @id_corrida, @estatus, @msg;
        EXEC ops.sp_retroceso_automatico @id_corrida;
        THROW;
    END CATCH;
END;
GO

/* =====================================================================
   Flujo diario (lunes a viernes)
   ---------------------------------------------------------------------
   Todos los días hábiles llega la actualización de saldos y pagos; la
   asignación puede o no llegar, y siempre llega después.

   ops.sp_archivos_presentes  cuántos archivos de un proceso ya están en la
                              carpeta del día (Q:\CYBER\C_486\<año>\<mes>\<día>\)
   ops.sp_diario_486          lo llama un job de SQL Agent cada 30 minutos,
                              lunes a viernes:
                              1. si llegaron los archivos de actualización y no
                                 ha corrido hoy -> ops.sp_actualizacion_486
                              2. si la actualización de hoy terminó OK, llegó la
                                 base maestra y no ha corrido -> ops.sp_asignacion_486
                              No repite lo que ya corrió (OK, ERROR o CANCELADA).
                              Si una corrida falla, el DAT regresa solo a como
                              estaba (ops.sp_retroceso_automatico); se corrige la
                              causa y se vuelve a correr a mano.
   ===================================================================== */
CREATE OR ALTER PROCEDURE ops.sp_archivos_presentes
    @cliente VARCHAR(10),
    @proceso VARCHAR(10),
    @fecha   DATE,
    @n       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @n = 0;
    DECLARE @ruta NVARCHAR(400), @patron NVARCHAR(200), @ruta_ant NVARCHAR(400) = N'';
    DECLARE @dir TABLE (subdirectory NVARCHAR(512), depth INT, [file] INT);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT cfg.fn_ruta(RUTA, @fecha),
               REPLACE(REPLACE(REPLACE(PATRON_NOMBRE,
                   N'{AAAAMMDD}',   CONVERT(CHAR(8), @fecha, 112)),
                   N'{DD-MM-AAAA}', REPLACE(CONVERT(CHAR(10), @fecha, 105), '.', '-')),
                   N'{AAAA-MM-DD}', CONVERT(CHAR(10), @fecha, 23))
        FROM cfg.ARCHIVO WHERE CLIENTE = @cliente AND PROCESO = @proceso AND ACTIVO = 1
        ORDER BY 1;
    OPEN cur;
    FETCH NEXT FROM cur INTO @ruta, @patron;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @ruta <> @ruta_ant
        BEGIN
            DELETE FROM @dir;
            INSERT INTO @dir EXEC master.sys.xp_dirtree @ruta, 1, 1;
            SET @ruta_ant = @ruta;
        END;
        IF EXISTS (SELECT 1 FROM @dir WHERE [file] = 1 AND subdirectory LIKE @patron COLLATE Latin1_General_CI_AI)
            SET @n += 1;
        FETCH NEXT FROM cur INTO @ruta, @patron;
    END;
    CLOSE cur; DEALLOCATE cur;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_diario_486
    @fecha  DATE = NULL,
    @forzar BIT  = 0          -- 1 = corre aunque sea fin de semana
AS
BEGIN
    SET NOCOUNT ON;
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));
    DECLARE @n INT, @id INT, @hora TIME(0) = CAST(GETDATE() AS TIME(0));

    IF cfg.fn_es_fin_de_semana(@fecha) = 1 AND @forzar = 0
    BEGIN
        SELECT 'FIN DE SEMANA' AS RESULTADO;
        RETURN;
    END;

    /* 1. Actualización */
    IF NOT EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = '486' AND PROCESO = 'ACT' AND FECHA_PROCESO = @fecha AND ESTATUS <> 'REVERTIDA')
    BEGIN
        EXEC ops.sp_archivos_presentes '486', 'ACT', @fecha, @n OUTPUT;
        IF @n = 0
        BEGIN
            SELECT 'ESPERANDO ACTUALIZACION' AS RESULTADO;
            RETURN;
        END;
        BEGIN TRY
            EXEC ops.sp_actualizacion_486 @fecha = @fecha, @hora_llegada = @hora, @id_corrida = @id OUTPUT;
        END TRY
        BEGIN CATCH
            SELECT 'ACTUALIZACION CON ERROR' AS RESULTADO, ERROR_MESSAGE() AS DETALLE;   -- el detalle queda en ops.CORRIDA y ops.BITACORA; el DAT ya se revirtió solo
            RETURN;
        END CATCH;
    END;

    IF NOT EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = '486' AND PROCESO = 'ACT' AND FECHA_PROCESO = @fecha AND ESTATUS = 'OK')
    BEGIN
        SELECT 'ACTUALIZACION DEL DIA SIN TERMINAR OK' AS RESULTADO;
        RETURN;
    END;

    /* 2. Asignación (puede no llegar) */
    IF EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = '486' AND PROCESO = 'ASIG' AND FECHA_PROCESO = @fecha AND ESTATUS <> 'REVERTIDA')
    BEGIN
        SELECT 'DIA COMPLETO' AS RESULTADO;
        /* 3. Arribo automático de correos y teléfonos en cuanto el operador sube SCBSDOS y SCBTEL (decisión 02/11) */
        BEGIN TRY
            EXEC ops.sp_arribo_automatico @fecha = @fecha;
        END TRY
        BEGIN CATCH
            SELECT 'ARRIBO AUTOMATICO CON ERROR' AS ARRIBO, ERROR_MESSAGE() AS DETALLE;
        END CATCH;
        RETURN;
    END;
    EXEC ops.sp_archivos_presentes '486', 'ASIG', @fecha, @n OUTPUT;
    IF @n = 0
    BEGIN
        SELECT 'ACTUALIZACION OK · SIN ASIGNACION (POR AHORA)' AS RESULTADO;
        RETURN;
    END;
    BEGIN TRY
        EXEC ops.sp_asignacion_486 @fecha = @fecha, @hora_llegada = @hora, @id_corrida = @id OUTPUT;
        SELECT 'ACTUALIZACION Y ASIGNACION OK' AS RESULTADO;
    END TRY
    BEGIN CATCH
        SELECT 'ASIGNACION CON ERROR' AS RESULTADO, ERROR_MESSAGE() AS DETALLE;
    END CATCH;
END;
GO
