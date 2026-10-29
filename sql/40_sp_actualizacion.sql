/* =====================================================================
   Banbaj · 40 Actualización 486 (saldos y pagos)
   ---------------------------------------------------------------------
   ops.sp_act_preparar   une los archivos de saldos y los cruza contra el DAT
   ops.sp_act_aplicar    actualiza el DAT y genera los scripts para CYBER
   ops.sp_act_pagos      pagos a arribar (sin repetir CUENTA + FE_PAG + IMPORTE ya arribados)
   Equivale a saldos.prg (+ la parte de pagos documentada).
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_act_preparar
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @src SYSNAME, @codigo VARCHAR(50), @seg VARCHAR(20), @llave SYSNAME, @sql NVARCHAR(MAX),
            @sel NVARCHAR(MAX), @n INT, @total INT = 0, @sin_dat INT = 0;

    DROP TABLE IF EXISTS stg.SALDOS_486;
    CREATE TABLE stg.SALDOS_486 (
        ID          INT IDENTITY(1,1) NOT NULL,
        ID_CORRIDA  INT           NOT NULL,
        ORIGEN      VARCHAR(50)   NOT NULL,
        SEGMENTO2   VARCHAR(20)   NOT NULL,
        LLAVE       VARCHAR(60)   NULL,
        CUENTA      VARCHAR(20)   NULL,
        CUENTA2     VARCHAR(28)   NULL,
        SDO_ACT     DECIMAL(18,2) NULL,
        SDO_VDO     DECIMAL(18,2) NULL,
        PAG_MIN     DECIMAL(18,2) NULL,
        PVS         VARCHAR(4)    NULL,
        SEG         VARCHAR(15)   NULL,
        FECHA       DATE          NULL,
        ANT_SDO_ACT DECIMAL(18,2) NULL,
        ANT_SEG     VARCHAR(15)   NULL
    );

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT a.TABLA_DESTINO, a.CODIGO, a.SEGMENTO2, a.LLAVE_DAT
        FROM cfg.ARCHIVO a
        JOIN ops.ARCHIVO_CARGADO c ON c.ID_ARCHIVO = a.ID_ARCHIVO AND c.ID_CORRIDA = @id_corrida AND c.ESTATUS = 'CARGADO'
        WHERE a.PROCESO = 'ACT' AND a.SEGMENTO2 IS NOT NULL AND a.LLAVE_DAT IS NOT NULL
        ORDER BY a.ORDEN;
    OPEN cur;
    FETCH NEXT FROM cur INTO @src, @codigo, @seg, @llave;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        /* Columnas que el archivo no trae quedan NULL (ej. TDC no trae SDO_VDO, A-03) */
        SET @sel = N'SELECT ID_CORRIDA, @codigo, @seg, CAST(s.' + QUOTENAME(@llave) + N' AS VARCHAR(60))'
                 + N', ' + CASE WHEN COL_LENGTH(@src, 'SDO_ACT') IS NOT NULL THEN N's.SDO_ACT' ELSE N'NULL' END
                 + N', ' + CASE WHEN COL_LENGTH(@src, 'SDO_VDO') IS NOT NULL THEN N's.SDO_VDO' ELSE N'NULL' END
                 + N', ' + CASE WHEN COL_LENGTH(@src, 'PAG_MIN') IS NOT NULL THEN N's.PAG_MIN' ELSE N'NULL' END
                 + N', ' + CASE WHEN COL_LENGTH(@src, 'PVS')     IS NOT NULL THEN N's.PVS'     ELSE N'NULL' END
                 + N', ' + CASE WHEN COL_LENGTH(@src, 'SEG')     IS NOT NULL THEN N's.SEG'     ELSE N'NULL' END
                 + N', ' + CASE WHEN COL_LENGTH(@src, 'FECHA')   IS NOT NULL THEN N's.FECHA'   ELSE N'NULL' END;
        SET @sql = N'INSERT INTO stg.SALDOS_486 (ID_CORRIDA, ORIGEN, SEGMENTO2, LLAVE, SDO_ACT, SDO_VDO, PAG_MIN, PVS, SEG, FECHA) '
                 + @sel + N' FROM ' + QUOTENAME(PARSENAME(@src, 2)) + N'.' + QUOTENAME(PARSENAME(@src, 1))
                 + N' s WHERE s.ID_CORRIDA = @id_corrida; SET @n = @@ROWCOUNT;';
        EXEC sp_executesql @sql, N'@id_corrida INT, @codigo VARCHAR(50), @seg VARCHAR(20), @n INT OUTPUT',
             @id_corrida = @id_corrida, @codigo = @codigo, @seg = @seg, @n = @n OUTPUT;
        SET @total += @n;

        /* Cruce contra el DAT por la llave del archivo, dentro del mismo segmento */
        SET @sql = N'UPDATE x SET CUENTA = d.CUENTA, CUENTA2 = d.CUENTA2, ANT_SDO_ACT = d.SDO_ACT, ANT_SEG = d.SEG '
                 + N'FROM stg.SALDOS_486 x JOIN dat.DAT_486 d ON CAST(d.' + QUOTENAME(@llave) + N' AS VARCHAR(60)) = x.LLAVE '
                 + N'AND d.SEGMENTO2 = x.SEGMENTO2 WHERE x.ORIGEN = @codigo;';
        EXEC sp_executesql @sql, N'@codigo VARCHAR(50)', @codigo = @codigo;

        FETCH NEXT FROM cur INTO @src, @codigo, @seg, @llave;
    END;
    CLOSE cur; DEALLOCATE cur;

    /* Lo que no está en el DAT no se actualiza (regla 1 del documento) */
    INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, MOTIVO, DATOS)
    SELECT @id_corrida, x.ORIGEN, N'No existe en el DAT', (SELECT x.LLAVE, x.SEGMENTO2, x.SDO_ACT FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM stg.SALDOS_486 x WHERE x.CUENTA IS NULL;
    DELETE FROM stg.SALDOS_486 WHERE CUENTA IS NULL;
    SET @sin_dat = @@ROWCOUNT;

    /* Una sola fila por cuenta */
    ;WITH d AS (SELECT ID, ORIGEN, CUENTA, ROW_NUMBER() OVER (PARTITION BY CUENTA ORDER BY ID) AS RN FROM stg.SALDOS_486)
    INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, MOTIVO, DATOS)
    SELECT @id_corrida, ORIGEN, N'Cuenta repetida en saldos', (SELECT d.CUENTA FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM d WHERE RN > 1;
    ;WITH d AS (SELECT ID, ROW_NUMBER() OVER (PARTITION BY CUENTA ORDER BY ID) AS RN FROM stg.SALDOS_486)
    DELETE FROM d WHERE RN > 1;

    SET @sql = CONCAT(N'Recibidos: ', @total, N' · no están en DAT: ', @sin_dat);
    SET @n = @total - @sin_dat;
    EXEC ops.sp_log @id_corrida, 'ACT PREPARAR', 'OK', @n, @sql;
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_act_aplicar
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @modo VARCHAR(12) = ISNULL(cfg.fn_param(@cliente, 'NEGATIVO_MODO'), 'ABS_LEGADO'), @n INT;

    BEGIN TRANSACTION;

    /* DAT: SDO_ACT y SEG siempre; PVS solo fuera de TDC; PAG_MIN y SDO_VDO solo si el archivo los trae */
    UPDATE d
    SET d.SDO_ACT = ISNULL(x.SDO_ACT, d.SDO_ACT),
        d.SEG     = ISNULL(x.SEG, ''),
        d.PVS     = CASE WHEN x.SEGMENTO2 <> 'TDC' THEN ISNULL(x.PVS, '0') ELSE d.PVS END,
        d.PAG_MIN = ISNULL(x.PAG_MIN, d.PAG_MIN),
        d.SDO_VDO = ISNULL(x.SDO_VDO, d.SDO_VDO),
        d.ID_CORRIDA_ULT = @id_corrida,
        d.FE_ULT_ACT = SYSDATETIME()
    FROM dat.DAT_486 d
    JOIN stg.SALDOS_486 x ON x.CUENTA = d.CUENTA AND x.ID_CORRIDA = @id_corrida;
    SET @n = @@ROWCOUNT;

    /* Scripts para CYBER (antes act486.sql, min486.sql, pvs486.sql); cada uno con su commit (A-04) */
    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT IN ('ACT_SALDOS', 'ACT_VENCIDO', 'ACT_PAGMIN');

    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    SELECT @id_corrida, 'ACT_SALDOS', ROW_NUMBER() OVER (ORDER BY CUENTA2),
           CONCAT(N'update RCVRY.delqmst set DMCURBAL=''', cfg.fn_pad_importe(SDO_ACT, 15, @modo),
                  N''' ,dmbphone=''', REPLACE(ISNULL(SEG, ''), '''', ''''''),
                  N''' Where dmacctg=''1'' And dmacct=''', CUENTA2, N''';')
    FROM stg.SALDOS_486 WHERE ID_CORRIDA = @id_corrida AND SDO_ACT IS NOT NULL;

    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    SELECT @id_corrida, 'ACT_VENCIDO', ROW_NUMBER() OVER (ORDER BY CUENTA2),
           CONCAT(N'update RCVRY.delqmst set dmamtdlq=''', cfg.fn_pad_importe(SDO_VDO, 15, @modo),
                  N''' Where dmacctg=''1'' And dmacct=''', CUENTA2, N''';')
    FROM stg.SALDOS_486 WHERE ID_CORRIDA = @id_corrida AND SDO_VDO IS NOT NULL;

    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    SELECT @id_corrida, 'ACT_PAGMIN', ROW_NUMBER() OVER (ORDER BY CUENTA2),
           CONCAT(N'update RCVRY.uda1 set u1pagmin=''', cfg.fn_pad_importe(PAG_MIN, 15, @modo),
                  N''' Where u1acct=''', CUENTA2, N''';')
    FROM stg.SALDOS_486 WHERE ID_CORRIDA = @id_corrida AND PAG_MIN IS NOT NULL;

    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    SELECT @id_corrida, s.SCRIPT, ISNULL(MAX(c.NUM), 0) + v.k, v.txt
    FROM (VALUES ('ACT_SALDOS'), ('ACT_VENCIDO'), ('ACT_PAGMIN')) s(SCRIPT)
    CROSS JOIN (VALUES (1, N'commit;'), (2, N'exit;')) v(k, txt)
    LEFT JOIN ops.CYBER_SCRIPT c ON c.ID_CORRIDA = @id_corrida AND c.SCRIPT = s.SCRIPT
    GROUP BY s.SCRIPT, v.k, v.txt;

    COMMIT TRANSACTION;

    DECLARE @msg NVARCHAR(400) = CONCAT(N'Cuentas con saldo cambiado: ',
                (SELECT COUNT(*) FROM stg.SALDOS_486 WHERE ID_CORRIDA = @id_corrida AND ISNULL(SDO_ACT, -1) <> ISNULL(ANT_SDO_ACT, -1)));
    EXEC ops.sp_log @id_corrida, 'ACT APLICAR', 'OK', @n, @msg;
END;
GO

/* ---------------------------------------------------------------------
   Pagos (pagos.prg): el CREDITO del archivo se cruza contra DAT.RIESGO
   (y DAT.CUENTA) para obtener CUENTA y CUENTA2. Se arriba lo que no esté
   ya en dat.PAGO_ARRIBADO con la misma CUENTA + FE_PAG + IMPORTE (antes
   PAGTOT). Dos pagos iguales en el mismo archivo se arriban los dos, como hoy.
   Los pagos negativos ya no llegan aquí: la regla PAGOS_NEGATIVOS los
   excluye y avisa a Operación. El archivo plano es SCBPAG (cfg.SALIDA).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_act_pagos
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    DECLARE @recibidos INT, @sin_dat INT, @ya INT, @nuevos INT;

    IF OBJECT_ID('stg.ENT_PAGOS') IS NULL
       OR NOT EXISTS (SELECT 1 FROM stg.ENT_PAGOS WHERE ID_CORRIDA = @id_corrida)
    BEGIN
        EXEC ops.sp_log @id_corrida, 'ACT PAGOS', 'AVISO', 0, N'No se recibió archivo de pagos (o todos se excluyeron).';
        RETURN;
    END;

    SELECT p.FILA, p.RIESGO, p.IMPORTE, p.FECHA, x.CUENTA, x.CUENTA2
    INTO #p
    FROM stg.ENT_PAGOS p
    OUTER APPLY (SELECT TOP (1) d.CUENTA, d.CUENTA2 FROM dat.DAT_486 d
                 WHERE d.CLIENTE = @cliente AND (d.RIESGO = p.RIESGO OR d.CUENTA = p.RIESGO)
                 ORDER BY CASE WHEN d.RIESGO = p.RIESGO THEN 0 ELSE 1 END, d.CUENTA2) x
    WHERE p.ID_CORRIDA = @id_corrida AND p.IMPORTE >= 0;
    SET @recibidos = @@ROWCOUNT;

    INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, FILA, MOTIVO, DATOS)
    SELECT @id_corrida, 'PAGOS', FILA, N'Crédito de pago que no existe en el DAT',
           (SELECT p.RIESGO, p.IMPORTE, p.FECHA FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM #p p WHERE p.CUENTA IS NULL;
    SET @sin_dat = @@ROWCOUNT;

    SELECT @ya = COUNT(*) FROM #p p
    WHERE p.CUENTA IS NOT NULL
      AND EXISTS (SELECT 1 FROM dat.PAGO_ARRIBADO a
                  WHERE a.CLIENTE = @cliente AND a.CUENTA = p.CUENTA AND a.FE_PAG = p.FECHA AND a.IMPORTE = p.IMPORTE);

    INSERT INTO dat.PAGO_ARRIBADO (CLIENTE, CUENTA, CUENTA2, FE_PAG, IMPORTE, FE_REG, ID_CORRIDA, ORIGEN)
    SELECT @cliente, p.CUENTA, p.CUENTA2, p.FECHA, p.IMPORTE, @fecha, @id_corrida, 'CORRIDA'
    FROM #p p
    WHERE p.CUENTA IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dat.PAGO_ARRIBADO a
                      WHERE a.CLIENTE = @cliente AND a.CUENTA = p.CUENTA AND a.FE_PAG = p.FECHA AND a.IMPORTE = p.IMPORTE);
    SET @nuevos = @@ROWCOUNT;

    DECLARE @msg NVARCHAR(400) = CONCAT(N'Recibidos: ', @recibidos, N' · sin cuenta en DAT: ', @sin_dat,
                N' · ya arribados antes: ', @ya, N' · a arribar (SCBPAG): ', @nuevos);
    EXEC ops.sp_log @id_corrida, 'ACT PAGOS', 'OK', @nuevos, @msg;
END;
GO
