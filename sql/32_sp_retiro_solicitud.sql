/* =====================================================================
   Banbaj · 32 Retiro por solicitud
   ---------------------------------------------------------------------
   Retira cuentas que pide el banco u Operación fuera de la asignación y de
   la actualización (antes: DEVOL1 por folio en prog15.prg). Acepta FOLIO
   (con o sin '486-') o RIESGO (crédito del banco).

   Uso:
     -- 1) Vista previa (no cambia nada): qué se retiraría y qué no se encontró
     EXEC ops.sp_retiro_solicitud @valores = N'486-100001, 100002, 1000000003';
     EXEC ops.sp_retiro_solicitud @archivo = N'D:\Banbaj\486\retiros\solicitud.csv';

     -- 2) Aplicar: corrida RET con respaldo (se puede revertir), baja en DAT,
     --    histórico, script de CYBER y archivos planos del retiro
     EXEC ops.sp_retiro_solicitud @valores = N'…', @motivo = N'SOLICITUD BANCO 28/10', @confirmar = 1;

   @tipo: AUTO (default) | FOLIO | RIESGO
     AUTO: con prefijo '486-' es folio; sin prefijo se busca primero como
     RIESGO y, si no existe, como folio. Si un valor coincide como riesgo de
     una cuenta y como folio de otra, se marca AMBIGUO y no se retira.
   El archivo: un valor por renglón (si trae más columnas se toma la primera);
   se ignoran encabezados FOLIO / RIESGO / CREDITO / CUENTA2.
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_retiro_solicitud
    @cliente    VARCHAR(10)   = '486',
    @valores    NVARCHAR(MAX) = NULL,
    @archivo    NVARCHAR(500) = NULL,
    @tipo       VARCHAR(10)   = 'AUTO',
    @motivo     NVARCHAR(80)  = N'RETIRO POR SOLICITUD',
    @confirmar  BIT           = 0,
    @codepage   VARCHAR(10)   = 'ACP',      -- '' en SQL Server Linux
    @id_corrida INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @tipo NOT IN ('AUTO', 'FOLIO', 'RIESGO') THROW 50500, '@tipo debe ser AUTO, FOLIO o RIESGO.', 1;
    IF @valores IS NULL AND @archivo IS NULL THROW 50501, 'Indica @valores o @archivo.', 1;

    DECLARE @prefijo VARCHAR(10) = ISNULL(cfg.fn_param(@cliente, 'PREFIJO_CUENTA2'), @cliente + '-');
    DECLARE @sql NVARCHAR(MAX), @n INT, @msg NVARCHAR(4000);

    CREATE TABLE #v (ID INT IDENTITY(1,1), VALOR NVARCHAR(200));
    IF @valores IS NOT NULL
        INSERT INTO #v (VALOR)
        SELECT value FROM STRING_SPLIT(REPLACE(REPLACE(REPLACE(REPLACE(@valores, CHAR(13), N''), CHAR(10), N','), N';', N','), CHAR(9), N','), N',');
    IF @archivo IS NOT NULL
    BEGIN
        CREATE TABLE #raw (L NVARCHAR(1000));
        SET @sql = N'BULK INSERT #raw FROM ' + QUOTENAME(@archivo, '''')
                 + N' WITH (ROWTERMINATOR = ''0x0a'', FIELDTERMINATOR = ''\t\t\t'''
                 + CASE WHEN NULLIF(@codepage, '') IS NOT NULL THEN N', CODEPAGE = ' + QUOTENAME(@codepage, '''') ELSE N'' END + N');';
        EXEC (@sql);
        INSERT INTO #v (VALOR)
        SELECT LEFT(x.L, CHARINDEX(N',', x.L + N',') - 1)
        FROM (SELECT REPLACE(REPLACE(REPLACE(L, CHAR(13), N''), N'"', N''), N';', N',') AS L FROM #raw) x;
    END;

    UPDATE #v SET VALOR = NULLIF(LTRIM(RTRIM(VALOR)), N'');
    DELETE FROM #v WHERE VALOR IS NULL OR UPPER(VALOR) IN (N'FOLIO', N'RIESGO', N'CREDITO', N'CRÉDITO', N'CUENTA2');

    /* Coincidencias como folio y como riesgo */
    SELECT v.ID, v.VALOR,
           CASE WHEN v.VALOR LIKE @prefijo + N'%' THEN 1 ELSE 0 END AS CON_PREFIJO,
           TRY_CONVERT(INT, CASE WHEN v.VALOR LIKE @prefijo + N'%' THEN SUBSTRING(v.VALOR, LEN(@prefijo) + 1, 50) ELSE v.VALOR END) AS FOLIO_N,
           f.CUENTA AS CTA_FOLIO, r.CUENTA AS CTA_RIESGO, r.N_RIESGO
    INTO #m
    FROM #v v
    OUTER APPLY (SELECT TOP (1) d.CUENTA FROM dat.DAT_486 d
                 WHERE d.CLIENTE = @cliente
                   AND TRY_CONVERT(INT, LTRIM(d.FOLIO)) = TRY_CONVERT(INT, CASE WHEN v.VALOR LIKE @prefijo + N'%'
                                                                          THEN SUBSTRING(v.VALOR, LEN(@prefijo) + 1, 50) ELSE v.VALOR END)) f
    OUTER APPLY (SELECT MIN(d.CUENTA) AS CUENTA, COUNT(*) AS N_RIESGO FROM dat.DAT_486 d
                 WHERE d.CLIENTE = @cliente AND LTRIM(RTRIM(d.RIESGO)) = v.VALOR) r;

    SELECT m.ID, m.VALOR,
           CASE WHEN x.CUENTA IS NOT NULL THEN x.TIPO
                WHEN m.CTA_RIESGO IS NOT NULL OR m.CTA_FOLIO IS NOT NULL THEN NULL END AS TIPO,
           x.CUENTA,
           CAST(CASE WHEN x.RES IS NOT NULL THEN x.RES
                     WHEN x.CUENTA IS NULL THEN 'NO ESTA EN EL DAT'
                     ELSE 'A RETIRAR' END AS VARCHAR(20)) AS RESULTADO
    INTO #r
    FROM #m m
    CROSS APPLY (
        SELECT CASE
                 WHEN @tipo = 'FOLIO' OR (@tipo = 'AUTO' AND m.CON_PREFIJO = 1) THEN m.CTA_FOLIO
                 WHEN @tipo = 'RIESGO' THEN CASE WHEN m.N_RIESGO = 1 THEN m.CTA_RIESGO END
                 WHEN m.CTA_RIESGO IS NOT NULL AND m.CTA_FOLIO IS NOT NULL AND m.CTA_RIESGO <> m.CTA_FOLIO THEN NULL
                 ELSE CASE WHEN m.N_RIESGO = 1 THEN m.CTA_RIESGO ELSE m.CTA_FOLIO END
               END AS CUENTA,
               CASE
                 WHEN @tipo = 'FOLIO' OR (@tipo = 'AUTO' AND m.CON_PREFIJO = 1) THEN 'FOLIO'
                 WHEN @tipo = 'RIESGO' THEN 'RIESGO'
                 WHEN m.N_RIESGO = 1 THEN 'RIESGO'
                 ELSE 'FOLIO'
               END AS TIPO,
               CASE
                 WHEN (@tipo = 'RIESGO' OR (@tipo = 'AUTO' AND m.CON_PREFIJO = 0)) AND m.N_RIESGO > 1 THEN 'RIESGO REPETIDO'
                 WHEN @tipo = 'AUTO' AND m.CON_PREFIJO = 0 AND m.CTA_RIESGO IS NOT NULL AND m.CTA_FOLIO IS NOT NULL
                      AND m.CTA_RIESGO <> m.CTA_FOLIO THEN 'AMBIGUO'
               END AS RES
    ) x;

    /* La misma cuenta pedida dos veces */
    ;WITH d AS (SELECT RESULTADO, ROW_NUMBER() OVER (PARTITION BY CUENTA ORDER BY ID) AS RN FROM #r WHERE RESULTADO = 'A RETIRAR')
    UPDATE d SET RESULTADO = 'REPETIDO' WHERE RN > 1;

    IF @confirmar = 0
    BEGIN
        SELECT r.VALOR, r.TIPO, r.RESULTADO, d.CUENTA2, LTRIM(d.FOLIO) AS FOLIO, d.SEGMENTO2, d.SDO_ACT
        FROM #r r LEFT JOIN dat.DAT_486 d ON d.CUENTA = r.CUENTA
        ORDER BY r.ID;
        PRINT 'Vista previa: no se cambió nada. Ejecuta con @confirmar = 1 para retirar.';
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE RESULTADO = 'A RETIRAR')
        THROW 50502, 'Ningún valor corresponde a una cuenta del DAT; no se retiró nada.', 1;

    EXEC ops.sp_corrida_iniciar @cliente, 'RET', NULL, NULL, @id_corrida OUTPUT;
    BEGIN TRY
        EXEC ops.sp_respaldo @id_corrida;

        INSERT INTO ops.DEVOLUCION (ID_CORRIDA, CLIENTE, CUENTA, SEGMENTO2, MOTIVO, ORIGEN)
        SELECT @id_corrida, @cliente, d.CUENTA, d.SEGMENTO2, LEFT(@motivo, 100), CONCAT('SOLICITUD ', r.TIPO)
        FROM #r r JOIN dat.DAT_486 d ON d.CUENTA = r.CUENTA
        WHERE r.RESULTADO = 'A RETIRAR';
        SET @n = @@ROWCOUNT;

        INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, FILA, MOTIVO, DATOS)
        SELECT @id_corrida, 'RETIRO_SOLICITUD', ID, CONCAT(N'Retiro por solicitud: ', RESULTADO),
               (SELECT r.VALOR, r.TIPO FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM #r r WHERE RESULTADO <> 'A RETIRAR';

        EXEC ops.sp_retiro @id_corrida;

        SET @msg = CONCAT(N'Solicitados: ', (SELECT COUNT(*) FROM #r), N' · retirados: ', @n,
                          N' · no retirados: ', (SELECT COUNT(*) FROM #r WHERE RESULTADO <> 'A RETIRAR'));
        EXEC ops.sp_corrida_finalizar @id_corrida, 'OK', @msg;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_corrida_finalizar @id_corrida, 'ERROR', @msg;
        THROW;
    END CATCH;

    SELECT r.VALOR, r.TIPO, r.RESULTADO, h.CUENTA2, h.FOLIO
    FROM #r r
    LEFT JOIN dat.HISTORIA_FOLIO h ON h.CUENTA = r.CUENTA AND h.ID_CORRIDA_BAJA = @id_corrida AND r.RESULTADO = 'A RETIRAR'
    ORDER BY r.ID;
END;
GO
