/* =====================================================================
   Banbaj · Pruebas de punta a punta (asignación + actualización 486)
   Se ejecuta en una base vacía después de los scripts de la carpeta sql. Usa los archivos
   ficticios de tests/generar_datos_prueba.py montados en /datos.
   Cada verificación queda en pru.RESULTADO; al final falla si alguna falló.
   ===================================================================== */
SET NOCOUNT ON;
GO
IF SCHEMA_ID('pru') IS NULL EXEC('CREATE SCHEMA pru');
GO
DROP TABLE IF EXISTS pru.RESULTADO;
CREATE TABLE pru.RESULTADO (ID INT IDENTITY(1,1), PRUEBA NVARCHAR(200), OK BIT, DETALLE NVARCHAR(4000));
GO
CREATE OR ALTER PROCEDURE pru.sp_ok @prueba NVARCHAR(200), @ok BIT, @detalle NVARCHAR(4000) = NULL
AS INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) VALUES (@prueba, ISNULL(@ok, 0), @detalle);
GO
CREATE OR ALTER PROCEDURE pru.sp_igual @prueba NVARCHAR(200), @esperado NVARCHAR(4000), @obtenido NVARCHAR(4000)
AS
BEGIN
    DECLARE @ok BIT = CASE WHEN @esperado = @obtenido OR (@esperado IS NULL AND @obtenido IS NULL) THEN 1 ELSE 0 END;
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT @prueba, ISNULL(@ok, 0), CAST(CONCAT(N'esperado=[', @esperado, N'] obtenido=[', @obtenido, N']') AS NVARCHAR(4000));
END;
GO
/* Campo de una línea de salida por nombre */
CREATE OR ALTER FUNCTION pru.fn_campo (@linea NVARCHAR(4000), @campo VARCHAR(50))
RETURNS NVARCHAR(4000)
AS
BEGIN
    DECLARE @ini INT, @ancho INT;
    SELECT @ancho = s.ANCHO,
           @ini = 1 + ISNULL((SELECT SUM(x.ANCHO) FROM cfg.SALIDA x WHERE x.CLIENTE = '486' AND x.ARCHIVO = 'SCBSDOS' AND x.ORDEN < s.ORDEN), 0)
    FROM cfg.SALIDA s WHERE s.CLIENTE = '486' AND s.ARCHIVO = 'SCBSDOS' AND s.CAMPO = @campo;
    RETURN RTRIM(SUBSTRING(@linea, @ini, @ancho));
END;
GO

/* ---------------------------------------------------------------------
   Preparación: rutas de prueba, consecutivo, DAT inicial, histórico, exclusión
   --------------------------------------------------------------------- */
UPDATE cfg.ARCHIVO SET RUTA = '/datos/asig/', PATRON_NOMBRE = REPLACE(PATRON_NOMBRE, '.csv', '%'), CODEPAGE = ''
WHERE CLIENTE = '486' AND PROCESO = 'ASIG';
UPDATE cfg.ARCHIVO SET RUTA = '/datos/act_ok/', CODEPAGE = '' WHERE CLIENTE = '486' AND PROCESO = 'ACT';
INSERT INTO cfg.PARAMETRO (CLIENTE, CLAVE, VALOR) VALUES ('486', 'DMSTATUS_RETIRO', 'R');
INSERT INTO dat.FOLIO_CONSECUTIVO (CLIENTE, ULTIMO_FOLIO) VALUES ('486', 100000);
INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, MOTIVO) VALUES ('486', 'CUENTA', '20000008', 'Prueba de exclusión');

INSERT INTO dat.DAT_486 (FOLIO, CLIENTE, SUB_CTE, NOMBRE1, CUENTA, CUENTA2, RIESGO, DES_PROD, SEGMENTO2, TIPO, SDO_ACT, SDO_VDO,
                         PAG_MIN, SALDO1, SALDO2, SALDO3, TEL1, ETIQUETA1, PVS, TRAMO, SEG, DIRECC1, DIRECC2, DIRECC3, DIRECC4, ESTADO,
                         FE_ASIG, FE_REC, FE_REG)
VALUES
('100', '486', 'NVA', 'CLIENTE PRUEBA UNO', '1111XAXX010101000', '486-100', '1000000001', '1111XAXX010101000', 'TDC', 'TDC_VEN', 1000, 1100,
 150, 3000, 4500, 1500, '5511111111', 'MORA 1', '120', '45', 'VEN4', 'CALLE FICTICIA 1', 'Colonia Prueba', '06600', 'Ciudad Prueba', 'CDMX',
 '2026-10-01', '2026-10-01', '2026-10-31'),
('101', '486', 'NVA', 'CLIENTE PRUEBA DOS', '2222XAXX010101000', '486-101', '1000000002', '2222XAXX010101000', 'TDC', 'TDC_VEN', 800, 800,
 100, 0, 0, 0, NULL, NULL, '90', '45', 'VEN4', NULL, NULL, NULL, NULL, NULL, '2026-10-01', '2026-10-01', '2026-10-31'),
('102', '486', 'NVA', 'CLIENTE PRUEBA C1', '20000001', '486-102', '20000001', '90000001-CRN-20000001', 'CONSUMO', 'PERS_VEN', 5000, 800,
 0, 900, 1200, 400, '5511111111', NULL, '96', '90+', NULL, 'CALLE FICTICIA 2', 'Colonia Prueba', '06600', 'Ciudad Prueba', 'CDMX',
 '2026-10-01', '2026-10-01', '2026-10-31'),
('103', '486', 'NVA', 'CLIENTE PRUEBA C2', '20000002', '486-103', '20000002', '90000002-CRN-20000002', 'CONSUMO', 'PERS_VEN', 600, 60,
 0, 0, 0, 0, NULL, NULL, '96', '90+', NULL, NULL, NULL, NULL, NULL, NULL, '2026-10-01', '2026-10-01', '2026-10-31'),
('104', '486', 'NVA', 'CLIENTE PRUEBA C3', '20000003', '486-104', '20000003', '90000003-CRN-20000003', 'CONSUMO', 'PERS_VEN', 3000, 300,
 0, 900, 1200, 400, '5533333333', NULL, '96', '90+', NULL, 'CALLE FICTICIA 2', 'Colonia Prueba', '06600', 'Ciudad Prueba', 'CDMX',
 '2026-10-01', '2026-10-01', '2026-10-31');

INSERT INTO dat.HISTORIA_FOLIO (CLIENTE, CUENTA, FOLIO, CUENTA2, SEGMENTO2, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA)
VALUES ('486', '1111XAXX010101000', 100, '486-100', 'TDC', 'NVA', 'A', '2026-10-01', NULL),
       ('486', '2222XAXX010101000', 101, '486-101', 'TDC', 'NVA', 'A', '2026-10-01', NULL),
       ('486', '20000001', 102, '486-102', 'CONSUMO', 'NVA', 'A', '2026-10-01', NULL),
       ('486', '20000002', 103, '486-103', 'CONSUMO', 'NVA', 'A', '2026-10-01', NULL),
       ('486', '20000003', 104, '486-104', 'CONSUMO', 'NVA', 'A', '2026-10-01', NULL),
       ('486', '20000009', 500, '486-500', 'CONSUMO', 'NVA', 'B', '2025-01-10', '2025-06-30');
GO

/* ---------------------------------------------------------------------
   Funciones
   --------------------------------------------------------------------- */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_importe con $ y miles' AS p, CAST(N'1234.50' AS NVARCHAR(4000)) AS e, CAST(CONVERT(NVARCHAR(30), cfg.fn_importe(N'$1,234.50')) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_importe cero contable de Excel' AS p, CAST(N'0.00' AS NVARCHAR(4000)) AS e, CAST(CONVERT(NVARCHAR(30), cfg.fn_importe(N' -   ')) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_importe con espacios' AS p, CAST(N'12345.67' AS NVARCHAR(4000)) AS e, CAST(CONVERT(NVARCHAR(30), cfg.fn_importe(N' 12,345.67 ')) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_importe inválido -> NULL' AS p, CAST(NULL AS NVARCHAR(4000)) AS e, CAST(CONVERT(NVARCHAR(30), cfg.fn_importe(N'abc')) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_fecha AAAA-MM-DD con hora' AS p, CAST(N'2026-10-25' AS NVARCHAR(4000)) AS e, CAST(CONVERT(NVARCHAR(10), cfg.fn_fecha(N'2026-10-25 00:00:00.0', 'AAAA-MM-DD'), 23) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_fecha AAAAMMDD' AS p, CAST(N'2026-11-02' AS NVARCHAR(4000)) AS e, CAST(CONVERT(NVARCHAR(10), cfg.fn_fecha(N'20261102', 'AAAAMMDD'), 23) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_pad_importe legado (negativo sale positivo)' AS p, CAST(N'000000000012.50' AS NVARCHAR(4000)) AS e, CAST(cfg.fn_pad_importe(-12.50, 15, 'ABS_LEGADO') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_pad_importe con signo' AS p, CAST(N'-00000000012.50' AS NVARCHAR(4000)) AS e, CAST(cfg.fn_pad_importe(-12.50, 15, 'SIGNO') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_cp_estado' AS p, CAST(N'GTO' AS NVARCHAR(4000)) AS e, CAST(cfg.fn_cp_estado('37236') AS NVARCHAR(4000)) AS o) x;
GO

/* ---------------------------------------------------------------------
   Correo dinámico
   --------------------------------------------------------------------- */
DECLARE @r TABLE (PARA NVARCHAR(MAX), CC NVARCHAR(MAX), CCO NVARCHAR(MAX), ASUNTO NVARCHAR(255), CUERPO_HTML NVARCHAR(MAX), ADJUNTOS NVARCHAR(MAX));
INSERT INTO @r EXEC mail.sp_enviar @plantilla = 'PAGOS_NO_ACTUALIZADOS_486', @solo_prueba = 1;
DECLARE @para NVARCHAR(MAX), @cco NVARCHAR(MAX), @cuerpo NVARCHAR(MAX);
SELECT @para = PARA, @cco = CCO, @cuerpo = CUERPO_HTML FROM @r;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Correo: TO armado desde la tabla', ISNULL(CASE WHEN @para LIKE N'%erika.ramos@sertec.com.mx%' THEN 1 ELSE 0 END, 0), CAST(@para AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Correo: BCC armado desde la tabla', ISNULL(CASE WHEN @cco LIKE N'%asig.cdmx@sertec.com.mx%' THEN 1 ELSE 0 END, 0), CAST(@cco AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Correo: firma y aviso insertados', ISNULL(CASE WHEN @cuerpo NOT LIKE N'%{{%' AND @cuerpo LIKE N'%SERTEC%' THEN 1 ELSE 0 END, 0), CAST(LEFT(@cuerpo, 300) AS NVARCHAR(4000));

EXEC mail.sp_destinatario_alta 'PAGOS_NO_ACTUALIZADOS_486', 'Nuevo.Correo@Sertec.com.mx', 'CC';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Correo: alta de destinatario' AS p, CAST(N'nuevo.correo@sertec.com.mx' AS NVARCHAR(4000)) AS e, CAST((SELECT CC FROM mail.v_LISTA_RESUELTA WHERE LISTA = 'PAGOS_NO_ACTUALIZADOS_486') AS NVARCHAR(4000)) AS o) x;
EXEC mail.sp_destinatario_baja 'PAGOS_NO_ACTUALIZADOS_486', 'nuevo.correo@sertec.com.mx';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Correo: baja de destinatario' AS p, CAST(NULL AS NVARCHAR(4000)) AS e, CAST((SELECT CC FROM mail.v_LISTA_RESUELTA WHERE LISTA = 'PAGOS_NO_ACTUALIZADOS_486') AS NVARCHAR(4000)) AS o) x;
GO

/* ---------------------------------------------------------------------
   ASIGNACIÓN 1: la devolución supera el tope -> se cancela
   --------------------------------------------------------------------- */
UPDATE cfg.PARAMETRO SET VALOR = '10' WHERE CLIENTE = '486' AND CLAVE = 'TOPE_DEVOLUCION_PCT';
DECLARE @id INT;
BEGIN TRY
    EXEC ops.sp_asignacion_486 @fecha = '2026-11-02', @hora_llegada = '09:15', @id_corrida = @id OUTPUT;
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Asignación con devolución masiva debe detenerse', ISNULL(0, 0), CAST(N'No se detuvo' AS NVARCHAR(4000));
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
    FROM (SELECT N'Asignación con devolución masiva: error 50100' AS p, CAST(N'50100' AS NVARCHAR(4000)) AS e, CAST(CAST(ERROR_NUMBER() AS NVARCHAR(10)) AS NVARCHAR(4000)) AS o) x;
END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Asignación cancelada: estatus de la corrida' AS p, CAST(N'CANCELADA' AS NVARCHAR(4000)) AS e, CAST((SELECT TOP (1) ESTATUS FROM ops.CORRIDA WHERE PROCESO = 'ASIG' ORDER BY ID_CORRIDA DESC) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Asignación cancelada: el DAT no cambió' AS p, CAST(N'5' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM dat.DAT_486) AS NVARCHAR(4000)) AS o) x;
GO

/* ---------------------------------------------------------------------
   ASIGNACIÓN 2: sin tope, aplicando el retiro
   --------------------------------------------------------------------- */
UPDATE cfg.PARAMETRO SET VALOR = '' WHERE CLIENTE = '486' AND CLAVE = 'TOPE_DEVOLUCION_PCT';   -- la base se trabaja como llega
DECLARE @id INT;
BEGIN TRY
    EXEC ops.sp_asignacion_486 @fecha = '2026-11-02', @hora_llegada = '09:15', @aplicar_retiro = 1,
         @id_corrida = @id OUTPUT;
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Asignación termina OK', ISNULL(1, 0), CAST(NULL AS NVARCHAR(4000));
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Asignación termina OK', ISNULL(0, 0), CAST(ERROR_MESSAGE() AS NVARCHAR(4000));
END CATCH;
SET @id = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ASIG');

INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: archivos cargados' AS p, CAST(N'2' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM ops.ARCHIVO_CARGADO WHERE ID_CORRIDA = @id AND ESTATUS = 'CARGADO') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ASIG: rechazo por saldo inválido (abc)', ISNULL(CASE WHEN EXISTS (SELECT 1 FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'MAESTRA_TDC' AND MOTIVO LIKE N'%SDO_ACT%') THEN 1 ELSE 0 END, 0), CAST(NULL AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ASIG: rechazo por cuenta duplicada', ISNULL(CASE WHEN EXISTS (SELECT 1 FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND MOTIVO LIKE N'%duplicada%') THEN 1 ELSE 0 END, 0), CAST(NULL AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ASIG: cuenta excluida (exc486)', ISNULL(CASE WHEN EXISTS (SELECT 1 FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'EXCLUSION_CUENTAS')
           AND NOT EXISTS (SELECT 1 FROM dat.DAT_486 WHERE CUENTA = '20000008') THEN 1 ELSE 0 END, 0), CAST(NULL AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ASIG: alerta por saldo <= 0 en Consumo', ISNULL(CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'SDO_ACT_CONSUMO_CERO') THEN 1 ELSE 0 END, 0), CAST(NULL AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: devoluciones por segmento (C2 y T2)' AS p, CAST(N'20000002,2222XAXX010101000' AS NVARCHAR(4000)) AS e, CAST((SELECT STRING_AGG(CUENTA, ',') WITHIN GROUP (ORDER BY CUENTA) FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: DAT final (3 existentes + 4 NVA + 1 REA)' AS p, CAST(N'8' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM dat.DAT_486) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: folios NVA consecutivos' AS p, CAST(N'20000004:100001,20000005:100002,3333XAXX010101000:100003,4444XAXX010101000:100004' AS NVARCHAR(4000)) AS e, CAST((SELECT STRING_AGG(CONCAT(CUENTA, ':', FOLIO), ',') WITHIN GROUP (ORDER BY FOLIO) FROM dat.DAT_486 WHERE SUB_CTE = 'NVA' AND ID_CORRIDA_ALTA = @id) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: consecutivo actualizado' AS p, CAST(N'100004' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(ULTIMO_FOLIO AS NVARCHAR(10)) FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = '486') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: REA reutiliza folio del histórico' AS p, CAST(N'REA|486-500' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(SUB_CTE, '|', CUENTA2) FROM dat.DAT_486 WHERE CUENTA = '20000009') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: existente actualiza teléfono y etiqueta' AS p, CAST(N'5599999999|MORA 2' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(TEL1, '|', ETIQUETA1) FROM dat.DAT_486 WHERE CUENTA = '1111XAXX010101000') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: existente sin cambios no se toca' AS p, CAST(NULL AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(ID_CORRIDA_ULT AS NVARCHAR(10)) FROM dat.DAT_486 WHERE CUENTA = '20000003') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: TDC saldo <= 0 toma SDO_VDO y TIPO por tramo' AS p, CAST(N'750.00|TDC_VEN' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(SDO_ACT, '|', TIPO) FROM dat.DAT_486 WHERE CUENTA = '3333XAXX010101000') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: TDC castigada' AS p, CAST(N'TDC_CAS' AS NVARCHAR(4000)) AS e, CAST((SELECT TIPO FROM dat.DAT_486 WHERE CUENTA = '4444XAXX010101000') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: Consumo importe con $, CP de 4 dígitos, homologación' AS p, CAST(N'1234.50|06600|NOMINA|NOMINA_VIG|400.00' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(SDO_ACT, '|', DIRECC3, '|', ESTRA3, '|', TIPO, '|', SALDO3) FROM dat.DAT_486 WHERE CUENTA = '20000004') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: histórico de bajas (retiro)' AS p, CAST(N'2' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_BAJA = @id AND ESTATUS = 'B' AND DATOS_BAJA IS NOT NULL) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: script de retiro para CYBER' AS p, CAST(N'update RCVRY.delqmst set dmstatus=''R'' where dmacctg=''1'' and dmacct=''486-101'';' AS NVARCHAR(4000)) AS e, CAST((SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'RETIRO' AND NUM = 1) AS NVARCHAR(4000)) AS o) x;

DECLARE @lin NVARCHAR(4000) = (SELECT l.LINEA FROM ops.SALIDA_LINEA l WHERE l.ID_CORRIDA = @id AND l.ARCHIVO = 'SCBSDOS'
                               AND l.LINEA LIKE N'____486-100001 %');
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: líneas generadas' AS p, CAST(N'8' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: todas miden 1559' AS p, CAST(N'0' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS' AND DATALENGTH(LINEA) / 2 <> 1559) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: DMCURBAL' AS p, CAST(N'000000001234.50' AS NVARCHAR(4000)) AS e, CAST(pru.fn_campo(@lin, 'DMCURBAL') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: DMZIP y DMSTATE' AS p, CAST(N'06600|CDMX' AS NVARCHAR(4000)) AS e, CAST(CONCAT(pru.fn_campo(@lin, 'DMZIP'), '|', pru.fn_campo(@lin, 'DMSTATE')) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: U1ASIGDTE MMDDAAAA' AS p, CAST(N'11022026' AS NVARCHAR(4000)) AS e, CAST(pru.fn_campo(@lin, 'U1ASIGDTE') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: U1FTECAR y DMCOMPANY' AS p, CAST(N'BANCO BAJIO|486' AS NVARCHAR(4000)) AS e, CAST(CONCAT(pru.fn_campo(@lin, 'U1FTECAR'), '|', pru.fn_campo(@lin, 'DMCOMPANY')) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: U1MINASIG con signo' AS p, CAST(N'000000000400.00' AS NVARCHAR(4000)) AS e, CAST(pru.fn_campo(@lin, 'U1MINASIG') AS NVARCHAR(4000)) AS o) x;
GO

/* ---------------------------------------------------------------------
   ETIQUETAS TOP (las alimenta Asignaciones con folio + etiqueta de Operación)
   --------------------------------------------------------------------- */
DECLARE @r TABLE (TIPO VARCHAR(20), MODO VARCHAR(10), LEIDOS INT, CARGADOS INT, SIN_DATO INT, REPETIDOS INT, NO_DAT INT);
INSERT INTO @r EXEC cfg.sp_etiqueta_cargar '486', 'TOP', '/datos/etiquetas/TOP.csv', 'REEMPLAZAR', 'FOLIO', '';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'TOP: leídos|cargados|sin dato|repetidos|fuera del DAT' AS p, N'5|3|1|1|1' AS e,
             (SELECT CONCAT(LEIDOS, '|', CARGADOS, '|', SIN_DATO, '|', REPETIDOS, '|', NO_DAT) FROM @r) AS o) x;

DECLARE @id INT = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ASIG' AND ESTATUS = 'OK');
EXEC ops.sp_generar_salida @id, 'SCBSDOS';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'TOP: U1EXT2 en SCBSDOS por folio (con y sin 486-)' AS p, N'REE|REE|' AS e,
             CONCAT((SELECT pru.fn_campo(LINEA, 'U1EXT2') FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS' AND LINEA LIKE N'____486-100001 %'), '|',
                    (SELECT pru.fn_campo(LINEA, 'U1EXT2') FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS' AND LINEA LIKE N'____486-100003 %'), '|',
                    (SELECT pru.fn_campo(LINEA, 'U1EXT2') FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS' AND LINEA LIKE N'____486-100002 %')) AS o) x;

EXEC cfg.sp_etiqueta_baja '486', 'TOP', '100003';
EXEC cfg.sp_etiqueta_alta '486', 'TOP', '486-100002', 'REE';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'TOP: baja y alta sueltas' AS p, N'486-100001,486-100002,486-999999' AS e,
             (SELECT STRING_AGG(LLAVE, ',') WITHIN GROUP (ORDER BY LLAVE) FROM cfg.ETIQUETA WHERE TIPO = 'TOP' AND ACTIVO = 1) AS o) x;
GO

/* ---------------------------------------------------------------------
   ACTUALIZACIÓN: saldos, pagos y retiros
   --------------------------------------------------------------------- */
DECLARE @id INT;
BEGIN TRY
    EXEC ops.sp_actualizacion_486 @fecha = '2026-11-03', @aplicar_retiro = 1, @id_corrida = @id OUTPUT;
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Actualización termina OK', ISNULL(1, 0), CAST(NULL AS NVARCHAR(4000));
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Actualización termina OK', ISNULL(0, 0), CAST(ERROR_MESSAGE() AS NVARCHAR(4000));
END CATCH;
SET @id = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ACT');

INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ACT: no hay alerta de pagos T-1 (sí vienen pagos de ayer)', ISNULL(CASE WHEN NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'PAGOS_T1') THEN 1 ELSE 0 END, 0), CAST(NULL AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ACT: saldo de cuenta que no está en el DAT va a rechazos', ISNULL(CASE WHEN EXISTS (SELECT 1 FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'SALDOS_TDC' AND MOTIVO LIKE N'%DAT%') THEN 1 ELSE 0 END, 0), CAST(NULL AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: devoluciones (T1 NORM, C3 tramo 0, C4 saldo 0, C5 DAT en 0)' AS p, CAST(N'1111XAXX010101000,20000003,20000004,20000005' AS NVARCHAR(4000)) AS e, CAST((SELECT STRING_AGG(CUENTA, ',') WITHIN GROUP (ORDER BY CUENTA) FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: Consumo actualizado (saldo con miles, vencido, PVS)' AS p, CAST(N'12345.67|2000.00|120|90+' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(SDO_ACT, '|', SDO_VDO, '|', PVS, '|', SEG) FROM dat.DAT_486 WHERE CUENTA = '20000001') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: TDC actualiza saldo y conserva SDO_VDO (el archivo no lo trae)' AS p, CAST(N'900.50|750.00|VEN4' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(SDO_ACT, '|', SDO_VDO, '|', SEG) FROM dat.DAT_486 WHERE CUENTA = '3333XAXX010101000') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: script DMCURBAL' AS p, CAST(N'update RCVRY.delqmst set DMCURBAL=''000000012345.67'' ,dmbphone=''90+'' Where dmacctg=''1'' And dmacct=''486-102'';' AS NVARCHAR(4000)) AS e, CAST((SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'ACT_SALDOS' AND SENTENCIA LIKE N'%486-102''%') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: dmamtdlq solo para quien trae vencido (3 + commit + exit)' AS p, CAST(N'5' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'ACT_VENCIDO') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: cada script termina en commit y exit' AS p, CAST(N'commit;|exit;' AS NVARCHAR(4000)) AS e, CAST((SELECT STRING_AGG(SENTENCIA, '|') WITHIN GROUP (ORDER BY NUM) FROM (SELECT TOP (2) SENTENCIA, NUM FROM ops.CYBER_SCRIPT
      WHERE ID_CORRIDA = @id AND SCRIPT = 'ACT_PAGMIN' ORDER BY NUM DESC) x) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: pagos nuevos (duplicado y crédito inexistente fuera)' AS p, CAST(N'486-100001:500.00,486-102:1000.00' AS NVARCHAR(4000)) AS e, CAST((SELECT STRING_AGG(CONCAT(CUENTA2, ':', IMPORTE), ',') WITHIN GROUP (ORDER BY CUENTA2) FROM ops.PAGO WHERE ID_CORRIDA = @id) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: DAT después del retiro' AS p, CAST(N'4' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM dat.DAT_486) AS NVARCHAR(4000)) AS o) x;
GO

/* Segunda actualización con los mismos pagos: no se duplican */
DECLARE @id INT;
BEGIN TRY
    EXEC ops.sp_actualizacion_486 @fecha = '2026-11-03', @id_corrida = @id OUTPUT;
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Segunda actualización termina OK', ISNULL(0, 0), CAST(ERROR_MESSAGE() AS NVARCHAR(4000));
END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT 2: pagos no se registran dos veces' AS p, CAST(N'2' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM ops.PAGO) AS NVARCHAR(4000)) AS o) x;
GO

/* Pagos negativos: la actualización se cancela */
UPDATE cfg.ARCHIVO SET RUTA = '/datos/act_neg/' WHERE CLIENTE = '486' AND PROCESO = 'ACT';
DECLARE @id INT;
BEGIN TRY
    EXEC ops.sp_actualizacion_486 @fecha = '2026-11-03', @id_corrida = @id OUTPUT;
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Pagos negativos deben cancelar', ISNULL(0, 0), CAST(N'No se canceló' AS NVARCHAR(4000));
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
    FROM (SELECT N'Pagos negativos cancelan la actualización' AS p, CAST(N'CANCELADA' AS NVARCHAR(4000)) AS e, CAST((SELECT TOP (1) ESTATUS FROM ops.CORRIDA WHERE PROCESO = 'ACT' ORDER BY ID_CORRIDA DESC) AS NVARCHAR(4000)) AS o) x;
END CATCH;
GO

/* ---------------------------------------------------------------------
   RETROCESO: corridas 5, 4 y 3 (actualizaciones) y luego la 2 (asignación)
   --------------------------------------------------------------------- */
BEGIN TRY
    EXEC ops.sp_revertir_corrida 3, 1;
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) VALUES (N'Retroceso fuera de orden debe rechazarse', 0, N'Se permitió');
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Retroceso fuera de orden se rechaza (50304)', CASE WHEN ERROR_NUMBER() = 50304 THEN 1 ELSE 0 END, ERROR_MESSAGE();
END CATCH;
GO
BEGIN TRY
    EXEC ops.sp_revertir_corrida 5, 1;
    EXEC ops.sp_revertir_corrida 4, 1;
    EXEC ops.sp_revertir_corrida 3, 1;
    INSERT INTO pru.RESULTADO (PRUEBA, OK) VALUES (N'Retroceso de las tres actualizaciones', 1);
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) VALUES (N'Retroceso de las tres actualizaciones', 0, ERROR_MESSAGE());
END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Retroceso ACT: DAT como después de la asignación' AS p, N'8|0|1000.00|5000.00' AS e,
             CONCAT((SELECT COUNT(*) FROM dat.DAT_486), '|', (SELECT COUNT(*) FROM ops.PAGO), '|',
                    (SELECT SDO_ACT FROM dat.DAT_486 WHERE CUENTA = '1111XAXX010101000'), '|',
                    (SELECT SDO_ACT FROM dat.DAT_486 WHERE CUENTA = '20000001')) AS o) x;
GO
BEGIN TRY
    EXEC ops.sp_revertir_corrida 2, 0;     -- vista previa: no cambia nada
    EXEC ops.sp_revertir_corrida 2, 1;
    INSERT INTO pru.RESULTADO (PRUEBA, OK) VALUES (N'Retroceso de la asignación', 1);
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) VALUES (N'Retroceso de la asignación', 0, ERROR_MESSAGE());
END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Retroceso ASIG: DAT, consecutivo e histórico como al inicio' AS p, N'5|100000|A|B|1|REVERTIDA' AS e,
             CONCAT((SELECT COUNT(*) FROM dat.DAT_486), '|',
                    (SELECT ULTIMO_FOLIO FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = '486'), '|',
                    (SELECT ESTATUS FROM dat.HISTORIA_FOLIO WHERE CUENTA = '2222XAXX010101000'), '|',
                    (SELECT STRING_AGG(ESTATUS, ',') FROM dat.HISTORIA_FOLIO WHERE CUENTA = '20000009'), '|',
                    (SELECT COUNT(*) FROM dat.HISTORIA_FOLIO WHERE CUENTA = '20000009'), '|',
                    (SELECT ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = 2)) AS o) x;
GO

/* ---------------------------------------------------------------------
   Resultado
   --------------------------------------------------------------------- */
SELECT CASE OK WHEN 1 THEN 'OK   ' ELSE 'FALLA' END AS R, PRUEBA, DETALLE FROM pru.RESULTADO ORDER BY ID;
DECLARE @fallas INT = (SELECT COUNT(*) FROM pru.RESULTADO WHERE OK = 0), @total INT = (SELECT COUNT(*) FROM pru.RESULTADO);
PRINT CONCAT('PRUEBAS: ', @total - @fallas, ' de ', @total, ' OK');
IF @fallas > 0
BEGIN
    SELECT TOP (60) b.ID_CORRIDA, b.PASO, b.ESTATUS, b.REGISTROS, LEFT(b.MENSAJE, 300) AS MENSAJE FROM ops.BITACORA b ORDER BY b.ID;
    THROW 50999, 'Hay pruebas fallidas.', 1;
END;
GO
