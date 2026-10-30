/* Prueba de la migración desde CSV de FoxPro (ops.sp_migrar_486). Corre en una base vacía (BanbajMig). */
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
CREATE TABLE #r (ID INT IDENTITY(1,1), PRUEBA NVARCHAR(200), OK BIT, DETALLE NVARCHAR(1000));
DECLARE @c NVARCHAR(100) = N'/datos/migracion/', @err NVARCHAR(4000), @o NVARCHAR(1000);

BEGIN TRY
    EXEC ops.sp_migrar_486 @carpeta = @c, @codepage = '';
    INSERT INTO #r VALUES (N'Revisión sin confirmar no escribe', CASE WHEN (SELECT COUNT(*) FROM dat.DAT_486) = 0 THEN 1 ELSE 0 END, NULL);
END TRY
BEGIN CATCH INSERT INTO #r VALUES (N'Revisión sin confirmar no escribe', 0, ERROR_MESSAGE()); END CATCH;

BEGIN TRY
    EXEC ops.sp_migrar_486 @carpeta = @c, @codepage = '', @confirmar = 1;
    INSERT INTO #r VALUES (N'Primera carga', 1, NULL);
END TRY
BEGIN CATCH INSERT INTO #r VALUES (N'Primera carga', 0, ERROR_MESSAGE()); END CATCH;

SET @err = NULL;
BEGIN TRY EXEC ops.sp_migrar_486 @carpeta = @c, @codepage = '', @confirmar = 1; END TRY
BEGIN CATCH SET @err = CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
INSERT INTO #r VALUES (N'Segunda carga sin @reemplazar se rechaza y no cambia nada',
    CASE WHEN @err = N'50910' AND (SELECT COUNT(*) FROM dat.DAT_486) = 2 AND OBJECT_ID('stg.MIG_DAT') IS NULL THEN 1 ELSE 0 END, @err);

BEGIN TRY
    EXEC ops.sp_migrar_486 @carpeta = @c, @codepage = '', @confirmar = 1, @reemplazar = 1;
    INSERT INTO #r VALUES (N'Carga con @reemplazar', 1, NULL);
END TRY
BEGIN CATCH INSERT INTO #r VALUES (N'Carga con @reemplazar', 0, ERROR_MESSAGE()); END CATCH;

SET @o = (SELECT CONCAT(COUNT(*), '|', MAX(FOLIO), '|', SUM(CASE WHEN ETIQUETA1 IS NULL THEN 1 ELSE 0 END)) FROM dat.DAT_486);
INSERT INTO #r VALUES (N'DAT: 2 cuentas (repetida omitida), folio sin espacios, vacío -> NULL', CASE WHEN @o = N'2|101|1' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT(SDO_ACT, '|', FE_ASIG, '|', NOMBRE1) FROM dat.DAT_486 WHERE CUENTA = '20000001');
INSERT INTO #r VALUES (N'DAT: importe, fecha AAAAMMDD y texto', CASE WHEN @o = N'1500.50|2026-10-01|CLIENTE UNO' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT STRING_AGG(CONCAT(CUENTA, ':', ESTATUS, ':', SUB_CTE), ',') WITHIN GROUP (ORDER BY CUENTA) FROM dat.HISTORIA_FOLIO);
INSERT INTO #r VALUES (N'HISTORIA: solo las activas del DAT', CASE WHEN @o = N'20000001:A:NVA,20000002:A:REA' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CAST(ULTIMO_FOLIO AS NVARCHAR(10)) FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = '486');
INSERT INTO #r VALUES (N'CONSECUTIVO: máximo de TAB7 / DAT / HISTORIA', CASE WHEN @o = N'160' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT(COUNT(*), '|', MIN(CUENTA), '|', MIN(FE_PAG), '|', MIN(IMPORTE), '|', MIN(ORIGEN), '|', MIN(FE_REG)) FROM dat.PAGO_ARRIBADO);
INSERT INTO #r VALUES (N'PAGOS: PAGTOT con cuenta, fecha e importe (renglón corrido omitido, iguales se conservan)',
    CASE WHEN @o = N'2|20000001|2026-10-02|1000.00|PAGTOT|2026-10-03' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT STRING_AGG(CONCAT(TIPO, ':', LLAVE, ':', VALOR), ',') WITHIN GROUP (ORDER BY TIPO, LLAVE) FROM cfg.ETIQUETA);
INSERT INTO #r VALUES (N'ETIQUETAS: TOP', CASE WHEN @o = N'TOP:486-100:REE,TOP:486-999:REE' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT(COUNT(*), '|', SUM(CASE WHEN VALOR2 = '486-100' THEN 1 ELSE 0 END), '|',
                        SUM(CASE WHEN VALOR = '5522222222' THEN 1 ELSE 0 END), '|', SUM(CASE WHEN VALOR = '5500000000' THEN 1 ELSE 0 END)) FROM cfg.EXCLUSION);
INSERT INTO #r VALUES (N'EXCLUSIONES: 3 del banco (semilla) + exc486 + blacklist (10 dígitos) + TELBAJ solo del 486', CASE WHEN @o = N'6|1|0|1' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT((SELECT COUNT(*) FROM cfg.LADA), '|', (SELECT COUNT(*) FROM cfg.PLAN_NUMERACION), '|', (SELECT LADA FROM cfg.LADA WHERE CP = '06600')));
INSERT INTO #r VALUES (N'LADA y PNC', CASE WHEN @o = N'2|2|55' THEN 1 ELSE 0 END, @o);
INSERT INTO #r VALUES (N'Las tablas de paso con datos de clientes se borran', CASE WHEN NOT EXISTS (SELECT 1 FROM sys.tables WHERE name LIKE 'MIG[_]%') THEN 1 ELSE 0 END, NULL);

SELECT CASE OK WHEN 1 THEN 'OK   ' ELSE 'FALLA' END AS R, PRUEBA, DETALLE FROM #r ORDER BY ID;
DECLARE @f INT = (SELECT COUNT(*) FROM #r WHERE OK = 0), @t INT = (SELECT COUNT(*) FROM #r);
PRINT CONCAT('MIGRACION: ', @t - @f, ' de ', @t, ' OK');
IF @f > 0 THROW 50998, 'Hay pruebas de migración fallidas.', 1;
