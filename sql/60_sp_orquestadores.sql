/* =====================================================================
   Banbaj · 60 Orquestadores (un SP por proceso)
   ---------------------------------------------------------------------
   ops.sp_asignacion_486      reemplaza paso.prg (+ asig_bases, asi486)
   ops.sp_actualizacion_486   reemplaza saldos.prg

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
    EXEC ops.sp_corrida_iniciar '486', 'ASIG', @fecha, @hora_llegada, @id_corrida OUTPUT;

    BEGIN TRY
        EXEC ops.sp_respaldo           @id_corrida;
        EXEC ops.sp_cargar_proceso     @id_corrida, @recibidos OUTPUT;
        EXEC ops.sp_homologar_entradas @id_corrida;
        EXEC ops.sp_validar            @id_corrida, 'POST_CARGA';
        EXEC ops.sp_asig_unir_layout   @id_corrida;
        EXEC ops.sp_homologar          @id_corrida, 'stg.LAYOUT_486';
        EXEC ops.sp_asig_devolucion    @id_corrida, @forzar_devolucion;
        EXEC ops.sp_asig_existentes    @id_corrida;
        EXEC ops.sp_validar            @id_corrida, 'PRE_ALTA';
        EXEC ops.sp_asig_alta          @id_corrida;
        IF @aplicar_retiro = 1
            EXEC ops.sp_retiro         @id_corrida;
        EXEC ops.sp_generar_salida     @id_corrida, 'SCBSDOS';

        SET @msg = CONCAT(N'Archivos: ', @recibidos,
                          N' · devoluciones: ', (SELECT COUNT(*) FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id_corrida),
                          CASE WHEN @aplicar_retiro = 0 THEN N' (pendientes de aplicar con ops.sp_retiro)' ELSE N'' END);
        EXEC ops.sp_corrida_finalizar @id_corrida, 'OK', @msg;

        SET @json = (SELECT @id_corrida AS CORRIDA, @msg AS RESUMEN FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC mail.sp_enviar @plantilla = 'CONFIRMACION_ASIG_486', @id_corrida = @id_corrida, @valores = @json;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @msg = ERROR_MESSAGE();
        DECLARE @estatus VARCHAR(15) = CASE WHEN ERROR_NUMBER() IN (50040, 50100) THEN 'CANCELADA' ELSE 'ERROR' END;
        EXEC ops.sp_corrida_finalizar @id_corrida, @estatus, @msg;
        SET @json = (SELECT @id_corrida AS CORRIDA, N'Asignación 486' AS PROCESO, @msg AS ERROR FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC mail.sp_enviar @plantilla = 'ERROR_PROCESO_486', @id_corrida = @id_corrida, @valores = @json;
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
        EXEC ops.sp_validar            @id_corrida, 'POST_CARGA';     -- pagos negativos (cancela), pagos a T-1 (alerta)
        EXEC ops.sp_act_preparar       @id_corrida;
        EXEC ops.sp_validar            @id_corrida, 'RETIRO';         -- criterios de retiro -> ops.DEVOLUCION
        EXEC ops.sp_act_aplicar        @id_corrida;
        EXEC ops.sp_act_pagos          @id_corrida;
        IF @aplicar_retiro = 1
            EXEC ops.sp_retiro         @id_corrida;
        EXEC ops.sp_generar_salida     @id_corrida, 'SCBSDOS';

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
        SET @json = (SELECT @id_corrida AS CORRIDA, N'Actualización 486' AS PROCESO, @msg AS ERROR FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC mail.sp_enviar @plantilla = 'ERROR_PROCESO_486', @id_corrida = @id_corrida, @valores = @json;
        THROW;
    END CATCH;
END;
GO
