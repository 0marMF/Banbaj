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
INSERT INTO dat.FOLIO_CONSECUTIVO (CLIENTE, ULTIMO_FOLIO) VALUES ('486', 100000);
/* El escenario de prueba corre la asignación antes que la actualización; el candado se prueba aparte */
UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486' AND CLAVE = 'ASIG_REQUIERE_ACT';
INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, MOTIVO) VALUES ('486', 'CUENTA', '20000008', 'Prueba de exclusión');
INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO) VALUES ('486', 'TELEFONO', '5533333333', '486-104', 'Prueba de queja (TELBAJ)');
INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO) VALUES ('486', 'CORREO', 'malo@correo.com', '20000009', 'Prueba de EMAILMALO');
INSERT INTO cfg.PLAN_NUMERACION (LADA, SERIE, N_INI, N_FIN, TIPORED)
VALUES ('55', '1111', 0, 9999, 'MOVIL'), ('477', '123', 4000, 4999, 'MOVIL'), ('477', '123', 0, 3999, 'FIJO'), ('477', '700', 0, 9999, 'FIJO'),
       ('55', '9999', 0, 9999, 'FIJO'), ('55', '7777', 0, 9999, 'FIJO'), ('55', '4444', 0, 9999, 'FIJO');

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

/* Teléfonos de prueba en TEL14..TEL16 (no se tocan al actualizar existentes) */
UPDATE dat.DAT_486 SET TEL14 = '4771234567', TEL15 = '477-700-1234', TEL16 = '4777140350' WHERE CUENTA = '1111XAXX010101000';
UPDATE dat.DAT_486 SET TEL14 = '55-4444-5555', TEL15 = '044 551111 1111', TEL16 = '12345' WHERE CUENTA = '20000003';

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
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Negativos en cero (decisión 30/10: el saldo <= 0 se retira)' AS p, CAST(N'CERO|000000000000.00|000000000012.50' AS NVARCHAR(4000)) AS e,
             CAST(CONCAT(cfg.fn_param('486', 'NEGATIVO_MODO'), '|', cfg.fn_pad_importe(-12.50, 15, cfg.fn_param('486', 'NEGATIVO_MODO')), '|',
                         cfg.fn_pad_importe(12.50, 15, cfg.fn_param('486', 'NEGATIVO_MODO'))) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_cp_estado' AS p, CAST(N'GTO' AS NVARCHAR(4000)) AS e, CAST(cfg.fn_cp_estado('37236') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_ruta: carpeta del día con mes en español' AS p, N'Q:\CYBER\C_486\2026\octubre\28\|Q:\CYBER\C_486\2027\enero\05\' AS e,
             CONCAT((SELECT RUTA FROM (SELECT DISTINCT cfg.fn_ruta(N'Q:\CYBER\C_486\{AAAA}\{MES}\{DD}\', '2026-10-28') AS RUTA) r), '|',
                    cfg.fn_ruta(N'Q:\CYBER\C_486\{AAAA}\{MES}\{DD}\', '2027-01-05')) AS o) x;
GO

/* Flujo diario: día hábil anterior, fin de semana, archivos presentes y candado ACT -> ASIG */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'fn_dia_habil_anterior (lunes -> viernes) y fin de semana' AS p, N'2026-10-30|2026-11-02|2026-11-06|1|0' AS e,
             CONCAT(CONVERT(CHAR(10), cfg.fn_dia_habil_anterior('2026-11-02'), 23), '|', CONVERT(CHAR(10), cfg.fn_dia_habil_anterior('2026-11-03'), 23), '|',
                    CONVERT(CHAR(10), cfg.fn_dia_habil_anterior('2026-11-08'), 23), '|', cfg.fn_es_fin_de_semana('2026-11-07'), '|', cfg.fn_es_fin_de_semana('2026-11-06')) AS o) x;
DECLARE @na INT, @ns INT;
EXEC ops.sp_archivos_presentes '486', 'ACT', '2026-11-03', @na OUTPUT;
EXEC ops.sp_archivos_presentes '486', 'ASIG', '2026-11-02', @ns OUTPUT;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Archivos presentes: 3 de actualización, 2 maestras', CASE WHEN @na = 3 AND @ns = 2 THEN 1 ELSE 0 END, CONCAT(@na, '|', @ns);
DECLARE @d TABLE (RESULTADO VARCHAR(60));
INSERT INTO @d EXEC ops.sp_diario_486 '2026-11-07';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Diario: fin de semana no corre', CASE WHEN (SELECT RESULTADO FROM @d) = 'FIN DE SEMANA' THEN 1 ELSE 0 END, (SELECT RESULTADO FROM @d);
UPDATE cfg.PARAMETRO SET VALOR = '1' WHERE CLIENTE = '486' AND CLAVE = 'ASIG_REQUIERE_ACT';
BEGIN TRY
    EXEC ops.sp_asignacion_486 @fecha = '2026-11-09';
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) VALUES (N'Candado: asignación sin actualización del día debe detenerse', 0, N'No se detuvo');
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Candado: asignación sin actualización del día se detiene (50110) sin abrir corrida',
           CASE WHEN ERROR_NUMBER() = 50110 AND NOT EXISTS (SELECT 1 FROM ops.CORRIDA) THEN 1 ELSE 0 END, ERROR_MESSAGE();
END CATCH;
UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486' AND CLAVE = 'ASIG_REQUIERE_ACT';
GO

/* ---------------------------------------------------------------------
   Correo dinámico
   --------------------------------------------------------------------- */
DECLARE @r TABLE (PARA NVARCHAR(MAX), CC NVARCHAR(MAX), CCO NVARCHAR(MAX), ASUNTO NVARCHAR(255), CUERPO_HTML NVARCHAR(MAX), ADJUNTOS NVARCHAR(MAX));
INSERT INTO @r EXEC mail.sp_enviar @plantilla = 'CONFIRMACION_ASIG_486', @valores = N'{"RESUMEN":"Archivos: 2"}', @solo_prueba = 1;
DECLARE @para NVARCHAR(MAX), @cco NVARCHAR(MAX), @cuerpo NVARCHAR(MAX);
SELECT @para = PARA, @cco = CCO, @cuerpo = CUERPO_HTML FROM @r;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Correo: TO armado desde la tabla', ISNULL(CASE WHEN @para LIKE N'%erika.ramos@sertec.com.mx%' THEN 1 ELSE 0 END, 0), CAST(@para AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Correo: BCC armado desde la tabla', ISNULL(CASE WHEN @cco LIKE N'%asig.cdmx@sertec.com.mx%' THEN 1 ELSE 0 END, 0), CAST(@cco AS NVARCHAR(4000));
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Correo: firma y aviso insertados', ISNULL(CASE WHEN @cuerpo NOT LIKE N'%{{%' AND @cuerpo LIKE N'%SERTEC%' THEN 1 ELSE 0 END, 0), CAST(LEFT(@cuerpo, 300) AS NVARCHAR(4000));

EXEC mail.sp_destinatario_alta 'OPERACION_ASIG_486', 'Nuevo.Correo@Sertec.com.mx', 'CC';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Correo: alta de destinatario' AS p, CAST(N'nuevo.correo@sertec.com.mx' AS NVARCHAR(4000)) AS e, CAST((SELECT CC FROM mail.v_LISTA_RESUELTA WHERE LISTA = 'OPERACION_ASIG_486') AS NVARCHAR(4000)) AS o) x;
EXEC mail.sp_destinatario_baja 'OPERACION_ASIG_486', 'nuevo.correo@sertec.com.mx';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Correo: baja de destinatario' AS p, CAST(NULL AS NVARCHAR(4000)) AS e, CAST((SELECT CC FROM mail.v_LISTA_RESUELTA WHERE LISTA = 'OPERACION_ASIG_486') AS NVARCHAR(4000)) AS o) x;
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
DECLARE @c1 INT = (SELECT TOP (1) ID_CORRIDA FROM ops.CORRIDA WHERE PROCESO = 'ASIG' ORDER BY ID_CORRIDA DESC);
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Retroceso automático: la corrida cancelada conserva su estatus y no deja base maestra' AS p, N'CANCELADA|1|1|0' AS e,
             CONCAT((SELECT ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = @c1), '|',
                    (SELECT CAST(REVERTIDA_AUTO AS INT) FROM ops.CORRIDA WHERE ID_CORRIDA = @c1), '|',
                    (SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @c1 AND PASO = 'RETROCESO' AND ESTATUS = 'OK'), '|',
                    (SELECT COUNT(*) FROM dat.BASE_RECIBIDA_ARCHIVO WHERE ID_CORRIDA = @c1)) AS o) x;
/* Una base anterior de TDC (ficticia) para probar que el retroceso la devuelve a vigente */
INSERT INTO dat.BASE_RECIBIDA_ARCHIVO (ID_CORRIDA, CODIGO, CLIENTE, ARCHIVO, ENCABEZADOS, REGISTROS, VIGENTE)
VALUES (0, 'MAESTRA_TDC', '486', N'BASE MAESTRA_TARJETA anterior.csv', N'[]', 0, 1);
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
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: base maestra vigente y anterior por segmento' AS p, N'0|1' AS e,
             CONCAT((SELECT CAST(VIGENTE AS INT) FROM dat.BASE_RECIBIDA_ARCHIVO WHERE ID_CORRIDA = 0 AND CODIGO = 'MAESTRA_TDC'), '|',
                    (SELECT CAST(VIGENTE AS INT) FROM dat.BASE_RECIBIDA_ARCHIVO WHERE ID_CORRIDA = @id AND CODIGO = 'MAESTRA_TDC')) AS o) x;
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
FROM (SELECT N'ASIG: TDC castigada y NAME2 "-" toma NAME1 (macro)' AS p, CAST(N'TDC_CAS|CLIENTE PRUEBA CUATRO' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(TIPO, '|', NOMBRE1) FROM dat.DAT_486 WHERE CUENTA = '4444XAXX010101000') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: Consumo importe con $, CP de 4 dígitos, homologación' AS p, CAST(N'1234.50|06600|NOMINA|NOMINA_VIG|400.00' AS NVARCHAR(4000)) AS e, CAST((SELECT CONCAT(SDO_ACT, '|', DIRECC3, '|', ESTRA3, '|', TIPO, '|', SALDO3) FROM dat.DAT_486 WHERE CUENTA = '20000004') AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: histórico de bajas (retiro)' AS p, CAST(N'2' AS NVARCHAR(4000)) AS e, CAST((SELECT CAST(COUNT(*) AS NVARCHAR(10)) FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_BAJA = @id AND ESTATUS = 'B' AND DATOS_BAJA IS NOT NULL) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: archivo de devolución para CYBER (CUENTA2)' AS p, N'486-101,486-103' AS e,
             (SELECT STRING_AGG(RTRIM(LINEA), ',') WITHIN GROUP (ORDER BY NUM) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'DEVOL_CYBER') AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ASIG: script de retiro para CYBER' AS p, CAST(N'update RCVRY.delqmst set dmstatus=''R'' where dmacctg=''1'' and dmacct=''486-101'';' AS NVARCHAR(4000)) AS e, CAST((SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'RETIRO' AND NUM = 1) AS NVARCHAR(4000)) AS o) x;

/* Teléfonos (telbnx.prg): limpieza, celular por plan de numeración, lada de 2 y 3 dígitos, banco, queja, repetidos */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'TEL: sub_mst (CUENTA|AREA|TELEFONO|TIPOTEL)' AS p,
             N'486-100|01477|7001234|4,486-100|0155|99999999|1,486-100|045|4771234567|5,486-100003|045|4771234567|5,486-102|0155|77777777|1,486-104|0155|44445555|4,486-104|044|5511111111|5' AS e,
             (SELECT STRING_AGG(LINEA, ',') WITHIN GROUP (ORDER BY NUM) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'TEL_SUBMST') AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'TEL: SCBTEL 7 líneas de 137 con fecha y gestor' AS p, N'7|0|11022026|HOSP' AS e,
             CONCAT((SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBTEL'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBTEL' AND DATALENGTH(LINEA) / 2 <> 137), '|',
                    (SELECT SUBSTRING(LINEA, 82, 8) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBTEL' AND NUM = 1), '|',
                    (SELECT SUBSTRING(LINEA, 99, 4) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBTEL' AND NUM = 1)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'TEL: bitácora (quejas TELBAJ) y scripts de CYBER (vaciar remesa y procedimiento)' AS p, N'1|TRUNCATE TABLE RCVRY.JSP_TAB_TEL_REMESA_486;|EXECUTE RCVRY.JSP_TELEFONOS_REMESA_486;' AS e,
             CONCAT((SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'TELEFONOS' AND MENSAJE LIKE N'%quejas (TELBAJ): 1 %'), '|',
                    (SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'TEL_BORRA' AND NUM = 1), '|',
                    (SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'TEL_ACTUALIZA' AND NUM = 1)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'TEL: renglón del día en JSP_VALIDADOR_TELEFONOS con el total enviado',
       CASE WHEN SENTENCIA LIKE N'INSERT INTO RCVRY.JSP_VALIDADOR_TELEFONOS (CLIENTE, FECHA, TOTAL_TELS) SELECT ''486'', SYSDATE, 7 FROM DUAL WHERE NOT EXISTS%' THEN 1 ELSE 0 END, SENTENCIA
FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'TEL_BORRA' AND NUM = 2;

/* Arribo automático a CYBER (02/11): bloques PL/SQL, remesas sin sqlldr y detección de SCBSDOS / SCBTEL subidos */
DECLARE @pl TABLE (SCRIPT VARCHAR(40), BLOQUE INT, PLSQL NVARCHAR(MAX));
INSERT INTO @pl EXEC ops.sp_arribar_cyber @id, 'TELEFONOS', @solo_mostrar = 1;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ARRIBO TEL: TRUNCATE con EXECUTE IMMEDIATE, remesa con INSERT y procedimiento en bloque PL/SQL' AS p, N'1|1|1|7|1' AS e,
             CONCAT((SELECT COUNT(*) FROM @pl WHERE SCRIPT = 'TEL_BORRA' AND PLSQL LIKE N'BEGIN EXECUTE IMMEDIATE ''TRUNCATE TABLE RCVRY.JSP_TAB_TEL_REMESA_486''; INSERT INTO RCVRY.JSP_VALIDADOR_TELEFONOS%COMMIT; END;'), '|',
                    (SELECT COUNT(*) FROM @pl WHERE SCRIPT = 'TEL_REMESA' AND PLSQL LIKE N'%INSERT INTO RCVRY.JSP_TAB_TEL_REMESA_486 (CUENTA,AREA,TELEFONO,TIPOTEL) VALUES (''486-100'', ''01477'', ''7001234'', ''4'');%'), '|',
                    (SELECT COUNT(*) FROM @pl WHERE SCRIPT = 'TEL_ACTUALIZA' AND PLSQL = N'BEGIN RCVRY.JSP_TELEFONOS_REMESA_486; COMMIT; END;'), '|',
                    (SELECT COUNT(*) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'TEL_REMESA'), '|',
                    (SELECT COUNT(*) FROM @pl WHERE PLSQL LIKE N'%exit%' OR PLSQL LIKE N'%EXIT%')  + 1) AS o) x;
DELETE FROM @pl;
INSERT INTO @pl EXEC ops.sp_arribar_cyber @id, 'CORREOS', @solo_mostrar = 1;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ARRIBO CORREOS: bandera, remesa y JSP_CORREOS_486 en orden' AS p, N'MAIL_ACTIVA_BANDERA,MAIL_BORRA,MAIL_REMESA,MAIL_ACTUALIZA,MAIL_INACTIVA_BANDERA|1' AS e,
             CONCAT((SELECT STRING_AGG(SCRIPT, ',') WITHIN GROUP (ORDER BY O) FROM (SELECT DISTINCT SCRIPT, CASE SCRIPT WHEN 'MAIL_ACTIVA_BANDERA' THEN 1 WHEN 'MAIL_BORRA' THEN 2 WHEN 'MAIL_REMESA' THEN 3 WHEN 'MAIL_ACTUALIZA' THEN 4 ELSE 5 END AS O FROM @pl WHERE SCRIPT <> 'MAIL_INSERTA_NUEVOS') z), '|',
                    (SELECT COUNT(*) FROM @pl WHERE SCRIPT = 'MAIL_ACTUALIZA' AND PLSQL = N'BEGIN RCVRY.JSP_CORREOS_486; COMMIT; END;')) AS o) x;

DECLARE @ar NVARCHAR(400), @ars NVARCHAR(2000) = N'';
TRUNCATE TABLE stg.CYBER_DELQMST_ACT; TRUNCATE TABLE stg.CYBER_PHONE_G1;
EXEC ops.sp_arribo_automatico @fecha = '2026-11-02', @sin_bajar = 1, @resultado = @ar OUTPUT; SET @ars += @ar + N',';    -- nada subido
INSERT INTO stg.CYBER_DELQMST_ACT (CUENTA) SELECT CUENTA2 FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_ALTA = @id;
EXEC ops.sp_arribo_automatico @fecha = '2026-11-02', @sin_bajar = 1, @resultado = @ar OUTPUT; SET @ars += @ar + N',';    -- SCBSDOS subido: correos (sin servidor vinculado -> ERROR)
EXEC ops.sp_arribo_automatico @fecha = '2026-11-02', @sin_bajar = 1, @resultado = @ar OUTPUT; SET @ars += @ar + N',';    -- correos ya intentados; teléfonos esperando
INSERT INTO stg.CYBER_PHONE_G1 (CUENTA, AREA, TELEFONO) SELECT CUENTA2, AREA, TELEFONO FROM ops.TELEFONO WHERE ID_CORRIDA = @id;
EXEC ops.sp_arribo_automatico @fecha = '2026-11-02', @sin_bajar = 1, @resultado = @ar OUTPUT; SET @ars += @ar + N',';    -- SCBTEL subido: teléfonos
EXEC ops.sp_arribo_automatico @fecha = '2026-11-02', @sin_bajar = 1, @resultado = @ar OUTPUT; SET @ars += @ar;           -- ya no repite
TRUNCATE TABLE stg.CYBER_DELQMST_ACT; TRUNCATE TABLE stg.CYBER_PHONE_G1;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ARRIBO AUTO: espera, detecta SCBSDOS (altas en DELQMST) y SCBTEL (teléfonos de altas en PHONE_G1), una vez cada uno' AS p,
             N'ESPERANDO ARRIBO,CORREOS ERROR,ESPERANDO ARRIBO,TELEFONOS ERROR,ARRIBO AUTOMATICO TERMINADO|1|1' AS e,
             CONCAT(@ars, '|',
                    (SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO CORREOS' AND ESTATUS = 'ERROR'), '|',
                    (SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO TELEFONOS' AND ESTATUS = 'ERROR')) AS o) x;

/* op9.prg: las cuentas nuevas guardan sus teléfonos como AREA + TELEFONO; las existentes, como llegan */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'TEL DAT: nueva normalizada (op9), existente tal como llega' AS p, N'0454771234567|5599999999' AS e,
             CONCAT((SELECT TEL1 FROM dat.DAT_486 WHERE CUENTA = '3333XAXX010101000'), '|', (SELECT TEL1 FROM dat.DAT_486 WHERE CUENTA = '1111XAXX010101000')) AS o) x;

/* Correos (email.PRG): minúsculas, con @, sin "no tiene", uno por cuenta */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'MAIL: sub_mail (CUENTA2|CORREO) y scripts de CYBER' AS p,
             N'486-100003|persona.tres@correo.com,486-102|uno@correo.com|TRUNCATE TABLE RCVRY.JSP_TAB_MAIL_REMESA_486;|EXECUTE RCVRY.JSP_CORREOS_486;' AS e,
             CONCAT((SELECT STRING_AGG(LINEA, ',') WITHIN GROUP (ORDER BY NUM) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'MAIL_SUBMAIL'), '|',
                    (SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'MAIL_BORRA' AND NUM = 1), '|',
                    (SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'MAIL_ACTUALIZA' AND NUM = 1)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'GESCAR sin teléfono: no sale en la asignación (espera lo que baja de CYBER)', CASE WHEN NOT EXISTS (SELECT 1 FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_SINTEL') THEN 1 ELSE 0 END, NULL;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'MAIL: banderas de CYBER (id_proc 416) al inicio y al final' AS p,
             N'UPDATE RCVRY.RPT_LOG_CYBER_REG SET STATUS=1, ETAPA=''INICIA ACTUALIZACION ADDRESS 486'', ACTIVADO=SYSDATE  where id_proc=416;|UPDATE RCVRY.RPT_LOG_CYBER_REG SET STATUS=0, ETAPA=''FINALIZA ACTUALIZACION ADDRESS G1 486'' where id_proc=416;' AS e,
             CONCAT((SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'MAIL_ACTIVA_BANDERA' AND NUM = 1), '|',
                    (SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'MAIL_INACTIVA_BANDERA' AND NUM = 2)) AS o) x;

/* DAT para MIS en CSV (resdat.PRG): CUENTA = 486-folio, campos entre comillas */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'MIS: DAT en CSV con comillas' AS p, N'8|"100","486","' AS e,
             CONCAT((SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'DAT_MIS_ASIG'), '|',
                    (SELECT LEFT(LINEA, 13) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'DAT_MIS_ASIG' AND NUM = 1)) AS o) x;

/* Bases maestras completas (todas las columnas) */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'BASE: maestras guardadas completas (renglones, encabezados y un valor; solo la última)' AS p, N'4|96|1000000001|7|107|1' AS e,
             CONCAT((SELECT REGISTROS FROM dat.BASE_RECIBIDA_ARCHIVO WHERE ID_CORRIDA = @id AND CODIGO = 'MAESTRA_TDC'), '|',
                    (SELECT COUNT(*) FROM dat.BASE_RECIBIDA_ARCHIVO a CROSS APPLY OPENJSON(a.ENCABEZADOS) j WHERE a.ID_CORRIDA = @id AND a.CODIGO = 'MAESTRA_TDC'), '|',
                    (SELECT JSON_VALUE(DATOS, '$."ACC_NUM"') FROM dat.BASE_RECIBIDA WHERE ID_CORRIDA = @id AND CODIGO = 'MAESTRA_TDC' AND FILA = 2), '|',
                    (SELECT REGISTROS FROM dat.BASE_RECIBIDA_ARCHIVO WHERE ID_CORRIDA = @id AND CODIGO = 'MAESTRA_CONSUMO'), '|',
                    (SELECT COUNT(*) FROM dat.BASE_RECIBIDA_ARCHIVO a CROSS APPLY OPENJSON(a.ENCABEZADOS) j WHERE a.ID_CORRIDA = @id AND a.CODIGO = 'MAESTRA_CONSUMO'), '|',
                    (SELECT COUNT(DISTINCT ID_CORRIDA) FROM dat.BASE_RECIBIDA WHERE CODIGO = 'MAESTRA_TDC')) AS o) x;

/* Gescar (ges_nuevas_rea.prg y ges_retiro.prg): 119 posiciones */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'GESCAR: nuevas, reasignadas y retiro (líneas y ancho)' AS p, N'4|1|2|0' AS e,
             CONCAT((SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_NVA'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_REA'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_RETIRO'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO LIKE 'GESCAR%' AND DATALENGTH(LINEA) / 2 <> 119)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'GESCAR: campos de la línea' AS p,
             N'2001486-100001|11022026|000RSR1|aaxrh|CUENTA NUEVA ASIGNADA.#2001486-500|CUENTA REASIGNADA.#2001486-101|RETIRO DE CUENTA.' AS e,
             CONCAT((SELECT CONCAT(RTRIM(LEFT(LINEA, 29)), '|', SUBSTRING(LINEA, 30, 8), '|', SUBSTRING(LINEA, 47, 7), '|', RTRIM(SUBSTRING(LINEA, 56, 8)), '|', RTRIM(SUBSTRING(LINEA, 64, 56)))
                     FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_NVA' AND NUM = 1), '#',
                    (SELECT CONCAT(RTRIM(LEFT(LINEA, 29)), '|', RTRIM(SUBSTRING(LINEA, 64, 56))) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_REA' AND NUM = 1), '#',
                    (SELECT CONCAT(RTRIM(LEFT(LINEA, 29)), '|', RTRIM(SUBSTRING(LINEA, 64, 56))) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_RETIRO' AND NUM = 1)) AS o) x;

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
/* Para estructura.prg (REE): TDC con tramo 60-89 y Consumo personal 90+ con REE previo */
UPDATE dat.DAT_486 SET TRAMO = '60-89', REE = NULL WHERE CUENTA = '3333XAXX010101000';
UPDATE dat.DAT_486 SET REE = 'X' WHERE CUENTA = '20000001';
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
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: PVS y REE por script (ACT_PVS_REE) y sin SCBSDOS' AS p,
             N'update RCVRY.uda1 set u1arcod1=''120'' ,u1arcod3=''' + ISNULL((SELECT LTRIM(RTRIM(REE)) FROM dat.DAT_486 WHERE CUENTA2 = '486-102'), '') + N''' Where u1acct=''486-102'';|commit;|exit;|1|0' AS e,
             CONCAT((SELECT SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'ACT_PVS_REE' AND SENTENCIA LIKE N'%''486-102''%'), '|',
                    (SELECT STRING_AGG(SENTENCIA, '|') WITHIN GROUP (ORDER BY NUM) FROM (SELECT TOP (2) SENTENCIA, NUM FROM ops.CYBER_SCRIPT
                     WHERE ID_CORRIDA = @id AND SCRIPT = 'ACT_PVS_REE' ORDER BY NUM DESC) z), '|',
                    CASE WHEN (SELECT COUNT(*) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'ACT_PVS_REE') - 2
                              = (SELECT COUNT(*) FROM dat.DAT_486 WHERE CUENTA2 IS NOT NULL) THEN 1 ELSE 0 END, '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS_ACT')) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: se arriban todos los pagos (iguales van los dos; crédito sin cruce va tal cual)' AS p, CAST(N'29999999:10.00,486-100001:500.00,486-100001:500.00,486-102:1000.00' AS NVARCHAR(4000)) AS e, CAST((SELECT STRING_AGG(CONCAT(ISNULL(CUENTA2, CUENTA), ':', IMPORTE), ',') WITHIN GROUP (ORDER BY ISNULL(CUENTA2, CUENTA), ID) FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id) AS NVARCHAR(4000)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBPAG: 4 líneas de 104' AS p, N'4|0' AS e,
             CONCAT((SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBPAG'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBPAG' AND DATALENGTH(LINEA) / 2 <> 104)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBPAG: línea completa (pagos.prg)' AS p,
             CONCAT(N'5001', LEFT(N'20000001' + SPACE(25), 25), N'11022026', N'000000001000.00', N'pbank ', N'SERTEC  ', N'11032026', LEFT(N'PAGO' + SPACE(15), 15), N'000000001000.00') AS e,
             (SELECT LINEA FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBPAG' AND LINEA LIKE N'500120000001 %') AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT: REE (estructura.prg): TDC 60-89 = REEST, personal 90+ vacío' AS p, CAST(N'REEST|' AS NVARCHAR(4000)) AS e,
             CAST(CONCAT((SELECT REE FROM dat.DAT_486 WHERE CUENTA = '3333XAXX010101000'), '|', (SELECT REE FROM dat.DAT_486 WHERE CUENTA = '20000001')) AS NVARCHAR(4000)) AS o) x;
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
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ACT 2: pagos de cuentas retiradas se cruzan con el histórico',
       CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ACT')
                         AND PASO = 'ACT PAGOS' AND MENSAJE LIKE N'%de cuentas retiradas (histórico): 2 %') THEN 1 ELSE 0 END,
       (SELECT TOP (1) MENSAJE FROM ops.BITACORA WHERE PASO = 'ACT PAGOS' ORDER BY ID DESC);
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ACT 2: pagos ya arribados no se repiten' AS p, CAST(N'4|0' AS NVARCHAR(4000)) AS e, CAST(CONCAT((SELECT COUNT(*) FROM dat.PAGO_ARRIBADO), '|', (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBPAG')) AS NVARCHAR(4000)) AS o) x;
GO

/* Pagos negativos: la actualización se cancela */
UPDATE cfg.ARCHIVO SET RUTA = '/datos/act_neg/' WHERE CLIENTE = '486' AND PROCESO = 'ACT';
DECLARE @id INT;
BEGIN TRY
    EXEC ops.sp_actualizacion_486 @fecha = '2026-11-03', @id_corrida = @id OUTPUT;
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Pagos negativos: la actualización sigue', 0, ERROR_MESSAGE();
END CATCH;
SET @id = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ACT');
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Pagos negativos: no se arriban, quedan en rechazos y se avisa al equipo de asignaciones' AS p, N'OK|1|0|4|1' AS e,
             CONCAT((SELECT ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = @id), '|',
                    (SELECT COUNT(*) FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'PAGOS_NEGATIVOS'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBPAG'), '|',
                    (SELECT COUNT(*) FROM dat.PAGO_ARRIBADO), '|',
                    (SELECT COUNT(*) FROM mail.ENVIO WHERE ID_CORRIDA = @id AND PLANTILLA = 'PAGOS_NEGATIVOS_486')) AS o) x;
DECLARE @pn TABLE (PARA NVARCHAR(MAX), CC NVARCHAR(MAX), CCO NVARCHAR(MAX), ASUNTO NVARCHAR(255), CUERPO_HTML NVARCHAR(MAX), ADJUNTOS NVARCHAR(MAX));
INSERT INTO @pn EXEC mail.sp_enviar @plantilla = 'PAGOS_NEGATIVOS_486', @valores = N'{"REGISTROS":"1","DETALLE":"x"}', @solo_prueba = 1;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'Pagos negativos: el correo va al equipo de asignaciones',
       CASE WHEN PARA = N'asig.486.cdmx@sertec.com.mx' AND CCO LIKE N'%asignaciones3@sertec.com.mx%' THEN 1 ELSE 0 END, CONCAT(PARA, ' | ', CCO) FROM @pn;
GO

/* ---------------------------------------------------------------------
   RETIRO POR SOLICITUD (folio o riesgo)
   DAT en este punto: 486-102 (riesgo 20000001), 486-100003 (1000000003),
   486-100004 (1000000004) y 486-500, al que se le pone riesgo 100004 para
   probar el caso ambiguo (riesgo de una cuenta = folio de otra).
   --------------------------------------------------------------------- */
UPDATE dat.DAT_486 SET RIESGO = '100004' WHERE CUENTA2 = '486-500';
DECLARE @v NVARCHAR(MAX) = N'486-100003, 1000000004
777777;486-100003, 100004';
DECLARE @t TABLE (ID INT IDENTITY(1,1), VALOR NVARCHAR(200), TIPO VARCHAR(10), RESULTADO VARCHAR(20), CUENTA2 VARCHAR(28), FOLIO VARCHAR(10), SEGMENTO2 VARCHAR(20), SDO_ACT DECIMAL(18,2));
INSERT INTO @t (VALOR, TIPO, RESULTADO, CUENTA2, FOLIO, SEGMENTO2, SDO_ACT) EXEC ops.sp_retiro_solicitud @valores = @v;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'RET: vista previa (folio, riesgo, no existe, repetido, ambiguo)' AS p,
             N'486-100003:FOLIO:A RETIRAR:486-100003|1000000004:RIESGO:A RETIRAR:486-100004|777777::NO ESTA EN EL DAT:|486-100003:FOLIO:REPETIDO:486-100003|100004::AMBIGUO:|4' AS e,
             CONCAT((SELECT STRING_AGG(CONCAT(VALOR, ':', TIPO, ':', RESULTADO, ':', CUENTA2), '|') WITHIN GROUP (ORDER BY ID) FROM @t), '|',
                    (SELECT COUNT(*) FROM dat.DAT_486)) AS o) x;

DECLARE @id INT;
BEGIN TRY
    EXEC ops.sp_retiro_solicitud @valores = @v, @motivo = N'SOLICITUD DE PRUEBA', @confirmar = 1, @id_corrida = @id OUTPUT;
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'RET: retiro por solicitud termina OK', 0, ERROR_MESSAGE();
END CATCH;
SET @id = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'RET');
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'RET: retira 2, rechaza 3, archivos de retiro y script de CYBER' AS p, N'OK|2|3|486-100003,486-100004|2|4|B,B' AS e,
             CONCAT((SELECT ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = @id), '|',
                    (SELECT COUNT(*) FROM dat.DAT_486), '|',
                    (SELECT COUNT(*) FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'RETIRO_SOLICITUD'), '|',
                    (SELECT STRING_AGG(RTRIM(LINEA), ',') WITHIN GROUP (ORDER BY NUM) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'DEVOL_CYBER'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_RETIRO'), '|',
                    (SELECT COUNT(*) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id AND SCRIPT = 'RETIRO'), '|',
                    (SELECT STRING_AGG(ESTATUS, ',') FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_BAJA = @id)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'RET: lista de folios para operación (FOLIO,CUENTA2,MOTIVO)' AS p, N'100003,486-100003,SOLICITUD DE PRUEBA' AS e,
             (SELECT LINEA FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'RETIROS' AND NUM = 1) AS o) x;

BEGIN TRY
    EXEC ops.sp_revertir_corrida @id, 1;
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'RET: retroceso', 0, ERROR_MESSAGE();
END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'RET: retroceso devuelve las cuentas al DAT' AS p, N'4|A,A' AS e,
             CONCAT((SELECT COUNT(*) FROM dat.DAT_486), '|',
                    (SELECT STRING_AGG(ESTATUS, ',') FROM dat.HISTORIA_FOLIO WHERE CUENTA IN ('3333XAXX010101000', '4444XAXX010101000'))) AS o) x;
GO

/* ---------------------------------------------------------------------
   PROCESOS MANUALES: etiquetado del DAT, mora, lista negra, blanqueo de
   status y avisos. DAT: 486-102 (20000001), 486-100003, 486-100004, 486-500.
   --------------------------------------------------------------------- */
DECLARE @t TABLE (ID INT IDENTITY(1,1), CAMPO SYSNAME, RESULTADO VARCHAR(30), REGISTROS INT);
INSERT INTO @t (CAMPO, RESULTADO, REGISTROS) EXEC ops.sp_etiquetar_campo @campo = 'saldo1', @archivo = N'/datos/etiquetas/ETIQUETA_SALDO1.csv', @codepage = '';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ETI: vista previa del etiquetado de un campo (FOLIO,ETIQUETA)' AS p,
             N'SALDO1:A ACTUALIZAR:1|SALDO1:IMPORTE INVALIDO:1|SALDO1:NO ESTA EN EL DAT:1|SALDO1:SIN ETIQUETA:1' AS e,
             (SELECT STRING_AGG(CONCAT(CAMPO, ':', RESULTADO, ':', REGISTROS), '|') WITHIN GROUP (ORDER BY ID) FROM @t) AS o) x;
DECLARE @id INT, @err NVARCHAR(4000);
BEGIN TRY
    EXEC ops.sp_etiquetar_campo @campo = 'SALDO1', @archivo = N'/datos/etiquetas/ETIQUETA_SALDO1.csv', @codepage = '', @confirmar = 1, @id_corrida = @id OUTPUT;
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ETI: etiquetado termina OK', 0, ERROR_MESSAGE();
END CATCH;
SET @id = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ETI');
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ETI: SALDO1 etiquetado por folio, rechazos y SCBSDOS' AS p, N'OK|1500.00|3|1' AS e,
             CONCAT((SELECT ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = @id), '|',
                    (SELECT SALDO1 FROM dat.DAT_486 WHERE CUENTA = '20000001'), '|',
                    (SELECT COUNT(*) FROM ops.RECHAZO WHERE ID_CORRIDA = @id AND ORIGEN = 'ETIQUETADO_DAT'), '|',
                    CASE WHEN (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS_ETI') > 0 THEN 1 ELSE 0 END) AS o) x;

/* Nombre de Operación: MORA -> ETIQUETA1; '-' deja en blanco; folio repetido se rechaza */
SET @id = NULL;
DELETE FROM @t;
BEGIN TRY
    INSERT INTO @t (CAMPO, RESULTADO, REGISTROS)
    EXEC ops.sp_etiquetar_campo @campo = 'MORA', @archivo = N'/datos/etiquetas/ETIQUETA_MORA.csv', @codepage = '', @confirmar = 1, @id_corrida = @id OUTPUT;
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ETI: etiquetado por alias termina OK', 0, ERROR_MESSAGE();
END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ETI: alias MORA -> ETIQUETA1, blanco con ''-'', repetidos y sin folio' AS p,
             N'ETIQUETA1:A ACTUALIZAR:2|ETIQUETA1:FOLIO REPETIDO:2|ETIQUETA1:SIN FOLIO:1|MORA 2|[]' AS e,
             CONCAT((SELECT STRING_AGG(CONCAT(CAMPO, ':', RESULTADO, ':', REGISTROS), '|') WITHIN GROUP (ORDER BY ID) FROM @t), '|',
                    (SELECT ETIQUETA1 FROM dat.DAT_486 WHERE CUENTA = '3333XAXX010101000'), '|',
                    (SELECT CONCAT('[', ETIQUETA1, ']') FROM dat.DAT_486 WHERE CUENTA = '20000001')) AS o) x;

/* Campos no permitidos y TOP */
BEGIN TRY
    EXEC ops.sp_etiquetar_campo @campo = 'FOLIO', @archivo = N'/datos/etiquetas/ETIQUETA_MORA.csv', @codepage = '';
    SET @err = N'no falló';
END TRY
BEGIN CATCH SET @err = CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
BEGIN TRY
    EXEC ops.sp_etiquetar_campo @campo = 'ETIQUETA6', @archivo = N'/datos/etiquetas/ETIQUETA_MORA.csv', @codepage = '';
    SET @err = @err + N'|no falló';
END TRY
BEGIN CATCH SET @err = @err + N'|' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ETI: rechaza campos fuera de ETIQUETADO_CAMPOS y TOP', CASE WHEN @err = N'50602|50605' THEN 1 ELSE 0 END, @err;

/* Candado de Excel: cuentas en notación científica */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE)
SELECT N'ASIG: detecta notación científica de Excel', CASE WHEN x.o = N'1|0|0|3' THEN 1 ELSE 0 END, x.o
FROM (SELECT CONCAT(CASE WHEN '1.23457E+15' LIKE '%[0-9][Ee][+-][0-9]%' THEN 1 ELSE 0 END, '|',
                    CASE WHEN '5512345678901234' LIKE '%[0-9][Ee][+-][0-9]%' THEN 1 ELSE 0 END, '|',
                    CASE WHEN 'XAXX010101E00' LIKE '%[0-9][Ee][+-][0-9]%' THEN 1 ELSE 0 END, '|',
                    (SELECT COUNT(*) FROM cfg.REGLA WHERE CLIENTE = '486' AND CODIGO LIKE '%NOTACION_CIENTIFICA' AND ACCION = 'CANCELAR')) AS o) x;
GO

/* eti486 ya no se usa: aunque exista una etiqueta ETI486, DMPHONE sale de la ETIQUETA1 que llegó */
INSERT INTO cfg.ETIQUETA (CLIENTE, TIPO, LLAVE, VALOR) VALUES ('486', 'ETI486', '486-102', 'MORA 3');
DECLARE @id INT;
EXEC ops.sp_regenerar_scbsdos @motivo = N'Prueba de SCBSDOS fuera de proceso', @id_corrida = @id OUTPUT;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o OR (x.e IS NULL AND x.o IS NULL) THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'SCBSDOS: DMPHONE = ETIQUETA1 recibida (sin eti486)' AS p,
             CAST((SELECT ISNULL(ETIQUETA1, '') FROM dat.DAT_486 WHERE CUENTA2 = '486-102') AS NVARCHAR(4000)) AS e,
             CAST((SELECT pru.fn_campo(LINEA, 'DMPHONE') FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS_ETI' AND LINEA LIKE N'____486-102 %') AS NVARCHAR(4000)) AS o) x;
DELETE FROM cfg.ETIQUETA WHERE TIPO = 'ETI486';
GO

/* Lista negra (blacklist_486.prg) */
DECLARE @r TABLE (TIPO VARCHAR(20), LEIDOS INT, VALIDOS INT, NUEVOS INT, YA_EXISTIAN INT, NO_10 INT, DESACTIVADOS INT);
INSERT INTO @r EXEC cfg.sp_exclusion_cargar @tipo = 'TELEFONO', @archivo = N'/datos/exclusiones/BLACKLIST.csv', @req = 'REQ PRUEBA', @solicita = N'Operación', @codepage = '';
INSERT INTO @r EXEC cfg.sp_exclusion_cargar @tipo = 'TELEFONO', @archivo = N'/datos/exclusiones/BLACKLIST.csv', @req = 'REQ PRUEBA', @solicita = N'Operación', @codepage = '';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'EXCLUSION: lista negra solo 10 dígitos, con REQ y sin duplicar' AS p, N'1:1:2,1:0:2|REQ PRUEBA' AS e,
             CONCAT((SELECT STRING_AGG(CONCAT(VALIDOS, ':', NUEVOS, ':', NO_10), ',') WITHIN GROUP (ORDER BY NUEVOS DESC) FROM @r), '|',
                    (SELECT REQ FROM cfg.EXCLUSION WHERE TIPO = 'TELEFONO' AND VALOR = '5512345678')) AS o) x;
/* Con TELEFONO, OS, FECHA y STATUS: vacío deja de excluir, X da de alta con su OS y fecha */
DELETE FROM @r;
INSERT INTO @r EXEC cfg.sp_exclusion_cargar @tipo = 'TELEFONO', @archivo = N'/datos/exclusiones/BLACKLIST_STATUS.csv', @solicita = N'Operación', @codepage = '';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'EXCLUSION: lista negra con STATUS (vacío desactiva, X da de alta con OS y fecha)' AS p, N'1:1:1|0|OS-51:2026-11-01:CARGA' AS e,
             CONCAT((SELECT CONCAT(VALIDOS, ':', NUEVOS, ':', DESACTIVADOS) FROM @r), '|',
                    (SELECT COUNT(*) FROM cfg.EXCLUSION WHERE TIPO = 'TELEFONO' AND VALOR = '5512345678' AND ACTIVO = 1), '|',
                    (SELECT CONCAT(REQ, ':', CAST(FE_ALTA AS DATE), ':', ORIGEN) FROM cfg.EXCLUSION WHERE TIPO = 'TELEFONO' AND VALOR = '5598765432' AND ACTIVO = 1)) AS o) x;
GO

/* Blanqueo de status (status.prg) sobre la asignación 2 (día 2: sí toca). Lo que baja de CYBER llega a stg.CYBER_STATUS */
INSERT INTO stg.CYBER_STATUS (CLIENTE, FOLIO, CUENTA, STATUS, ACCION, FECHA, PESO, DMSSNUM)
VALUES ('486', '100001', '486-100001', 'PP', 'CM', '01/11/2026', '1', '20000004'),
       ('486', '100003', '486-100003', 'NC', 'CM', '01/11/2026', '1', '3333XAXX010101000'),
       ('486', '500', '486-500', NULL, NULL, NULL, NULL, '20000009'),
       ('486', '102', '486-102', 'NC', 'CM', '01/11/2026', '1', '20000001'),
       ('307', '1', '307-1', 'NC', 'CM', '01/11/2026', '1', 'X'),
       ('486', '100004', '486-100004', NULL, 'RP', '01/11/2026', '1', '4444XAXX010101000');
EXEC ops.sp_blanqueo_status @id_corrida = 2;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'STATUS: blanquea nuevas/reasignadas salvo PP y sin status' AS p,
             N'486-100003,486-100004|4|100003,486-100003,NC,CM|NO ES NUEVA NI REASIGNADA EN LA CORRIDA,OTRO CLIENTE,SIN STATUS NI ACCION,STATUS QUE NO SE BLANQUEA' AS e,
             CONCAT((SELECT STRING_AGG(CUENTA, ',') WITHIN GROUP (ORDER BY CUENTA) FROM ops.STATUS_CYBER WHERE ID_CORRIDA = 2 AND BLANQUEA = 1), '|',
                    (SELECT COUNT(*) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = 2 AND SCRIPT = 'BLANQUEO_STATUS'), '|',
                    (SELECT LINEA FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = 2 AND ARCHIVO = 'BLANQUEO_LISTA' AND NUM = 1), '|',
                    (SELECT STRING_AGG(MOTIVO, ',') WITHIN GROUP (ORDER BY MOTIVO) FROM ops.STATUS_CYBER WHERE ID_CORRIDA = 2 AND MOTIVO IS NOT NULL)) AS o) x;
GO

INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'STATUS: la tabla de paso queda vacía', CASE WHEN NOT EXISTS (SELECT 1 FROM stg.CYBER_STATUS) THEN 1 ELSE 0 END, NULL;
GO

/* Correos nuevos (email.PRG): sin lo que baja de CYBER no se arman; con él, solo los que CYBER no tiene */
BEGIN TRY
    EXEC ops.sp_correos_nuevos @id_corrida = 2;
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) VALUES (N'CORREOS NUEVOS: sin datos de CYBER se detiene', 0, N'No se detuvo');
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'CORREOS NUEVOS: sin datos de CYBER se detiene (50642)', CASE WHEN ERROR_NUMBER() = 50642 THEN 1 ELSE 0 END, ERROR_MESSAGE();
END CATCH;
INSERT INTO stg.CYBER_CORREO (CUENTA, CORREO) VALUES ('486-102', 'UNO@correo.com '), ('486-100004', 'otro@correo.com');
DECLARE @r TABLE (NUEVOS INT, YA_EN_CYBER INT);
INSERT INTO @r EXEC ops.sp_correos_nuevos @id_corrida = 2;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'CORREOS NUEVOS: INSERT en RCVRY.ADDRESS solo de lo que CYBER no tiene (formato email.sql)' AS p,
             N'1|1|3|INSERT INTO RCVRY.ADDRESS VALUES(''3333XAXX010101000'',''3'','''',''persona.tres@correo.com'','''','''','''','''','''',''A'','''',''1'',''486-100003'',TO_DATE(''02/11/26 |0' AS e,
             CONCAT((SELECT CONCAT(NUEVOS, '|', YA_EN_CYBER) FROM @r), '|',
                    (SELECT COUNT(*) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = 2 AND SCRIPT = 'MAIL_INSERTA_NUEVOS'), '|',
                    (SELECT LEFT(SENTENCIA, 143) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = 2 AND SCRIPT = 'MAIL_INSERTA_NUEVOS' AND NUM = 1), '|',
                    (SELECT COUNT(*) FROM stg.CYBER_CORREO)) AS o) x;
GO

/* Gescar de nuevas y reasignadas sin teléfono activo en CYBER (ges486.prg) */
INSERT INTO stg.CYBER_TELEFONO (CUENTA, LADA, TEL)
VALUES ('486-100001', '0155', '12345678'), ('486-100003', '045', '4771234567'), ('486-100003', '0155', '11111111'), ('486-102', '0155', '77777777');
EXEC ops.sp_gescar_sin_telefono @id_corrida = 2;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'GESCAR sin teléfono: cuentas sin teléfono en CYBER (119, zzasg)' AS p,
             N'3|0|2001486-100002|zzasg|CUENTA SIN NUMERO TELEFONICO|486-100002,486-100004,486-500' AS e,
             CONCAT((SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = 2 AND ARCHIVO = 'GESCAR_SINTEL'), '|',
                    (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = 2 AND ARCHIVO = 'GESCAR_SINTEL' AND DATALENGTH(LINEA) / 2 <> 119), '|',
                    (SELECT CONCAT(RTRIM(LEFT(LINEA, 29)), '|', RTRIM(SUBSTRING(LINEA, 56, 8)), '|', RTRIM(SUBSTRING(LINEA, 64, 56)))
                     FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = 2 AND ARCHIVO = 'GESCAR_SINTEL' AND NUM = 1), '|',
                    (SELECT STRING_AGG(SUBSTRING(RTRIM(LEFT(LINEA, 29)), 5, 25), ',') WITHIN GROUP (ORDER BY NUM) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = 2 AND ARCHIVO = 'GESCAR_SINTEL')) AS o) x;
GO

/* Correos del 486 (30/10): inicio de asignación automático y devolución única en dos copias */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'CORREO: inicio de asignación al arrancar la corrida',
       CASE WHEN EXISTS (SELECT 1 FROM mail.ENVIO WHERE ID_CORRIDA = 2 AND PLANTILLA = 'INICIO_ASIG_486') THEN 1 ELSE 0 END, NULL;
DECLARE @m TABLE (PARA NVARCHAR(MAX), CC NVARCHAR(MAX), CCO NVARCHAR(MAX), ASUNTO NVARCHAR(255), CUERPO_HTML NVARCHAR(MAX), ADJUNTOS NVARCHAR(MAX));
INSERT INTO @m EXEC ops.sp_aviso_devolucion 3, N'C:\RETIROS_PAG_486_prueba.zip', 1;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'CORREO: devolución única, Operación con el ZIP y AEM en copia oculta sin él' AS p, N'2|1|1|1|1' AS e,
             CONCAT((SELECT COUNT(*) FROM @m WHERE ASUNTO LIKE N'Devolucion del cliente BANCO BAJIO%' AND CUERPO_HTML LIKE N'%(actualización)%'), '|',
                    (SELECT COUNT(*) FROM @m WHERE PARA LIKE N'%soluciones.486@sertec.com.mx%' AND ADJUNTOS = N'C:\RETIROS_PAG_486_prueba.zip' AND CCO NOT LIKE N'%aem.%'), '|',
                    (SELECT COUNT(*) FROM @m WHERE PARA IS NULL AND CC IS NULL AND CCO LIKE N'%aem.control1@sertec.com.mx%' AND ADJUNTOS IS NULL), '|',
                    (SELECT COUNT(*) FROM mail.PLANTILLA WHERE CODIGO IN ('INICIO_ASIG_486', 'CONFIRMACION_ASIG_486', 'ALERTA_NUEVAS_486', 'DEVOLUCION_486', 'DEVOLUCION_486_AEM')) / 5, '|',
                    CASE WHEN NOT EXISTS (SELECT 1 FROM mail.PLANTILLA WHERE CODIGO IN ('ASIG_EXPRESS_486', 'RETIROS_ACT_486', 'NOTIFICACION_RETIRO_486', 'CONFIRMACION_ACT_486',
                                                                                      'PAGOS_NO_ACTUALIZADOS_486', 'ERROR_PROCESO_486', 'DEVOLUCION_MASIVA_486', 'AVISO_DEVOLUCION_486')) THEN 1 ELSE 0 END) AS o) x;

/* Horas del arribo (bitac/bitact: solicitud, autorización y fin) */
DECLARE @act INT = (SELECT MIN(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ACT');
EXEC ops.sp_marcar_arribo @act, 'solicitud', '2026-11-03T10:00:00';
EXEC ops.sp_marcar_arribo @act, 'AUTORIZACION', '2026-11-03T10:20:00';
EXEC ops.sp_marcar_arribo @act, 'AUTORIZACION', '2026-11-03T10:25:00';      -- la última marca es la que vale
EXEC ops.sp_marcar_arribo @act, 'FIN', '2026-11-03T11:00:00';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ARRIBO: horas de solicitud, autorización y fin' AS p, N'25|35|1' AS e,
             (SELECT CONCAT(MIN_ESPERA_AUTORIZACION, '|', MIN_ARRIBO, '|', (SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @act AND PASO = 'ARRIBO AUTORIZACION'))
              FROM ops.v_TIEMPOS_CORRIDA WHERE ID_CORRIDA = @act) AS o) x;

/* Cuadre de pagos contra CYBER (BAJ.sql): CYBER trae todos menos uno, más uno ajeno */
DECLARE @pc INT = (SELECT MIN(ID_CORRIDA) FROM dat.PAGO_ARRIBADO WHERE ORIGEN = 'CORRIDA');
DECLARE @falta BIGINT = (SELECT MIN(ID) FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @pc AND ORIGEN = 'CORRIDA' AND CUENTA2 IS NOT NULL);
-- los arribados sin CUENTA2 (crédito que no está en el DAT) tampoco pueden aparecer en CYBER
DECLARE @sin_c2 INT = (SELECT COUNT(*) FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @pc AND ORIGEN = 'CORRIDA' AND CUENTA2 IS NULL);
INSERT INTO stg.CYBER_PAGO (CUENTA, MONTO, FECHA)
SELECT CUENTA2, CONVERT(VARCHAR(30), IMPORTE), '03/11/2026' FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @pc AND ORIGEN = 'CORRIDA' AND ID <> @falta
UNION ALL SELECT '486-999999', '10.00', '03/11/2026';
EXEC ops.sp_cuadrar_pagos @pc;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'PAGOS: cuadre contra CYBER detecta el que no subió' AS p,
             CONCAT(1 + @sin_c2, '|AVISO|1|0') AS e,
             CONCAT((SELECT COUNT(*) FROM ops.RECHAZO WHERE ID_CORRIDA = @pc AND ORIGEN = 'CUADRE_PAGOS'), '|',
                    (SELECT TOP (1) ESTATUS FROM ops.BITACORA WHERE ID_CORRIDA = @pc AND PASO = 'CUADRE PAGOS' ORDER BY ID DESC), '|',
                    (SELECT COUNT(*) FROM ops.RECHAZO r JOIN dat.PAGO_ARRIBADO p ON p.ID = @falta
                     WHERE r.ID_CORRIDA = @pc AND r.ORIGEN = 'CUADRE_PAGOS' AND JSON_VALUE(r.DATOS, '$.CUENTA2') = p.CUENTA2
                       AND CAST(JSON_VALUE(r.DATOS, '$.IMPORTE') AS DECIMAL(15,2)) = p.IMPORTE), '|',
                    (SELECT COUNT(*) FROM stg.CYBER_PAGO)) AS o) x;

INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE)
SELECT N'Catálogo: perfil de correo asig.486.cdmx y sin COVID/Reestructura en las bases maestras', CASE WHEN x.o = N'0|0|1' THEN 1 ELSE 0 END, x.o
FROM (SELECT CONCAT((SELECT COUNT(*) FROM mail.PLANTILLA WHERE PERFIL_DBMAIL <> N'asig.486.cdmx'), '|',
                    (SELECT COUNT(*) FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO
                     WHERE a.CLIENTE = '486' AND c.CAMPO_DESTINO IN ('ETIQUETA', 'REE') AND a.CODIGO LIKE 'MAESTRA%'), '|',
                    (SELECT COUNT(*) FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO
                     WHERE a.CODIGO = 'MAESTRA_TDC' AND c.CAMPO_DESTINO = 'ENFOQUE')) AS o) x;

/* Avisos retirados (29/10): no deben quedar reglas ni plantillas */
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE)
SELECT N'REGLAS: sin avisos de saldos no actualizados, saldos iguales ni pagos sin subir', CASE WHEN x.o = N'0|0' THEN 1 ELSE 0 END, x.o
FROM (SELECT CONCAT((SELECT COUNT(*) FROM cfg.REGLA WHERE CODIGO IN ('SALDOS_NO_ACTUALIZADOS') OR CODIGO LIKE '%[_]SALDOS_IGUALES_DAT'), '|',
                    (SELECT COUNT(*) FROM mail.PLANTILLA WHERE CODIGO IN ('SALDOS_NO_ACTUALIZADOS_486', 'SALDOS_IGUALES_DAT_486', 'PAGOS_NO_SUBIERON_486'))) AS o) x;

/* Se revierten las corridas de etiquetado (de la más reciente a la más vieja) para seguir con el retroceso */
DECLARE @e0 INT = (SELECT MIN(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ETI'), @ex INT;
BEGIN TRY
    WHILE 1 = 1
    BEGIN
        SET @ex = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE PROCESO = 'ETI' AND ESTATUS = 'OK');
        IF @ex IS NULL BREAK;
        EXEC ops.sp_revertir_corrida @ex, 1;
    END;
END TRY
BEGIN CATCH
    INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'ETI: retroceso', 0, ERROR_MESSAGE();
END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'ETI: retroceso deja el DAT como antes del etiquetado' AS p, N'900.00|REVERTIDA' AS e,
             CONCAT((SELECT SALDO1 FROM dat.DAT_486 WHERE CUENTA = '20000001'), '|', (SELECT ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = @e0)) AS o) x;
GO

/* ---------------------------------------------------------------------
   RETROCESO: corridas 5, 4 y 3 (actualizaciones) y luego la 2 (asignación)
   (la 6, retiro por solicitud, ya se revirtió arriba)
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
             CONCAT((SELECT COUNT(*) FROM dat.DAT_486), '|', (SELECT COUNT(*) FROM dat.PAGO_ARRIBADO), '|',
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
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'Retroceso ASIG: la base maestra anterior de TDC vuelve a ser la vigente' AS p, N'1|0' AS e,
             CONCAT((SELECT CAST(VIGENTE AS INT) FROM dat.BASE_RECIBIDA_ARCHIVO WHERE ID_CORRIDA = 0 AND CODIGO = 'MAESTRA_TDC'), '|',
                    (SELECT COUNT(*) FROM dat.BASE_RECIBIDA_ARCHIVO WHERE ID_CORRIDA = 2)) AS o) x;
GO

/* ---------------------------------------------------------------------
   EXPORTAR archivos (vista previa: en Linux no hay automatización OLE ni xp_cmdshell)
   --------------------------------------------------------------------- */
DECLARE @p TABLE (ORDEN INT, TIPO VARCHAR(10), ARCHIVO VARCHAR(50), RUTA NVARCHAR(400), CHARSET VARCHAR(30), EOL VARCHAR(4), ENCABEZADO BIT, LINEAS INT, COMANDO NVARCHAR(4000));
INSERT INTO @p EXEC ops.sp_exportar_salidas @id_corrida = 2, @zip = 'RETIROS', @solo_mostrar = 1;
DECLARE @dir NVARCHAR(100) = N'C:\BANBAJ\486\SALIDA\20261102_corrida2\';
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'EXPORTAR: archivos de la asignación con nombre, carpeta y líneas' AS p,
             N'8|7|4|1|2|7|1|1|9|1|1|windows-1252:CRLF' AS e,
             CONCAT((SELECT LINEAS FROM @p WHERE RUTA = @dir + N'SCBSDOS.TXT'), '|',
                    (SELECT LINEAS FROM @p WHERE RUTA = @dir + N'SCBTEL.TXT'), '|',
                    (SELECT LINEAS FROM @p WHERE RUTA = @dir + N'SCBACTH_486NU.TXT'), '|',
                    (SELECT LINEAS FROM @p WHERE RUTA = @dir + N'SCBACTH_486REA.TXT'), '|',
                    (SELECT LINEAS FROM @p WHERE RUTA = @dir + N'SCBACTH_486.TXT'), '|',
                    (SELECT LINEAS FROM @p WHERE RUTA = @dir + N'sub_mst.TXT'), '|',
                    (SELECT COUNT(*) FROM @p WHERE RUTA LIKE @dir + N'MX[_]G1MCT[_]DVBJIG[_]20261102[_]%'), '|',
                    (SELECT COUNT(*) FROM @p WHERE RUTA = @dir + N'RETIROS_486_20261102.csv'), '|',
                    (SELECT LINEAS FROM @p WHERE RUTA = @dir + N'DAT486_20261102.csv' AND ENCABEZADO = 1), '|',
                    (SELECT COUNT(*) FROM @p WHERE RUTA = @dir + N'cyber\RETIRO.sql'), '|',
                    (SELECT COUNT(*) FROM @p WHERE RUTA = @dir + N'cyber\TEL_ACTUALIZA.sql'), '|',
                    (SELECT STRING_AGG(CS, ',') FROM (SELECT DISTINCT CONCAT(CHARSET, ':', EOL) AS CS FROM @p WHERE TIPO <> 'ZIP') d)) AS o) x;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'EXPORTAR: copia del DAT para MIS en \\192.168.50.13\q\MIS\SERTEC98\CLIENTES\486\',
       CASE WHEN (SELECT COUNT(*) FROM @p WHERE TIPO = 'MIS' AND RUTA = N'\\192.168.50.13\q\MIS\SERTEC98\CLIENTES\486\DAT486_20261102.csv' AND LINEAS = 9) = 1 THEN 1 ELSE 0 END,
       (SELECT STRING_AGG(CONCAT(TIPO, ':', RUTA, ':', LINEAS), ' | ') FROM @p WHERE TIPO = 'MIS');
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT N'EXPORTAR: ZIP de retiros en C:\ con 7-Zip y la contraseña oculta',
       CASE WHEN RUTA LIKE N'C:\RETIROS[_]PAG[_]486[_]%.zip' AND COMANDO LIKE N'""C:\Program Files\7-Zip\7z.exe" a -tzip -mem=ZipCrypto -p"********" -y "C:\RETIROS[_]PAG[_]486[_]%.zip" "'
                 + @dir + N'RETIROS_486_20261102.csv""' THEN 1 ELSE 0 END, CONCAT(RUTA, ' | ', COMANDO)
FROM @p WHERE TIPO = 'ZIP';
DELETE FROM @p;
INSERT INTO @p EXEC ops.sp_exportar_salidas @id_corrida = 3, @solo_mostrar = 1;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'EXPORTAR: SCBPAG y scripts de saldos de la actualización' AS p, N'4|3' AS e,
             CONCAT((SELECT LINEAS FROM @p WHERE RUTA LIKE N'%\SCBPAG.TXT'), '|',
                    (SELECT COUNT(*) FROM @p WHERE TIPO = 'SCRIPT' AND ARCHIVO IN ('ACT_SALDOS', 'ACT_VENCIDO', 'ACT_PAGMIN'))) AS o) x;
GO

/* ---------------------------------------------------------------------
   CREDENCIALES y consultas a CYBER (sin Oracle: solo arma la consulta)
   --------------------------------------------------------------------- */
INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('cyber_oracle', 'usuario_prueba', N'Clave$Prueba1');
INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('CYBER_ORACLE', 'usuario_nuevo', N'Clave$Nueva2');   -- reemplaza
DECLARE @u NVARCHAR(128), @c NVARCHAR(256), @err NVARCHAR(4000) = N'';
EXEC cfg.sp_credencial_leer 'CYBER_ORACLE', @u OUTPUT, @c OUTPUT;
BEGIN TRY
    INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('CYBER_ORACLE', 'x', N'********');
END TRY
BEGIN CATCH SET @err = CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'CREDENCIAL: se guarda cifrada, se reemplaza y no se muestra' AS p, N'1|usuario_nuevo|1|********|0|50800' AS e,
             CONCAT((SELECT COUNT(*) FROM cfg.CREDENCIAL), '|', @u, '|', CASE WHEN @c = N'Clave$Nueva2' THEN 1 ELSE 0 END, '|',
                    (SELECT CLAVE FROM cfg.CAPTURA_CREDENCIAL WHERE SISTEMA = 'CYBER_ORACLE'), '|',
                    (SELECT COUNT(*) FROM cfg.CREDENCIAL WHERE CHARINDEX(CAST(N'Clave$Nueva2' AS VARBINARY(100)), CLAVE) > 0), '|', @err) AS o) x;

DECLARE @m TABLE (CONSULTA VARCHAR(20), SERVIDOR SYSNAME, ORACLE NVARCHAR(MAX), SQL_SERVER NVARCHAR(MAX));
INSERT INTO @m EXEC ops.sp_bajar_cyber 'pagos', @fecha = '2026-11-03', @solo_mostrar = 1;
INSERT INTO @m EXEC ops.sp_bajar_cyber 'STATUS', @solo_mostrar = 1;
SET @err = N'';
BEGIN TRY EXEC ops.sp_bajar_cyber 'TELEFONOS', @id_corrida = 2; END TRY
BEGIN CATCH SET @err = CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
INSERT INTO pru.RESULTADO (PRUEBA, OK, DETALLE) SELECT x.p, CASE WHEN x.e = x.o THEN 1 ELSE 0 END, CONCAT(N'esperado=[', x.e, N'] obtenido=[', x.o, N']')
FROM (SELECT N'CYBER: consultas por servidor vinculado (BAJ.sql, STATUS.SQL) y aviso si no está configurado' AS p, N'1|1|1|50823' AS e,
             CONCAT((SELECT COUNT(*) FROM @m WHERE CONSULTA = 'PAGOS' AND ORACLE LIKE N'%RCVRY.pmtfil%' AND ORACLE LIKE N'%DMCOMPANY = ''486''%'
                                                AND ORACLE LIKE N'%TO_DATE(''2026-11-03''%' AND SQL_SERVER LIKE N'INSERT INTO stg.CYBER_PAGO (CUENTA, MONTO, FECHA) EXEC (N''select PMACCT%) AT [[]CYBER];'), '|',
                    (SELECT COUNT(*) FROM @m WHERE CONSULTA = 'STATUS' AND ORACLE LIKE N'%DMSTATUS is null%'), '|',
                    (SELECT COUNT(*) FROM @m WHERE CONSULTA = 'PAGOS' AND SQL_SERVER LIKE N'%''''2026-11-03''''%'), '|', @err) AS o) x;
DELETE FROM cfg.CAPTURA_CREDENCIAL WHERE SISTEMA = 'CYBER_ORACLE';
GO

/* ---------------------------------------------------------------------
   TELÉFONOS DE CYBER (como G4_025_TELEFONOS): plan de numeración de la misma
   instancia y quejas por servidor vinculado (en la prueba, uno que apunta a sí mismo)
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS pru.CAT_PNM;
CREATE TABLE pru.CAT_PNM (LADA INT, SERIE INT, NUMINI INT, NUMFIN INT, TIPORED VARCHAR(10));
INSERT INTO pru.CAT_PNM VALUES (55, 1111, 0, 9999, 'MOVIL'), (55, 1111, 0, 9999, 'FIJO'), (477, 23, 0, 9999, 'fijo'), (81, 50, 0, 4999, 'MOVIL'), (99, 1, 0, 1, 'OTRO');
DROP TABLE IF EXISTS pru.telbaj;
CREATE TABLE pru.telbaj (grupo VARCHAR(2), cuenta VARCHAR(30), telo VARCHAR(20), telpho VARCHAR(20));
INSERT INTO pru.telbaj VALUES ('1', '486-200', '525511112222', ''), ('1', '486-201', '', '5533334444'), ('4', '025-1', '5599998888', ''),
                              ('1', 'X486', '5500000001', ''), ('1', '486-202', '123', '');
DECLARE @pnm_ant INT = (SELECT COUNT(*) FROM cfg.PLAN_NUMERACION), @base SYSNAME = DB_NAME(), @err NVARCHAR(4000) = N'';
DECLARE @id INT;
EXEC ops.sp_corrida_iniciar '486', 'ETI', '2026-11-04', NULL, @id OUTPUT;
/* G4_025_TELEFONOS (01/11): número basura y teléfono fuera del plan de numeración se descartan */
DECLARE @o NVARCHAR(4000);
UPDATE dat.DAT_486 SET TEL12 = '5555555555', TEL13 = '4778889999' WHERE CUENTA2 = (SELECT MIN(CUENTA2) FROM dat.DAT_486 WHERE CLIENTE = '486');
EXEC ops.sp_telefonos @id;
SET @o = CONCAT((SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'TELEFONOS' AND MENSAJE LIKE N'%sin plan de numeración: 1 %'), '|',
                (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id AND (TELEFONO LIKE '%8889999' OR TELEFONO LIKE '%55555555')));
EXEC pru.sp_igual N'TEL: fuera del plan de numeración y número basura (5555555555) no salen', N'1|0', @o;
SET @o = CONCAT((SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'TELEFONOS' AND MENSAJE LIKE N'%sin plan de numeración: 0 %'), '|',
                (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id AND TELEFONO LIKE '%8889999'));
UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486' AND CLAVE = 'TEL_EXIGIR_PNM';
EXEC ops.sp_telefonos @id;
SET @o = CONCAT((SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'TELEFONOS' AND MENSAJE LIKE N'%sin plan de numeración: 0 %'), '|',
                (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id AND TELEFONO = '8889999' AND AREA = '01477'));
EXEC pru.sp_igual N'TEL: con TEL_EXIGIR_PNM = 0 sale como fijo (como telbnx.prg)', N'1|1', @o;
UPDATE cfg.PARAMETRO SET VALOR = '1' WHERE CLIENTE = '486' AND CLAVE = 'TEL_EXIGIR_PNM';
UPDATE cfg.PARAMETRO SET VALOR = @base + N'.pru.CAT_PNM' WHERE CLIENTE = '486' AND CLAVE = 'PNM_TABLA';
UPDATE cfg.PARAMETRO SET VALOR = 'LOOP_PRUEBA' WHERE CLIENTE = '486' AND CLAVE = 'TELBAJ_LINKED_SERVER';
UPDATE cfg.PARAMETRO SET VALOR = @base + N'.pru.telbaj' WHERE CLIENTE = '486' AND CLAVE = 'TELBAJ_TABLAS';
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'LOOP_PRUEBA') EXEC sp_dropserver 'LOOP_PRUEBA', 'droplogins';
    EXEC sp_addlinkedserver @server = N'LOOP_PRUEBA', @srvproduct = N'', @provider = N'MSOLEDBSQL', @datasrc = N'localhost',
         @provstr = N'Encrypt=no;TrustServerCertificate=yes';
    EXEC sp_serveroption 'LOOP_PRUEBA', 'data access', 'true';
    EXEC sp_addlinkedsrvlogin @rmtsrvname = N'LOOP_PRUEBA', @useself = N'TRUE';
END TRY
BEGIN CATCH SET @err = ERROR_MESSAGE(); END CATCH;
EXEC ops.sp_telefonos_refrescar_cyber @id;
SET @o = (SELECT CONCAT(COUNT(*), '|', STRING_AGG(CONCAT(LADA, '-', SERIE, '-', TIPORED), '|') WITHIN GROUP (ORDER BY LADA, SERIE)) FROM cfg.PLAN_NUMERACION);
EXEC pru.sp_igual N'TEL CYBER: plan de numeración de CAT_PNM (serie con ceros, MOVIL gana, inválidos fuera)',
     N'3|477-023-FIJO|55-1111-MOVIL|81-0050-MOVIL', @o;
SET @o = (SELECT CONCAT(STRING_AGG(CONCAT(CUENTA, '|', TELEFONO), ',') WITHIN GROUP (ORDER BY CUENTA), NULLIF(CONCAT(' (', @err, ')'), ' ()')) FROM cfg.TEL_QUEJA_CYBER)
       + ISNULL((SELECT TOP (1) CONCAT(' [', LEFT(MENSAJE, 300), ']') FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'TELEFONOS CYBER' AND ESTATUS = 'AVISO'), '');
EXEC pru.sp_igual N'TEL CYBER: quejas del grupo 1 por el servidor vinculado (últimos 10 dígitos de telo y telpho)',
     N'486-200|5511112222,486-201|5533334444', @o;
/* Sin servidor vinculado ni tabla: avisa y conserva lo cargado */
UPDATE cfg.PARAMETRO SET VALOR = 'NO_EXISTE' WHERE CLIENTE = '486' AND CLAVE = 'TELBAJ_LINKED_SERVER';
UPDATE cfg.PARAMETRO SET VALOR = @base + N'.pru.NO_EXISTE' WHERE CLIENTE = '486' AND CLAVE = 'PNM_TABLA';
EXEC ops.sp_telefonos_refrescar_cyber @id;
SET @o = CONCAT((SELECT COUNT(*) FROM cfg.TEL_QUEJA_CYBER), '|', (SELECT COUNT(*) FROM cfg.PLAN_NUMERACION), '|',
                (SELECT COUNT(*) FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'TELEFONOS CYBER' AND ESTATUS = 'AVISO' AND MENSAJE LIKE N'%NO_EXISTE%'));
EXEC pru.sp_igual N'TEL CYBER: sin fuentes avisa y conserva quejas y plan', N'2|3|2', @o;
EXEC ops.sp_corrida_finalizar @id, 'OK', N'Prueba de teléfonos de CYBER';
IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'LOOP_PRUEBA') EXEC sp_dropserver 'LOOP_PRUEBA', 'droplogins';
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
