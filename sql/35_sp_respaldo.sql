/* =====================================================================
   Banbaj · 35 Respaldo y retroceso por corrida
   ---------------------------------------------------------------------
   ops.sp_respaldo          copia el DAT y el consecutivo al iniciar cada corrida
                            (equivale a RESPALDO2.prg)
   ops.sp_revertir_corrida  deja el DAT, el histórico de folios, el consecutivo y
                            los pagos como estaban antes de una corrida

   El retroceso va en orden: solo se puede revertir la corrida más reciente
   que no esté revertida. Para regresar dos corridas, se revierte la última
   y luego la anterior.
   NO revierte lo que ya se arribó a CYBER: si los scripts o archivos ya se
   subieron, hay que corregir CYBER por separado.
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_respaldo
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @conservar INT = ISNULL(TRY_CONVERT(INT, cfg.fn_param(@cliente, 'RESPALDOS_A_CONSERVAR')), 15), @n INT;

    BEGIN TRANSACTION;
    DELETE FROM ops.RESPALDO_DAT_486 WHERE ID_CORRIDA_RESPALDO = @id_corrida;
    INSERT INTO ops.RESPALDO_DAT_486 SELECT @id_corrida, * FROM dat.DAT_486;
    SET @n = @@ROWCOUNT;

    DELETE FROM ops.RESPALDO_CONTROL WHERE ID_CORRIDA = @id_corrida;
    INSERT INTO ops.RESPALDO_CONTROL (ID_CORRIDA, CLIENTE, ULTIMO_FOLIO, REGISTROS)
    SELECT @id_corrida, @cliente, (SELECT ULTIMO_FOLIO FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = @cliente), @n;

    /* Se conservan solo los últimos N respaldos */
    DELETE r FROM ops.RESPALDO_DAT_486 r
    WHERE r.ID_CORRIDA_RESPALDO NOT IN (SELECT TOP (@conservar) ID_CORRIDA FROM ops.RESPALDO_CONTROL
                                        WHERE CLIENTE = @cliente ORDER BY ID_CORRIDA DESC);
    DELETE c FROM ops.RESPALDO_CONTROL c
    WHERE c.CLIENTE = @cliente
      AND c.ID_CORRIDA NOT IN (SELECT TOP (@conservar) ID_CORRIDA FROM ops.RESPALDO_CONTROL
                               WHERE CLIENTE = @cliente ORDER BY ID_CORRIDA DESC);
    COMMIT TRANSACTION;

    EXEC ops.sp_log @id_corrida, 'RESPALDO', 'OK', @n;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_revertir_corrida
    @id_corrida INT,
    @confirmar  BIT = 0          -- 0 = solo muestra qué cambiaría; 1 = revierte
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @cliente VARCHAR(10), @estatus VARCHAR(15), @folio INT, @msg NVARCHAR(4000), @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);
    SELECT @cliente = CLIENTE, @estatus = ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;

    IF @cliente IS NULL THROW 50300, 'La corrida no existe.', 1;
    IF @estatus = 'REVERTIDA' THROW 50301, 'La corrida ya fue revertida.', 1;
    IF @estatus = 'EN_PROCESO' THROW 50302, 'La corrida sigue en proceso; ciérrala antes de revertirla.', 1;
    IF NOT EXISTS (SELECT 1 FROM ops.RESPALDO_CONTROL WHERE ID_CORRIDA = @id_corrida)
        THROW 50303, 'No hay respaldo de esa corrida (se conservan solo los últimos RESPALDOS_A_CONSERVAR).', 1;
    IF EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = @cliente AND ID_CORRIDA > @id_corrida AND ESTATUS <> 'REVERTIDA')
        THROW 50304, 'Hay corridas posteriores sin revertir: revierte primero la más reciente.', 1;

    SELECT @folio = ULTIMO_FOLIO FROM ops.RESPALDO_CONTROL WHERE ID_CORRIDA = @id_corrida;

    /* Vista previa */
    SELECT 'DAT actual' AS CONCEPTO, COUNT(*) AS REGISTROS FROM dat.DAT_486
    UNION ALL SELECT 'DAT en el respaldo', COUNT(*) FROM ops.RESPALDO_DAT_486 WHERE ID_CORRIDA_RESPALDO = @id_corrida
    UNION ALL SELECT 'Altas en el histórico a borrar', COUNT(*) FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_ALTA = @id_corrida
    UNION ALL SELECT 'Bajas en el histórico a reabrir', COUNT(*) FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_BAJA = @id_corrida
    UNION ALL SELECT 'Pagos arribados a borrar', COUNT(*) FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id_corrida AND ORIGEN = 'CORRIDA'
    UNION ALL SELECT CONCAT('Consecutivo de folios: actual ', (SELECT ULTIMO_FOLIO FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = @cliente),
                            ' -> ', @folio), NULL;

    IF @confirmar = 0
    BEGIN
        PRINT 'Vista previa: no se cambió nada. Ejecuta con @confirmar = 1 para revertir.';
        RETURN;
    END;

    SELECT @cols = STRING_AGG(CAST(QUOTENAME(name) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY column_id)
    FROM sys.columns WHERE object_id = OBJECT_ID('dat.DAT_486');

    BEGIN TRANSACTION;

    DELETE FROM dat.DAT_486;
    SET @sql = N'INSERT INTO dat.DAT_486 (' + @cols + N') SELECT ' + @cols
             + N' FROM ops.RESPALDO_DAT_486 WHERE ID_CORRIDA_RESPALDO = @id_corrida;';
    EXEC sp_executesql @sql, N'@id_corrida INT', @id_corrida = @id_corrida;

    DELETE FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_ALTA = @id_corrida;
    /* Bajas de cuentas que no tenían alta en el histórico (ID_CORRIDA_ALTA = 0): se borran */
    DELETE FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_BAJA = @id_corrida AND ID_CORRIDA_ALTA = 0;
    UPDATE dat.HISTORIA_FOLIO
    SET ESTATUS = 'A', FE_BAJA = NULL, MOTIVO_BAJA = NULL, ID_CORRIDA_BAJA = NULL, DATOS_BAJA = NULL
    WHERE ID_CORRIDA_BAJA = @id_corrida;

    IF @folio IS NOT NULL
        UPDATE dat.FOLIO_CONSECUTIVO SET ULTIMO_FOLIO = @folio, FE_ACT = SYSDATETIME() WHERE CLIENTE = @cliente;

    DELETE FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id_corrida AND ORIGEN = 'CORRIDA';
    DELETE FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida;
    UPDATE ops.DEVOLUCION SET PROCESADA = 0 WHERE ID_CORRIDA = @id_corrida;

    SET @msg = CONCAT(N'Revertida (estatus previo ', @estatus, N'). Lo que ya se haya arribado a CYBER no se revierte.');
    UPDATE ops.CORRIDA SET ESTATUS = 'REVERTIDA', MENSAJE = @msg WHERE ID_CORRIDA = @id_corrida;

    COMMIT TRANSACTION;
    EXEC ops.sp_log @id_corrida, 'RETROCESO', 'OK', NULL, @msg;
END;
GO
