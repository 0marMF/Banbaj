/* =====================================================================
   Banbaj · 72 Seguimiento del arribo a CYBER
   ---------------------------------------------------------------------
   ops.sp_marcar_arribo    horas de solicitud, autorización y fin del arribo
                           (hoy en bitac/bitact con MESSAGEBOX)
   ops.v_TIEMPOS_CORRIDA   llegada, proceso y arribo de cada corrida
   ops.sp_cuadrar_pagos    BAJ.sql + cuadre de saldos.prg: lo que CYBER registró
                           hoy contra lo que se arribó en SCBPAG (NO_SUBIERON486)
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_marcar_arribo
    @id_corrida INT,
    @evento     VARCHAR(20),               -- SOLICITUD / AUTORIZACION / FIN
    @fecha_hora DATETIME2(0) = NULL,       -- NULL = ahora (sirve para capturar una hora pasada)
    @nota       NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @evento = UPPER(LTRIM(RTRIM(@evento)));
    IF @evento NOT IN ('SOLICITUD', 'AUTORIZACION', 'FIN') THROW 50700, '@evento debe ser SOLICITUD, AUTORIZACION o FIN.', 1;
    IF NOT EXISTS (SELECT 1 FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida) THROW 50701, 'La corrida no existe.', 1;
    DECLARE @paso VARCHAR(80) = 'ARRIBO ' + @evento;
    DELETE FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = @paso;      -- la última marca es la que vale
    INSERT INTO ops.BITACORA (ID_CORRIDA, FECHA, PASO, ESTATUS, MENSAJE)
    VALUES (@id_corrida, ISNULL(@fecha_hora, SYSDATETIME()), @paso, 'OK', @nota);
END;
GO

CREATE OR ALTER VIEW ops.v_TIEMPOS_CORRIDA
AS
SELECT c.ID_CORRIDA, c.CLIENTE, c.PROCESO, c.FECHA_PROCESO, c.HORA_LLEGADA, c.INICIO, c.FIN, c.ESTATUS, c.USUARIO,
       s.FECHA AS SOLICITUD_ARRIBO, a.FECHA AS AUTORIZACION_ARRIBO, f.FECHA AS FIN_ARRIBO,
       DATEDIFF(MINUTE, c.INICIO, c.FIN) AS MIN_PROCESO,
       DATEDIFF(MINUTE, s.FECHA, a.FECHA) AS MIN_ESPERA_AUTORIZACION,
       DATEDIFF(MINUTE, a.FECHA, f.FECHA) AS MIN_ARRIBO
FROM ops.CORRIDA c
OUTER APPLY (SELECT MAX(FECHA) AS FECHA FROM ops.BITACORA WHERE ID_CORRIDA = c.ID_CORRIDA AND PASO = 'ARRIBO SOLICITUD') s
OUTER APPLY (SELECT MAX(FECHA) AS FECHA FROM ops.BITACORA WHERE ID_CORRIDA = c.ID_CORRIDA AND PASO = 'ARRIBO AUTORIZACION') a
OUTER APPLY (SELECT MAX(FECHA) AS FECHA FROM ops.BITACORA WHERE ID_CORRIDA = c.ID_CORRIDA AND PASO = 'ARRIBO FIN') f;
GO

/* ---------------------------------------------------------------------
   Cuadre de pagos (saldos.prg después de PAGOS): se compara lo arribado en
   SCBPAG de la corrida (dat.PAGO_ARRIBADO) contra lo que CYBER registró hoy
   (stg.CYBER_PAGO, lo llena ops.sp_bajar_cyber 'PAGOS'). Se empareja por
   CUENTA2 + importe; lo que no aparece en CYBER es lo que "no subió".
   Lo corre solo ops.sp_cuadre_automatico (sql/78): si a la hora límite faltan pagos, avisa
   al equipo de asignaciones (HALLAZGO_486). Los pagos que no subieron quedan en ops.RECHAZO
   (CUADRE_PAGOS) y en el resultado.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_cuadrar_pagos
    @id_corrida INT,
    @silencioso BIT = 0          -- 1 = no regresa resultados (lo llama ops.sp_cuadre_automatico)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @proceso VARCHAR(10), @cliente VARCHAR(10), @msg NVARCHAR(4000);
    SELECT @proceso = PROCESO, @cliente = CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ACT' THROW 50710, 'Indica una corrida de actualización.', 1;

    SELECT LTRIM(RTRIM(CUENTA)) AS CUENTA2, cfg.fn_importe(MONTO) AS IMPORTE
    INTO #c FROM stg.CYBER_PAGO WHERE NULLIF(LTRIM(RTRIM(CUENTA)), N'') IS NOT NULL;

    ;WITH arr AS (SELECT CUENTA2, IMPORTE, ROW_NUMBER() OVER (PARTITION BY CUENTA2, IMPORTE ORDER BY ID) AS RN
                  FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id_corrida AND ORIGEN = 'CORRIDA'),
          cyb AS (SELECT CUENTA2, IMPORTE, ROW_NUMBER() OVER (PARTITION BY CUENTA2, IMPORTE ORDER BY (SELECT NULL)) AS RN FROM #c)
    SELECT a.CUENTA2, a.IMPORTE INTO #no
    FROM arr a
    WHERE NOT EXISTS (SELECT 1 FROM cyb c WHERE c.CUENTA2 = a.CUENTA2 AND c.IMPORTE = a.IMPORTE AND c.RN = a.RN);

    DECLARE @arribados INT = (SELECT COUNT(*) FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id_corrida AND ORIGEN = 'CORRIDA'),
            @en_cyber INT = (SELECT COUNT(*) FROM #c),
            @no_subieron INT = (SELECT COUNT(*) FROM #no);
    TRUNCATE TABLE stg.CYBER_PAGO;

    DELETE FROM ops.RECHAZO WHERE ID_CORRIDA = @id_corrida AND ORIGEN = 'CUADRE_PAGOS';
    INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, MOTIVO, DATOS)
    SELECT @id_corrida, 'CUADRE_PAGOS', N'Pago arribado que no aparece en CYBER', (SELECT n.CUENTA2, n.IMPORTE FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM #no n;

    SET @msg = CONCAT(N'Arribados: ', @arribados, N' · en CYBER hoy: ', @en_cyber, N' · no subieron: ', @no_subieron);
    DECLARE @est VARCHAR(15) = CASE WHEN @no_subieron = 0 THEN 'OK' ELSE 'AVISO' END;
    EXEC ops.sp_log @id_corrida, 'CUADRE PAGOS', @est, @no_subieron, @msg;


    IF @silencioso = 1 RETURN;
    SELECT @arribados AS ARRIBADOS, @en_cyber AS EN_CYBER, @no_subieron AS NO_SUBIERON;
    SELECT CUENTA2, IMPORTE FROM #no ORDER BY CUENTA2;
END;
GO
