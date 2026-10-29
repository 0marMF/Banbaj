/* =====================================================================
   Banbaj · 45 Teléfonos para CYBER (telbnx.prg + act_phone.prg)
   ---------------------------------------------------------------------
   ops.sp_telefonos arma, solo en la asignación, todos los teléfonos del DAT
   en el formato que acepta CYBER (formato actual, "2019"):
     celular  AREA 044 (lada 55/56) o 045 (resto) + 10 dígitos, TIPOTEL 5
     fijo     AREA 01 + lada (2 o 3 dígitos) + 8 o 7 dígitos, TIPOTEL 1 (TEL1),
              2 (TEL2) o 4 (resto)
   Se mandan completos: el procedimiento de CYBER (RCVRY.JSP_TELEFONOS_REMESA_486)
   purga y agrega. Salen en SCBTEL y en sub_mst.TXT (CUENTA|AREA|TELEFONO|TIPOTEL).

   Reglas de telbnx.prg (validadas contra TELSAN real: mismas 15,353 líneas):
   1. TEL1..TEL16 de cada cuenta; se quitan  espacio - / % # $ & @ \ *
      y se toman los últimos 10 caracteres.
   2. Se descartan: menos de 10 dígitos, con letras, '00000…', 1000000000,
      9999999999, 0999999999 y los que empiezan con 0 (telbnx los borra al final
      porque el área queda '010…').
   3. Un teléfono por cuenta (gana el primero de TEL1..TEL16).
   4. Exclusiones de cfg.EXCLUSION (TIPO TELEFONO): con VALOR2 = cuenta (TELBAJ,
      quejas) o sin VALOR2 (lista negra, teléfonos de dueños del banco).
   5. Lada: 2 dígitos si empieza con LADAS_2_DIGITOS (33, 55, 56, 81), si no 3.
      Celular si cae en un rango MOVIL de cfg.PLAN_NUMERACION (lada, serie, número).
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_telefonos
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @lada2 TABLE (LADA VARCHAR(3) PRIMARY KEY);
    DECLARE @lada044 TABLE (LADA VARCHAR(3) PRIMARY KEY);
    INSERT INTO @lada2 SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'LADAS_2_DIGITOS'), '33,55,56,81'), ',') WHERE LTRIM(RTRIM(value)) <> '';
    INSERT INTO @lada044 SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'LADAS_044'), '55,56'), ',') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @leidos INT, @invalidos INT, @repetidos INT, @quejas INT, @lista_negra INT, @n INT, @msg NVARCHAR(400);

    /* 1. Un renglón por teléfono capturado */
    SELECT d.CUENTA2, v.N,
           RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                 LTRIM(RTRIM(v.TEL)), ' ', ''), '-', ''), '/', ''), '%', ''), '#', ''), '$', ''), '&', ''), '@', ''), '\', ''), '*', ''), 10) AS T
    INTO #t
    FROM dat.DAT_486 d
    CROSS APPLY (VALUES (1, d.TEL1), (2, d.TEL2), (3, d.TEL3), (4, d.TEL4), (5, d.TEL5), (6, d.TEL6), (7, d.TEL7), (8, d.TEL8),
                        (9, d.TEL9), (10, d.TEL10), (11, d.TEL11), (12, d.TEL12), (13, d.TEL13), (14, d.TEL14), (15, d.TEL15),
                        (16, d.TEL16)) v(N, TEL)
    WHERE d.CLIENTE = @cliente AND d.CUENTA2 IS NOT NULL AND NULLIF(LTRIM(RTRIM(v.TEL)), '') IS NOT NULL;
    SET @leidos = @@ROWCOUNT;

    /* 2. Validación */
    DELETE FROM #t
    WHERE LEN(T) < 10 OR T LIKE '%[^0-9]%' OR T LIKE '0%' OR T LIKE '00000%'
       OR T IN ('1000000000', '9999999999', '0999999999');
    SET @invalidos = @@ROWCOUNT;

    /* Lista negra y teléfonos del banco (sin cuenta) */
    DELETE t FROM #t t
    WHERE EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = @cliente AND e.TIPO = 'TELEFONO' AND e.ACTIVO = 1
                    AND e.VALOR = t.T AND e.VALOR2 IS NULL);
    SET @lista_negra = @@ROWCOUNT;

    /* 3. Uno por cuenta: gana el primero de TEL1..TEL16 */
    ;WITH r AS (SELECT ROW_NUMBER() OVER (PARTITION BY CUENTA2, T ORDER BY N) AS RN FROM #t)
    DELETE FROM r WHERE RN > 1;
    SET @repetidos = @@ROWCOUNT;

    /* 4. Quejas (TELBAJ): teléfono dado de baja para esa cuenta */
    DELETE t FROM #t t
    WHERE EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = @cliente AND e.TIPO = 'TELEFONO' AND e.ACTIVO = 1
                    AND e.VALOR = t.T AND e.VALOR2 = t.CUENTA2);
    SET @quejas = @@ROWCOUNT;

    /* 5. Lada, serie y número para clasificar fijo / celular */
    DELETE FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida;

    INSERT INTO ops.TELEFONO (ID_CORRIDA, CUENTA2, AREA, TELEFONO, TIPOTEL, CAMPO_DAT)
    SELECT @id_corrida, t.CUENTA2,
           CASE WHEN m.MOVIL = 1 THEN CASE WHEN EXISTS (SELECT 1 FROM @lada044 x WHERE x.LADA = l.LA2) THEN '044' ELSE '045' END
                ELSE '01' + l.LA2 END,
           CASE WHEN m.MOVIL = 1 THEN t.T ELSE RIGHT(t.T, 10 - LEN(l.LA2)) END,
           CASE WHEN m.MOVIL = 1 THEN '5' WHEN t.N = 1 THEN '1' WHEN t.N = 2 THEN '2' ELSE '4' END,
           CONCAT('TEL', t.N)
    FROM #t t
    CROSS APPLY (SELECT CASE WHEN EXISTS (SELECT 1 FROM @lada2 x WHERE x.LADA = LEFT(t.T, 2)) THEN LEFT(t.T, 2) ELSE LEFT(t.T, 3) END AS LA2) l
    CROSS APPLY (SELECT CASE WHEN LEN(l.LA2) = 2 THEN SUBSTRING(t.T, 3, 4) ELSE SUBSTRING(t.T, 4, 3) END AS SE2,
                        CAST(RIGHT(t.T, 4) AS INT) AS TE2) s
    CROSS APPLY (SELECT CASE WHEN EXISTS (SELECT 1 FROM cfg.PLAN_NUMERACION p
                                          WHERE p.LADA = l.LA2 AND p.SERIE = s.SE2 AND s.TE2 BETWEEN p.N_INI AND p.N_FIN
                                            AND p.TIPORED = 'MOVIL') THEN 1 ELSE 0 END AS MOVIL) m;
    SET @n = @@ROWCOUNT;

    IF NOT EXISTS (SELECT 1 FROM cfg.PLAN_NUMERACION)
        EXEC ops.sp_log @id_corrida, 'TELEFONOS', 'AVISO', NULL, N'cfg.PLAN_NUMERACION está vacío: todos los teléfonos salen como fijos.';

    SET @msg = CONCAT(N'Capturados: ', @leidos, N' · inválidos: ', @invalidos, N' · lista negra/banco: ', @lista_negra,
                      N' · repetidos: ', @repetidos, N' · quejas (TELBAJ): ', @quejas,
                      N' · a CYBER: ', @n, N' (celulares ', (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida AND TIPOTEL = '5'), N')');
    EXEC ops.sp_log @id_corrida, 'TELEFONOS', 'OK', @n, @msg;

    /* Script para CYBER, después de cargar sub_mst.TXT en RCVRY.JSP_TAB_TEL_REMESA_486 (ACTUALIZA_PHONE.SQL).
       El procedimiento vive en CYBER y no se modifica desde aquí. */
    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT IN ('TEL_BORRA', 'TEL_ACTUALIZA');
    /* borra.sql de ACT_PHONE: se vacía la remesa para volver a insertar */
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    VALUES (@id_corrida, 'TEL_BORRA', 1, N'TRUNCATE TABLE RCVRY.JSP_TAB_TEL_REMESA_486;'),
           (@id_corrida, 'TEL_BORRA', 2, N'COMMIT;'),
           (@id_corrida, 'TEL_BORRA', 3, N'EXIT;');
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    VALUES (@id_corrida, 'TEL_ACTUALIZA', 1, CONCAT(N'EXECUTE ', ISNULL(cfg.fn_param(@cliente, 'CYBER_PROC_TELEFONOS'), N'RCVRY.JSP_TELEFONOS_REMESA_486'), N';')),
           (@id_corrida, 'TEL_ACTUALIZA', 2, N'COMMIT;'),
           (@id_corrida, 'TEL_ACTUALIZA', 3, N'exit;');
END;
GO

/* =====================================================================
   ops.sp_asig_normalizar_telefonos (op9.prg "PEGADOS (PROGRAMA B)" + limpia.PRG)
   ---------------------------------------------------------------------
   Antes de dar de alta las cuentas (nuevas y reasignadas) en el DAT, sus
   TEL1..TEL16 se guardan normalizados como AREA + TELEFONO:
     fijo     '01' + lada + número (lada de 2 dígitos: TEL_DAT_LADAS_2 = 33, 55, 81)
     celular  TEL_DAT_AREA_MOVIL ('045') + 10 dígitos (plan de numeración)
   Los inválidos se borran. Solo quita espacios y guiones (como op9).
   Las cuentas que ya estaban en el DAT no pasan por aquí: en paso.prg se
   actualizan con los teléfonos tal como llegan y luego salen del layout.
   Nota: op9 usa ladas 33/55/81 y 045 para todos los celulares; telbnx usa
   33/55/56/81 y 044 para 55/56. Como telbnx vuelve a tomar los últimos 10
   dígitos, lo que llega a CYBER es lo mismo.
   ===================================================================== */
CREATE OR ALTER PROCEDURE ops.sp_asig_normalizar_telefonos
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @movil VARCHAR(3) = ISNULL(cfg.fn_param(@cliente, 'TEL_DAT_AREA_MOVIL'), '045');
    DECLARE @lada2 TABLE (LADA VARCHAR(3) PRIMARY KEY);
    INSERT INTO @lada2 SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'TEL_DAT_LADAS_2'), '33,55,81'), ',') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @n INT, @validos INT, @msg NVARCHAR(400);

    SELECT l.CUENTA, v.N, RIGHT(REPLACE(REPLACE(LTRIM(RTRIM(v.TEL)), ' ', ''), '-', ''), 10) AS T
    INTO #t
    FROM stg.LAYOUT_486 l
    CROSS APPLY (VALUES (1, l.TEL1), (2, l.TEL2), (3, l.TEL3), (4, l.TEL4), (5, l.TEL5), (6, l.TEL6), (7, l.TEL7), (8, l.TEL8),
                        (9, l.TEL9), (10, l.TEL10), (11, l.TEL11), (12, l.TEL12), (13, l.TEL13), (14, l.TEL14), (15, l.TEL15),
                        (16, l.TEL16)) v(N, TEL)
    WHERE l.ID_CORRIDA = @id_corrida AND l.ES_EXISTENTE = 0 AND NULLIF(LTRIM(RTRIM(v.TEL)), '') IS NOT NULL;
    SET @n = @@ROWCOUNT;

    SELECT t.CUENTA, t.N,
           CASE WHEN m.MOVIL = 1 THEN @movil + t.T ELSE '01' + l.LA2 + RIGHT(t.T, 10 - LEN(l.LA2)) END AS V
    INTO #v
    FROM #t t
    CROSS APPLY (SELECT CASE WHEN EXISTS (SELECT 1 FROM @lada2 x WHERE x.LADA = LEFT(t.T, 2)) THEN LEFT(t.T, 2) ELSE LEFT(t.T, 3) END AS LA2) l
    CROSS APPLY (SELECT CASE WHEN LEN(l.LA2) = 2 THEN SUBSTRING(t.T, 3, 4) ELSE SUBSTRING(t.T, 4, 3) END AS SE2,
                        TRY_CONVERT(INT, RIGHT(t.T, 4)) AS TE2) s
    CROSS APPLY (SELECT CASE WHEN EXISTS (SELECT 1 FROM cfg.PLAN_NUMERACION p
                                          WHERE p.LADA = l.LA2 AND p.SERIE = s.SE2 AND s.TE2 BETWEEN p.N_INI AND p.N_FIN
                                            AND p.TIPORED = 'MOVIL') THEN 1 ELSE 0 END AS MOVIL) m
    WHERE LEN(t.T) = 10 AND t.T NOT LIKE '%[^0-9]%' AND t.T NOT LIKE '00000%'
      AND t.T NOT IN ('1000000000', '9999999999', '0999999999') AND TRY_CONVERT(BIGINT, t.T) > 0;
    SET @validos = @@ROWCOUNT;

    UPDATE l SET
        TEL1  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 1),
        TEL2  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 2),
        TEL3  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 3),
        TEL4  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 4),
        TEL5  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 5),
        TEL6  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 6),
        TEL7  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 7),
        TEL8  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 8),
        TEL9  = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 9),
        TEL10 = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 10),
        TEL11 = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 11),
        TEL12 = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 12),
        TEL13 = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 13),
        TEL14 = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 14),
        TEL15 = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 15),
        TEL16 = (SELECT V FROM #v v WHERE v.CUENTA = l.CUENTA AND v.N = 16)
    FROM stg.LAYOUT_486 l
    WHERE l.ID_CORRIDA = @id_corrida AND l.ES_EXISTENTE = 0;

    SET @msg = CONCAT(N'Teléfonos de cuentas nuevas y reasignadas: ', @n, N' · normalizados: ', @validos, N' · borrados por inválidos: ', @n - @validos);
    EXEC ops.sp_log @id_corrida, 'ASIG TELEFONOS DAT', 'OK', @validos, @msg;
END;
GO
