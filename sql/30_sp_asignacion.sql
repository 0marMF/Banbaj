USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 30 Asignación 486
   ---------------------------------------------------------------------
   ops.sp_asig_unir_layout    une las bases maestras recibidas en stg.LAYOUT_486 (riesgo repetido entre segmentos: detiene)
   ops.sp_asig_avisos_llave   avisos: mismo riesgo con otro RFC, cambio de segmento (20/11)
   ops.sp_asig_devolucion     cuentas del DAT que no vinieron en la base de su segmento
   ops.sp_asig_existentes     actualiza en DAT las cuentas que ya existen
   ops.sp_asig_alta           REA / NVA, folios y alta en DAT + histórico
   ops.sp_retiro              retira del DAT las cuentas de ops.DEVOLUCION (asig y act)
   Equivale a paso.prg + asig_bases.prg + prog15.prg.
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_asig_unir_layout
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX), @src SYSNAME, @codigo VARCHAR(50), @cols NVARCHAR(MAX), @sel NVARCHAR(MAX), @n INT, @total INT = 0;

    /* El layout tiene la misma estructura que el DAT + columnas de control */
    DROP TABLE IF EXISTS stg.LAYOUT_486;
    SELECT TOP (0) * INTO stg.LAYOUT_486 FROM dat.DAT_486;
    ALTER TABLE stg.LAYOUT_486 ADD ID_CORRIDA INT NULL, ORIGEN VARCHAR(50) NULL,
                                   ES_EXISTENTE BIT NOT NULL CONSTRAINT DF_LAYOUT_486_EXI DEFAULT 0;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT a.TABLA_DESTINO, a.CODIGO
        FROM cfg.ARCHIVO a
        JOIN ops.ARCHIVO_CARGADO c ON c.ID_ARCHIVO = a.ID_ARCHIVO AND c.ID_CORRIDA = @id_corrida AND c.ESTATUS = 'CARGADO'
        WHERE a.PROCESO = 'ASIG' AND a.SEGMENTO2 IS NOT NULL
        ORDER BY a.ORDEN;
    OPEN cur;
    FETCH NEXT FROM cur INTO @src, @codigo;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        /* Solo las columnas que existen en la base Y en el DAT. Se convierten al
           tipo del DAT con CAST: un texto más largo se recorta en lugar de fallar. */
        SELECT @cols = STRING_AGG(CAST(QUOTENAME(l.name) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY l.column_id),
               @sel  = STRING_AGG(CAST(N'CAST(' + QUOTENAME(l.name) + N' AS '
                         + CASE WHEN ty.name IN ('varchar', 'char', 'varbinary')
                                    THEN ty.name + N'(' + CASE WHEN l.max_length = -1 THEN N'MAX' ELSE CAST(l.max_length AS NVARCHAR(10)) END + N')'
                                WHEN ty.name IN ('nvarchar', 'nchar')
                                    THEN ty.name + N'(' + CASE WHEN l.max_length = -1 THEN N'MAX' ELSE CAST(l.max_length / 2 AS NVARCHAR(10)) END + N')'
                                WHEN ty.name IN ('decimal', 'numeric')
                                    THEN ty.name + N'(' + CAST(l.precision AS NVARCHAR(5)) + N',' + CAST(l.scale AS NVARCHAR(5)) + N')'
                                WHEN ty.name IN ('datetime2', 'time')
                                    THEN ty.name + N'(' + CAST(l.scale AS NVARCHAR(5)) + N')'
                                ELSE ty.name END
                         + N')' AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY l.column_id)
        FROM sys.columns l
        JOIN sys.types ty ON ty.user_type_id = l.user_type_id
        JOIN sys.columns s ON s.name = l.name AND s.object_id = OBJECT_ID(@src)
        WHERE l.object_id = OBJECT_ID('stg.LAYOUT_486')
          AND l.name NOT IN ('ID_CORRIDA', 'ORIGEN', 'ES_EXISTENTE');

        SET @sql = N'INSERT INTO stg.LAYOUT_486 (ID_CORRIDA, ORIGEN, ' + @cols + N') '
                 + N'SELECT ID_CORRIDA, @codigo, ' + @sel + N' FROM '
                 + QUOTENAME(PARSENAME(@src, 2)) + N'.' + QUOTENAME(PARSENAME(@src, 1))
                 + N' WHERE ID_CORRIDA = @id_corrida; SET @n = @@ROWCOUNT;';
        EXEC sp_executesql @sql, N'@id_corrida INT, @codigo VARCHAR(50), @n INT OUTPUT',
             @id_corrida = @id_corrida, @codigo = @codigo, @n = @n OUTPUT;
        SET @total += @n;
        FETCH NEXT FROM cur INTO @src, @codigo;
    END;
    CLOSE cur; DEALLOCATE cur;

    /* Sin llave (riesgo vacío): a rechazos */
    INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, MOTIVO, DATOS)
    SELECT @id_corrida, 'LAYOUT_486', N'Sin riesgo (llave única) en el layout',
           (SELECT d.ORIGEN, d.DES_PROD FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM stg.LAYOUT_486 d WHERE d.CUENTA IS NULL;
    DELETE FROM stg.LAYOUT_486 WHERE CUENTA IS NULL;

    /* 20/11: la llave (riesgo) repetida en la asignación detiene la corrida y avisa al equipo, igual que la validación
       de la entrada. Dentro de una base ya la detiene la regla LLAVE_UNICA; aquí queda el mismo riesgo en dos segmentos. */
    IF EXISTS (SELECT 1 FROM stg.LAYOUT_486 GROUP BY CUENTA HAVING COUNT(DISTINCT ORIGEN) > 1)
    BEGIN
        DECLARE @rep INT, @ej NVARCHAR(1000), @msg NVARCHAR(2048);
        SELECT @rep = COUNT(*) FROM (SELECT CUENTA FROM stg.LAYOUT_486 GROUP BY CUENTA HAVING COUNT(DISTINCT ORIGEN) > 1) x;
        SELECT @ej = STRING_AGG(CAST(CONCAT(cfg.fn_enmascarar(CUENTA), N' (', O, N')') AS NVARCHAR(MAX)), N'; ')
        FROM (SELECT TOP (5) CUENTA, STRING_AGG(CAST(ORIGEN AS NVARCHAR(100)), N' y ') AS O FROM stg.LAYOUT_486 GROUP BY CUENTA HAVING COUNT(DISTINCT ORIGEN) > 1 ORDER BY CUENTA) e;
        INSERT INTO ops.VALIDACION_ENTRADA (ID_CORRIDA, CODIGO, TIPO, CAMPO, ESPERADO, REVISADOS, ANOMALOS, PCT, PCT_MAX, EJEMPLOS, DETIENE)
        VALUES (@id_corrida, 'LAYOUT_486', 'LLAVE_UNICA', N'RIESGO', N'Cada riesgo en un solo segmento', @total, @rep,
                CAST(@rep * 100.0 / NULLIF(@total, 0) AS DECIMAL(7,2)), 0, LEFT(@ej, 1000), 1);
        EXEC ops.sp_log @id_corrida, 'ASIG UNIR LAYOUT', 'ERROR', @rep, N'Riesgos repetidos entre segmentos: la asignación se detiene.';
        EXEC ops.sp_validacion_entrada_avisar @id_corrida, @msg OUTPUT;
        THROW 50025, @msg, 1;
    END;

    /* Repetido dentro de la misma base: lo detiene la regla LLAVE_UNICA de la validación de la entrada. Si el equipo le
       subió la tolerancia, se conserva el primero y los demás van a rechazos */
    ;WITH d AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY CUENTA ORDER BY ORIGEN) AS RN FROM stg.LAYOUT_486)
    INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, MOTIVO, DATOS)
    SELECT @id_corrida, 'LAYOUT_486', N'CUENTA duplicada en el layout (riesgo repetido en la base)',
           (SELECT d.ORIGEN, d.DES_PROD FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM d WHERE RN > 1;
    ;WITH d AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY CUENTA ORDER BY ORIGEN) AS RN FROM stg.LAYOUT_486)
    DELETE FROM d WHERE RN > 1;

    EXEC ops.sp_log @id_corrida, 'ASIG UNIR LAYOUT', 'OK', @total;
    EXEC ops.sp_asig_avisos_llave @id_corrida;
END;
GO

/* ---------------------------------------------------------------------
   Avisos de la llave por riesgo (20/11). No detienen la asignación; llegan
   al equipo en el correo de hallazgos:
   - mismo riesgo con otro RFC que el que tiene el DAT (riesgo reutilizado o
     dato corregido por el banco);
   - cambio de segmento: la cuenta llega en otro segmento que el del DAT o,
     si regresa (reasignada), que el de su último registro en el histórico.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_asig_avisos_llave
    @id_corrida  INT,
    @solo_prueba BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @rfc INT, @seg INT, @ej_rfc NVARCHAR(600), @ej_seg NVARCHAR(600), @msg NVARCHAR(4000), @json NVARCHAR(MAX);

    SELECT l.CUENTA, l.ORIGEN INTO #rfc
    FROM stg.LAYOUT_486 l
    JOIN dat.DAT_486 d ON d.CUENTA = l.CUENTA
    WHERE l.ID_CORRIDA = @id_corrida
      AND NULLIF(LTRIM(RTRIM(l.RFC)), '') IS NOT NULL AND NULLIF(LTRIM(RTRIM(d.RFC)), '') IS NOT NULL
      AND UPPER(REPLACE(LTRIM(RTRIM(l.RFC)), ' ', '')) <> UPPER(REPLACE(LTRIM(RTRIM(d.RFC)), ' ', ''));
    SELECT l.CUENTA, CONCAT(x.SEG, N' -> ', l.SEGMENTO2) AS CAMBIO INTO #seg
    FROM stg.LAYOUT_486 l
    OUTER APPLY (SELECT TOP (1) d.SEGMENTO2 AS SEG FROM dat.DAT_486 d WHERE d.CUENTA = l.CUENTA) dd
    OUTER APPLY (SELECT TOP (1) h.SEGMENTO2 AS SEG FROM dat.HISTORIA_FOLIO h
                 WHERE dd.SEG IS NULL AND h.CLIENTE = @cliente AND h.CUENTA = l.CUENTA ORDER BY h.FE_ALTA DESC, h.ID DESC) hh
    CROSS APPLY (SELECT ISNULL(dd.SEG, hh.SEG) AS SEG) x
    WHERE l.ID_CORRIDA = @id_corrida AND x.SEG IS NOT NULL AND x.SEG <> l.SEGMENTO2;

    SELECT @ej_rfc = STRING_AGG(CAST(cfg.fn_enmascarar(CUENTA) AS NVARCHAR(MAX)), N', ') FROM (SELECT TOP (5) CUENTA FROM #rfc ORDER BY CUENTA) e;
    SET @rfc = (SELECT COUNT(*) FROM #rfc);
    SELECT @ej_seg = STRING_AGG(CAST(CONCAT(cfg.fn_enmascarar(CUENTA), N' (', CAMBIO, N')') AS NVARCHAR(MAX)), N', ') FROM (SELECT TOP (5) CUENTA, CAMBIO FROM #seg ORDER BY CUENTA) e;
    SET @seg = (SELECT COUNT(*) FROM #seg);
    IF @rfc = 0 AND @seg = 0
    BEGIN
        IF @solo_prueba = 0 EXEC ops.sp_log @id_corrida, 'ASIG AVISOS LLAVE', 'OK', 0, N'Sin riesgos con otro RFC ni cambios de segmento.';
        RETURN;
    END;
    SET @msg = CONCAT(CASE WHEN @rfc > 0 THEN CONCAT(N'Riesgos con otro RFC que el del DAT: ', @rfc, N' (', @ej_rfc, N')') ELSE N'' END,
                      CASE WHEN @rfc > 0 AND @seg > 0 THEN N' · ' ELSE N'' END,
                      CASE WHEN @seg > 0 THEN CONCAT(N'Cuentas que cambian de segmento: ', @seg, N' (', @ej_seg, N')') ELSE N'' END);
    IF @solo_prueba = 1
    BEGIN
        SELECT @rfc AS OTRO_RFC, @seg AS CAMBIO_SEGMENTO, @msg AS MENSAJE;
        RETURN;
    END;
    DECLARE @total INT = @rfc + @seg;
    EXEC ops.sp_log @id_corrida, 'ASIG AVISOS LLAVE', 'AVISO', @total, @msg;
    SET @json = (SELECT N'Avisos de la llave por riesgo' AS TIPO, @msg AS DETALLE,
                        N'No detiene la asignación. Revisar con el banco si el riesgo es el mismo crédito; las cuentas que cambian de segmento quedan en el segmento nuevo.' AS ACCION,
                        N'ASIG' AS PROCESO, N'' AS HTML_TABLA
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRY
        EXEC mail.sp_enviar @plantilla = 'HALLAZGO_486', @id_corrida = @id_corrida, @valores = @json;
    END TRY
    BEGIN CATCH
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------
   Devolución por segmento (asig_bases.prg): cuentas del DAT de ese
   SEGMENTO2 que no vienen en la base maestra recibida.
   Llave por archivo en cfg.ARCHIVO.LLAVE_DAT: RIESGO en todos los segmentos (20/11; antes Consumo/Hipo DES_PROD).
   Tope: si se devolvería más del TOPE_DEVOLUCION_PCT del segmento se
   detiene (una base incompleta provocaría un retiro masivo).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_asig_devolucion
    @id_corrida INT,
    @forzar     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @tope DECIMAL(9,2) = TRY_CONVERT(DECIMAL(9,2), cfg.fn_param(@cliente, 'TOPE_DEVOLUCION_PCT'));
    DECLARE @src SYSNAME, @codigo VARCHAR(50), @seg VARCHAR(20), @llave SYSNAME, @sql NVARCHAR(MAX),
            @total INT, @dev INT, @pct DECIMAL(9,2), @msg NVARCHAR(4000), @json NVARCHAR(MAX);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT a.TABLA_DESTINO, a.CODIGO, a.SEGMENTO2, a.LLAVE_DAT
        FROM cfg.ARCHIVO a
        JOIN ops.ARCHIVO_CARGADO c ON c.ID_ARCHIVO = a.ID_ARCHIVO AND c.ID_CORRIDA = @id_corrida AND c.ESTATUS = 'CARGADO'
        WHERE a.PROCESO = 'ASIG' AND a.SEGMENTO2 IS NOT NULL AND a.LLAVE_DAT IS NOT NULL;
    OPEN cur;
    FETCH NEXT FROM cur INTO @src, @codigo, @seg, @llave;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'SELECT @total = COUNT(*) FROM dat.DAT_486 d WHERE d.SEGMENTO2 = @seg; '
                 + N'SELECT @dev = COUNT(*) FROM dat.DAT_486 d WHERE d.SEGMENTO2 = @seg AND NOT EXISTS (SELECT 1 FROM '
                 + QUOTENAME(PARSENAME(@src, 2)) + N'.' + QUOTENAME(PARSENAME(@src, 1))
                 + N' s WHERE s.ID_CORRIDA = @id_corrida AND s.' + QUOTENAME(@llave) + N' = d.' + QUOTENAME(@llave) + N');';
        EXEC sp_executesql @sql, N'@id_corrida INT, @seg VARCHAR(20), @total INT OUTPUT, @dev INT OUTPUT',
             @id_corrida = @id_corrida, @seg = @seg, @total = @total OUTPUT, @dev = @dev OUTPUT;

        SET @pct = CASE WHEN @total > 0 THEN 100.0 * ISNULL(@dev, 0) / @total ELSE 0 END;
        SET @msg = CONCAT(@seg, N': ', ISNULL(@dev, 0), N' de ', @total, N' cuentas del DAT no vienen en la base (', @pct, N'%)');

        IF @tope IS NOT NULL AND @pct > @tope AND @forzar = 0
        BEGIN
            EXEC ops.sp_log @id_corrida, 'ASIG DEVOLUCION', 'ERROR', @dev, @msg;
            CLOSE cur; DEALLOCATE cur;
            SET @msg = @msg + N'. Supera el tope de ' + CAST(@tope AS NVARCHAR(10)) + N'%. Revisa la base o vuelve a correr con @forzar_devolucion = 1.';
            THROW 50100, @msg, 1;
        END;

        SET @sql = N'INSERT INTO ops.DEVOLUCION (ID_CORRIDA, CLIENTE, CUENTA, SEGMENTO2, MOTIVO, ORIGEN) '
                 + N'SELECT @id_corrida, @cliente, d.CUENTA, d.SEGMENTO2, N''NO VIENE EN BASE MAESTRA'', @codigo '
                 + N'FROM dat.DAT_486 d WHERE d.SEGMENTO2 = @seg AND NOT EXISTS (SELECT 1 FROM '
                 + QUOTENAME(PARSENAME(@src, 2)) + N'.' + QUOTENAME(PARSENAME(@src, 1))
                 + N' s WHERE s.ID_CORRIDA = @id_corrida AND s.' + QUOTENAME(@llave) + N' = d.' + QUOTENAME(@llave) + N') '
                 + N'AND NOT EXISTS (SELECT 1 FROM ops.DEVOLUCION x WHERE x.ID_CORRIDA = @id_corrida AND x.CUENTA = d.CUENTA);';
        EXEC sp_executesql @sql, N'@id_corrida INT, @cliente VARCHAR(10), @seg VARCHAR(20), @codigo VARCHAR(50)',
             @id_corrida = @id_corrida, @cliente = @cliente, @seg = @seg, @codigo = @codigo;

        EXEC ops.sp_log @id_corrida, 'ASIG DEVOLUCION', 'OK', @dev, @msg;
        FETCH NEXT FROM cur INTO @src, @codigo, @seg, @llave;
    END;
    CLOSE cur; DEALLOCATE cur;
END;
GO

/* ---------------------------------------------------------------------
   Cuentas existentes: se marcan en el layout y se actualizan en el DAT
   los campos de cfg.PARAMETRO 'CAMPOS_ACTUALIZA_EXISTENTES'. Solo se
   tocan los registros que realmente cambiaron (incluye SALDO3, H-19) y
   ETIQUETA1 se aplica directo (sin el C:\MORA1 acumulado, H-17).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_asig_existentes
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @campos NVARCHAR(4000) = cfg.fn_param(@cliente, 'CAMPOS_ACTUALIZA_EXISTENTES');
    DECLARE @set NVARCHAR(MAX), @d NVARCHAR(MAX), @l NVARCHAR(MAX), @sql NVARCHAR(MAX), @n INT, @existentes INT;

    UPDATE l SET ES_EXISTENTE = 1
    FROM stg.LAYOUT_486 l
    JOIN dat.DAT_486 d ON d.CUENTA = l.CUENTA
    WHERE l.ID_CORRIDA = @id_corrida;
    SET @existentes = @@ROWCOUNT;

    SELECT @set = STRING_AGG(CAST(N'd.' + QUOTENAME(c.value) + N' = l.' + QUOTENAME(c.value) AS NVARCHAR(MAX)), N', '),
           @d   = STRING_AGG(CAST(N'd.' + QUOTENAME(c.value) AS NVARCHAR(MAX)), N', '),
           @l   = STRING_AGG(CAST(N'l.' + QUOTENAME(c.value) AS NVARCHAR(MAX)), N', ')
    FROM (SELECT DISTINCT LTRIM(RTRIM(value)) AS value FROM STRING_SPLIT(@campos, ',')) c
    WHERE COL_LENGTH('dat.DAT_486', c.value) IS NOT NULL
      AND COL_LENGTH('stg.LAYOUT_486', c.value) IS NOT NULL;

    IF @set IS NULL
    BEGIN
        EXEC ops.sp_log @id_corrida, 'ASIG EXISTENTES', 'AVISO', @existentes, N'Parámetro CAMPOS_ACTUALIZA_EXISTENTES vacío: no se actualizó el DAT.';
        RETURN;
    END;

    /* EXISTS (SELECT … EXCEPT SELECT …) compara también NULL contra valor */
    SET @sql = N'UPDATE d SET ' + @set + N', d.ID_CORRIDA_ULT = @id_corrida, d.FE_ULT_ACT = SYSDATETIME() '
             + N'FROM dat.DAT_486 d JOIN stg.LAYOUT_486 l ON l.CUENTA = d.CUENTA '
             + N'WHERE l.ID_CORRIDA = @id_corrida AND l.ES_EXISTENTE = 1 '
             + N'AND EXISTS (SELECT ' + @d + N' EXCEPT SELECT ' + @l + N'); SET @n = @@ROWCOUNT;';
    EXEC sp_executesql @sql, N'@id_corrida INT, @n INT OUTPUT', @id_corrida = @id_corrida, @n = @n OUTPUT;

    SET @sql = CONCAT(@existentes, N' cuentas ya estaban en el DAT; ', @n, N' con algún cambio actualizado.');
    EXEC ops.sp_log @id_corrida, 'ASIG EXISTENTES', 'OK', @n, @sql;
END;
GO

/* ---------------------------------------------------------------------
   Alta de cuentas nuevas.
   REA: la cuenta tuvo folio antes (dat.HISTORIA_FOLIO) -> se reutiliza.
   NVA: folio consecutivo de dat.FOLIO_CONSECUTIVO, con bloqueo para que dos
        corridas no repartan el mismo folio.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_asig_alta
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @cliente VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;

    DECLARE @prefijo VARCHAR(10) = ISNULL(cfg.fn_param(@cliente, 'PREFIJO_CUENTA2'), @cliente + '-'),
            @dias_reg INT        = ISNULL(TRY_CONVERT(INT, cfg.fn_param(@cliente, 'DIAS_FE_REG')), 30),
            @alerta   INT        = TRY_CONVERT(INT, cfg.fn_param(@cliente, 'ALERTA_NUEVAS')),
            @ult INT, @nva INT, @rea INT, @monto DECIMAL(18,2), @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);

    BEGIN TRANSACTION;

    /* REA: último folio de la cuenta en el histórico */
    UPDATE l SET l.FOLIO = CAST(h.FOLIO AS VARCHAR(10)), l.SUB_CTE = 'REA'
    FROM stg.LAYOUT_486 l
    CROSS APPLY (SELECT TOP (1) FOLIO FROM dat.HISTORIA_FOLIO h
                 WHERE h.CLIENTE = @cliente AND h.CUENTA = l.CUENTA
                 ORDER BY h.FE_ALTA DESC, h.ID DESC) h
    WHERE l.ID_CORRIDA = @id_corrida AND l.ES_EXISTENTE = 0;
    SET @rea = @@ROWCOUNT;

    /* Si el histórico tenía la cuenta como activa (no estaba en el DAT), se cierra antes de reabrir */
    UPDATE h SET ESTATUS = 'B', FE_BAJA = @fecha, MOTIVO_BAJA = 'CIERRE POR REASIGNACION', ID_CORRIDA_BAJA = @id_corrida
    FROM dat.HISTORIA_FOLIO h
    JOIN stg.LAYOUT_486 l ON l.CUENTA = h.CUENTA AND l.ID_CORRIDA = @id_corrida AND l.SUB_CTE = 'REA'
    WHERE h.CLIENTE = @cliente AND h.ESTATUS = 'A';

    /* NVA: folios consecutivos */
    SELECT @ult = ULTIMO_FOLIO FROM dat.FOLIO_CONSECUTIVO WITH (UPDLOCK, HOLDLOCK) WHERE CLIENTE = @cliente;
    IF @ult IS NULL
        THROW 50110, 'No existe el consecutivo en dat.FOLIO_CONSECUTIVO para este cliente (cárgalo con el último folio de tab7).', 1;

    ;WITH n AS (
        SELECT FOLIO, SUB_CTE, ROW_NUMBER() OVER (ORDER BY SEGMENTO2, CUENTA) AS RN
        FROM stg.LAYOUT_486
        WHERE ID_CORRIDA = @id_corrida AND ES_EXISTENTE = 0 AND (FOLIO IS NULL OR LTRIM(FOLIO) = '')
    )
    UPDATE n SET FOLIO = CAST(@ult + RN AS VARCHAR(10)), SUB_CTE = 'NVA';
    SET @nva = @@ROWCOUNT;

    UPDATE dat.FOLIO_CONSECUTIVO SET ULTIMO_FOLIO = @ult + @nva, FE_ACT = SYSDATETIME() WHERE CLIENTE = @cliente;

    /* Valores por omisión */
    UPDATE stg.LAYOUT_486
    SET CLIENTE = @cliente,
        FE_ASIG = ISNULL(FE_ASIG, @fecha),
        FE_REC  = ISNULL(FE_REC,  @fecha),
        FE_REG  = ISNULL(FE_REG,  DATEADD(DAY, @dias_reg, ISNULL(FE_REC, @fecha))),
        CUENTA2 = @prefijo + LTRIM(FOLIO)
    WHERE ID_CORRIDA = @id_corrida AND ES_EXISTENTE = 0;

    /* Alta en el DAT */
    SELECT @cols = STRING_AGG(CAST(QUOTENAME(name) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY column_id)
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dat.DAT_486')
      AND name NOT IN ('ID_CORRIDA_ALTA', 'ID_CORRIDA_ULT', 'FE_ULT_ACT');

    SET @sql = N'INSERT INTO dat.DAT_486 (' + @cols + N', ID_CORRIDA_ALTA, ID_CORRIDA_ULT, FE_ULT_ACT) '
             + N'SELECT ' + @cols + N', @id_corrida, @id_corrida, SYSDATETIME() FROM stg.LAYOUT_486 '
             + N'WHERE ID_CORRIDA = @id_corrida AND ES_EXISTENTE = 0;';
    EXEC sp_executesql @sql, N'@id_corrida INT', @id_corrida = @id_corrida;

    INSERT INTO dat.HISTORIA_FOLIO (CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, CTA_BANCO, SUB_CTE, ESTATUS, FE_ALTA, ID_CORRIDA_ALTA)
    SELECT @cliente, CUENTA, CAST(FOLIO AS INT), CUENTA2, SEGMENTO2, LEFT(RIESGO, 35), CTA_BANCO, SUB_CTE, 'A', @fecha, @id_corrida
    FROM stg.LAYOUT_486
    WHERE ID_CORRIDA = @id_corrida AND ES_EXISTENTE = 0;

    SELECT @monto = SUM(SDO_ACT) FROM stg.LAYOUT_486
    WHERE ID_CORRIDA = @id_corrida AND ES_EXISTENTE = 0 AND SUB_CTE = 'NVA';

    COMMIT TRANSACTION;

    SET @sql = CONCAT(N'NVA: ', @nva, N' (folios ', @ult + 1, N' a ', @ult + @nva, N', monto ', ISNULL(@monto, 0), N') · REA: ', @rea);
    DECLARE @altas INT = @nva + @rea;
    EXEC ops.sp_log @id_corrida, 'ASIG ALTA', 'OK', @altas, @sql;

    IF @alerta IS NOT NULL AND @nva > @alerta
    BEGIN
        DECLARE @json NVARCHAR(MAX) = (SELECT @nva AS NUEVAS, @alerta AS UMBRAL FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC ops.sp_log @id_corrida, 'ASIG ALTA', 'AVISO', @nva, N'Más cuentas nuevas que el umbral ALERTA_NUEVAS (aem_alerta).';
        EXEC mail.sp_enviar @plantilla = 'ALERTA_NUEVAS_486', @id_corrida = @id_corrida, @valores = @json;
    END;
END;
GO

/* ---------------------------------------------------------------------
   Retiro (prog15.prg): baja en DAT, histórico, script para CYBER y
   archivos planos del retiro. Se llama al final de la asignación o de la
   actualización, a mano después de revisar ops.DEVOLUCION, o desde
   ops.sp_retiro_solicitud.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_retiro
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @cliente VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    DECLARE @dmstatus VARCHAR(10) = cfg.fn_param(@cliente, 'DMSTATUS_RETIRO'), @n INT;

    BEGIN TRANSACTION;

    /* Histórico: baja con foto del registro */
    UPDATE h SET ESTATUS = 'B', FE_BAJA = @fecha, MOTIVO_BAJA = LEFT(v.MOTIVO, 60), ID_CORRIDA_BAJA = @id_corrida,
                 RIESGO = ISNULL(h.RIESGO, LEFT(d.RIESGO, 35)), CTA_BANCO = ISNULL(h.CTA_BANCO, d.CTA_BANCO),
                 DATOS_BAJA = (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM dat.HISTORIA_FOLIO h
    JOIN ops.DEVOLUCION v ON v.CUENTA = h.CUENTA AND v.ID_CORRIDA = @id_corrida AND v.PROCESADA = 0
    JOIN dat.DAT_486 d ON d.CUENTA = v.CUENTA
    WHERE h.CLIENTE = @cliente AND h.ESTATUS = 'A';

    /* Cuentas sin histórico (cargadas antes de la migración): se registra la baja */
    INSERT INTO dat.HISTORIA_FOLIO (CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, RIESGO, CTA_BANCO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA,
                                    MOTIVO_BAJA, ID_CORRIDA_BAJA, DATOS_BAJA, ID_CORRIDA_ALTA)
    SELECT @cliente, d.CUENTA, ISNULL(TRY_CONVERT(INT, d.FOLIO), 0), ISNULL(d.CUENTA2, ''), d.SEGMENTO2, LEFT(d.RIESGO, 35), d.CTA_BANCO,
           CASE WHEN LEFT(d.SUB_CTE, 3) IN ('NVA', 'REA') THEN LEFT(d.SUB_CTE, 3) ELSE 'NVA' END, 'B',
           ISNULL(d.FE_ASIG, @fecha), @fecha, LEFT(v.MOTIVO, 60), @id_corrida,
           (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), 0     -- 0 = sin alta registrada (para el retroceso)
    FROM ops.DEVOLUCION v
    JOIN dat.DAT_486 d ON d.CUENTA = v.CUENTA
    WHERE v.ID_CORRIDA = @id_corrida AND v.PROCESADA = 0
      AND NOT EXISTS (SELECT 1 FROM dat.HISTORIA_FOLIO h WHERE h.CLIENTE = @cliente AND h.CUENTA = d.CUENTA AND h.ID_CORRIDA_BAJA = @id_corrida);

    /* Script para CYBER */
    IF @dmstatus IS NOT NULL
    BEGIN
        DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'RETIRO';
        INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
        SELECT @id_corrida, 'RETIRO', ROW_NUMBER() OVER (ORDER BY d.CUENTA2),
               CONCAT(N'update RCVRY.delqmst set dmstatus=''', @dmstatus, N''' where dmacctg=''1'' and dmacct=''', REPLACE(d.CUENTA2, '''', ''''''), N''';')
        FROM ops.DEVOLUCION v
        JOIN dat.DAT_486 d ON d.CUENTA = v.CUENTA
        WHERE v.ID_CORRIDA = @id_corrida AND v.PROCESADA = 0;
        SET @n = @@ROWCOUNT;
        INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
        VALUES (@id_corrida, 'RETIRO', @n + 1, N'commit;'), (@id_corrida, 'RETIRO', @n + 2, N'exit;');
    END
    ELSE
        EXEC ops.sp_log @id_corrida, 'RETIRO', 'AVISO', NULL, N'Sin parámetro DMSTATUS_RETIRO: no se generó el script de CYBER.';

    /* Baja del DAT */
    DELETE d
    FROM dat.DAT_486 d
    JOIN ops.DEVOLUCION v ON v.CUENTA = d.CUENTA AND v.ID_CORRIDA = @id_corrida AND v.PROCESADA = 0;
    SET @n = @@ROWCOUNT;

    UPDATE ops.DEVOLUCION SET PROCESADA = 1 WHERE ID_CORRIDA = @id_corrida AND PROCESADA = 0;

    COMMIT TRANSACTION;
    EXEC ops.sp_log @id_corrida, 'RETIRO', 'OK', @n;

    /* Archivos planos del retiro (cfg.SALIDA_ARCHIVO, PROCESO = 'RETIRO'): devolución para CYBER
       (MX_G1MCT_DVBJIG_*), gescar de retiro (SCBACTH_486) y lista de folios para operación */
    EXEC ops.sp_generar_salidas @id_corrida, 'RETIRO';
END;
GO
