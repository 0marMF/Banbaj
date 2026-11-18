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
INSERT INTO #r VALUES (N'DAT: importe, fecha AAAA/MM/DD (como la escribe FoxPro) y texto', CASE WHEN @o = N'1500.50|2026-10-01|CLIENTE UNO' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT STRING_AGG(CONCAT(CUENTA, ':', ESTATUS, ':', SUB_CTE), ',') WITHIN GROUP (ORDER BY CUENTA) FROM dat.HISTORIA_FOLIO);
INSERT INTO #r VALUES (N'HISTORIA: activas del DAT y cada asignación anterior de historia.dbf como baja',
    CASE WHEN @o = N'20000001:A:NVA,20000002:A:REA,20000007:B:NVA,20000009:B:NVA,20000009:B:REA' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT STRING_AGG(CONCAT(CUENTA, ':', FOLIO, ':', CUENTA2, ':', RIESGO, ':', FE_ALTA, ':', FE_BAJA), ',') WITHIN GROUP (ORDER BY CUENTA, FOLIO)
          FROM dat.HISTORIA_FOLIO WHERE ESTATUS = 'B');
INSERT INTO #r VALUES (N'HISTORIA: folio, CUENTA2 y crédito; fechas de asignación, reasignación y retiro vacías (03/11)',
    CASE WHEN @o = N'20000007:160:486-160:R7::,20000009:90:486-90:R9::,20000009:150:486-150:R9B::' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT MOTIVO_BAJA FROM dat.HISTORIA_FOLIO WHERE CUENTA = '20000009' AND FOLIO = 150);
INSERT INTO #r VALUES (N'PURGA no se usa: el periodo queda con el motivo de historia y sin fecha de retiro', CASE WHEN @o = N'MIGRACION (historia.dbf)' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT(JSON_VALUE(DATOS_BAJA, '$.SDO_ACT'), '|', JSON_VALUE(DATOS_BAJA, '$.TEL1'), '|', JSON_VALUE(DATOS_BAJA, '$.DIRECC1'), '|',
                        JSON_VALUE(DATOS_BAJA, '$.CORREO1'), '|', JSON_VALUE(DATOS_BAJA, '$.FE_BAJA'))
          FROM dat.HISTORIA_FOLIO WHERE CUENTA = '20000007');
INSERT INTO #r VALUES (N'HISTORIA: saldos, teléfonos, dirección y correos en DATOS_BAJA',
    CASE WHEN @o = N'1234.50|5511112222|CALLE ''LA FICTICIA'', NO. 7|uno@correo.com|2024/09/30' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CAST(ULTIMO_FOLIO AS NVARCHAR(10)) FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = '486');
INSERT INTO #r VALUES (N'CONSECUTIVO: máximo de TAB7 / DAT / HISTORIA', CASE WHEN @o = N'160' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT(COUNT(*), '|', MIN(CUENTA), '|', MIN(FE_PAG), '|', MIN(IMPORTE), '|', MIN(ORIGEN), '|', MIN(FE_REG)) FROM dat.PAGO_ARRIBADO);
INSERT INTO #r VALUES (N'PAGOS: PAGTOT con cuenta, fecha e importe (renglón corrido omitido, iguales se conservan)',
    CASE WHEN @o = N'2|20000001|2026-10-02|1000.00|PAGTOT|2026-10-03' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT STRING_AGG(CONCAT(TIPO, ':', LLAVE, ':', VALOR), ',') WITHIN GROUP (ORDER BY TIPO, LLAVE) FROM cfg.ETIQUETA);
INSERT INTO #r VALUES (N'ETIQUETAS: TOP', CASE WHEN @o = N'TOP:486-100:REE,TOP:486-999:REE' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT(COUNT(*), '|', SUM(CASE WHEN VALOR2 = '486-100' THEN 1 ELSE 0 END), '|',
                        SUM(CASE WHEN VALOR = '5522222222' THEN 1 ELSE 0 END), '|', SUM(CASE WHEN VALOR = '5500000000' THEN 1 ELSE 0 END)) FROM cfg.EXCLUSION);
INSERT INTO #r VALUES (N'EXCLUSIONES: 3 del banco (semilla) + exc486 + blacklist (10 dígitos); TELBAJ ya no se migra', CASE WHEN @o = N'6|0|0|1' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT STRING_AGG(CONCAT(VALOR, ':', ACTIVO, ':', REQ, ':', CAST(FE_ALTA AS DATE), ':', MOTIVO), ',') WITHIN GROUP (ORDER BY VALOR)
          FROM cfg.EXCLUSION WHERE TIPO = 'TELEFONO' AND ORIGEN = 'MIGRACION DBF');
INSERT INTO #r VALUES (N'BLACKLIST (TEL, FE_AGRE, OS, SOLICITUD; sin STATUS todo es X)',
    CASE WHEN @o = N'5500000000:1:OS-1:2026-01-01:Solicita: OPERACION,5511110000:1:OS-2:2026-02-01:Lista negra de teléfonos (blacklist_486)' THEN 1 ELSE 0 END, @o);
SET @o = (SELECT CONCAT((SELECT COUNT(*) FROM cfg.LADA), '|', (SELECT COUNT(*) FROM cfg.PLAN_NUMERACION)));
INSERT INTO #r VALUES (N'LADA y PNC ya no se migran', CASE WHEN @o = N'0|0' THEN 1 ELSE 0 END, @o);
/* CSV que SQL Server no puede leer (comillas dobles dentro de un campo): el error dice qué ve el servidor */
DECLARE @mala NVARCHAR(200) = N'/datos/migracion_mala/HISTORIA.csv', @res NVARCHAR(3000);
SET @err = NULL;
BEGIN TRY EXEC ops.sp_mig_leer N'HISTORIA', @mala, ''; END TRY
BEGIN CATCH SET @err = CONCAT(ERROR_NUMBER(), '|', ERROR_MESSAGE()); END CATCH;
INSERT INTO #r VALUES (N'CSV ilegible: 50905 con renglones, comillas fuera de lo normal y el renglón',
    CASE WHEN @err LIKE N'50905|%El servidor ve 4 renglones%Casi todos traen 6 comillas; con otro número: 1 (renglones 3:%' THEN 1 ELSE 0 END, LEFT(@err, 1000));
SET @err = NULL;
BEGIN TRY EXEC ops.sp_migrar_486 @carpeta = N'/datos/migracion_mala/', @codepage = ''; END TRY
BEGIN CATCH SET @err = CONCAT(ERROR_NUMBER(), '|', ERROR_MESSAGE()); END CATCH;
INSERT INTO #r VALUES (N'sp_migrar_486 con el CSV ilegible: mismo 50905 y no deja tablas de paso',
    CASE WHEN @err LIKE N'50905|%HISTORIA.csv%con otro número: 1 (renglones 3:%'
          AND NOT EXISTS (SELECT 1 FROM sys.tables WHERE name LIKE 'MIG[_]%') THEN 1 ELSE 0 END, LEFT(@err, 1000));
BEGIN TRY
    EXEC ops.sp_mig_diagnostico @mala, 3, '', @res OUTPUT, @mostrar = 0;
    INSERT INTO #r VALUES (N'sp_mig_diagnostico sin @mostrar solo regresa el resumen', CASE WHEN @res LIKE N'El servidor ve 4 renglones%' THEN 1 ELSE 0 END, @res);
END TRY
BEGIN CATCH INSERT INTO #r VALUES (N'sp_mig_diagnostico sin @mostrar solo regresa el resumen', 0, ERROR_MESSAGE()); END CATCH;
CREATE TABLE #dg (RENGLON INT, COMILLAS INT, CAMPOS INT, RAROS NVARCHAR(400), ENMASCARADO NVARCHAR(MAX));
BEGIN TRY
    INSERT INTO #dg EXEC ops.sp_mig_diagnostico @mala, 3, '';
    SET @o = (SELECT STRING_AGG(CONCAT(RENGLON, ':', COMILLAS, ':', CAMPOS), ',') WITHIN GROUP (ORDER BY RENGLON) FROM #dg);
    SET @o = CONCAT(@o, '|', (SELECT ENMASCARADO FROM #dg WHERE RENGLON = 3));
    INSERT INTO #r VALUES (N'sp_mig_diagnostico: renglón y vecinos enmascarados con comillas y campos',
        CASE WHEN @o = N'1:0:4,2:6:4,3:8:4,4:6:4|"99999999","       999",9999/99/99,"xxxxx "xxx" 9"' THEN 1 ELSE 0 END, @o);
END TRY
BEGIN CATCH INSERT INTO #r VALUES (N'sp_mig_diagnostico: renglón y vecinos enmascarados con comillas y campos', 0, ERROR_MESSAGE()); END CATCH;

INSERT INTO #r VALUES (N'Las tablas de paso con datos de clientes se borran', CASE WHEN NOT EXISTS (SELECT 1 FROM sys.tables WHERE name LIKE 'MIG[_]%') THEN 1 ELSE 0 END, NULL);

SELECT CASE OK WHEN 1 THEN 'OK   ' ELSE 'FALLA' END AS R, PRUEBA, DETALLE FROM #r ORDER BY ID;
DECLARE @f INT = (SELECT COUNT(*) FROM #r WHERE OK = 0), @t INT = (SELECT COUNT(*) FROM #r);
PRINT CONCAT('MIGRACION: ', @t - @f, ' de ', @t, ' OK');
IF @f > 0 THROW 50998, 'Hay pruebas de migración fallidas.', 1;
