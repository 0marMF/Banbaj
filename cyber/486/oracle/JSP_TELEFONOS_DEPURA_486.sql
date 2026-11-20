--------------------------------------------------------
--  Banbaj · RCVRY.JSP_TELEFONOS_DEPURA_486 (19/11/2026)
--  Depuración de teléfonos del 486 por diferencia. Reemplaza la versión del
--  18/11 (que recibía la remesa completa).
--
--  Banbaj (SQL Server) baja una foto de PHONE de las cuentas activas del 486,
--  la compara con sus teléfonos y solo sube lo que cambia a
--  RCVRY.JSP_TAB_TEL_DEPURA_486:
--     ACCION = 'I'  activo en CYBER que ya no viene: se inactiva (HIAS)
--     ACCION = 'A'  inactivo en CYBER que sí viene: se activa (HAAS)
--     ACCION = 'N'  no existe en PHONE: lo da de alta el SCBTEL (aquí solo se cuenta)
--  Antes de llamar a este store, Banbaj enciende la bandera (p_proc, 416) en
--  RPT_LOG_CYBER_REG / RPT_LOG_CYBER y revisa que la tabla tenga los renglones
--  que mandó; al terminar (o si falla) la apaga.
--
--  Este store:
--  1. Revisa que la tabla tenga p_esperados renglones (si no, error y no toca PHONE).
--  2. Inactiva los 'I' que sigan activos y los 'A' que sigan inactivos los activa,
--     nunca los de gestores de queja (HOMS, HPHPI, BLACK, ZZZTE).
--  3. Completa el renglón del día de JSP_VALIDADOR_TELEFONOS (lo inserta el
--     script TEL_BORRA de Banbaj con el total de teléfonos; si no existe, lo crea).
--  4. Deja cada etapa en RPT_LOG_CYBER con el id de la bandera; si algo falla,
--     deja el error ahí y lo regresa.
--
--  Instalación (DBA de CYBER), con el usuario dueño de RCVRY:
--     @JSP_TELEFONOS_DEPURA_486.sql
--     GRANT SELECT, INSERT, DELETE ON RCVRY.JSP_TAB_TEL_DEPURA_486 TO <usuario de CYBER_ORACLE>;
--     GRANT EXECUTE ON RCVRY.JSP_TELEFONOS_DEPURA_486 TO <usuario de CYBER_ORACLE>;
--  El usuario de CYBER_ORACLE además necesita SELECT en RCVRY.PHONE y
--  RCVRY.DELQMST (la foto) y UPDATE/INSERT en RCVRY.RPT_LOG_CYBER_REG y
--  RCVRY.RPT_LOG_CYBER (la bandera, como en correos), y poder vaciar
--  JSP_TAB_TEL_DEPURA_486 con TRUNCATE, igual que hoy vacía JSP_TAB_TEL_REMESA_486.
--  Después, en Banbaj:
--     UPDATE cfg.PARAMETRO SET VALOR = 'DIFERENCIA' WHERE CLIENTE = '486' AND CLAVE = 'TEL_DEPURACION';
--
--  Índices recomendados (si no existen):
--     JSP_TAB_TEL_DEPURA_486 (CUENTA, AREA, TELEFONO)
--     PHONE (PHACCTG, PHACCT, PHAREACODE, PHPHONE)
--------------------------------------------------------
set define off;

DECLARE
    v_n NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_n FROM ALL_TABLES WHERE OWNER = 'RCVRY' AND TABLE_NAME = 'JSP_TAB_TEL_DEPURA_486';
    IF v_n = 0 THEN
        EXECUTE IMMEDIATE 'CREATE TABLE RCVRY.JSP_TAB_TEL_DEPURA_486 (
                               CUENTA   VARCHAR2(28) NOT NULL,
                               AREA     VARCHAR2(10) NOT NULL,
                               TELEFONO VARCHAR2(20) NOT NULL,
                               ACCION   CHAR(1)      NOT NULL CHECK (ACCION IN (''I'', ''A'', ''N'')))';
        EXECUTE IMMEDIATE 'CREATE INDEX RCVRY.IX_JSP_TAB_TEL_DEPURA_486 ON RCVRY.JSP_TAB_TEL_DEPURA_486 (CUENTA, AREA, TELEFONO)';
    END IF;
END;
/

CREATE OR REPLACE PROCEDURE "RCVRY"."JSP_TELEFONOS_DEPURA_486" (
    p_proc      IN NUMBER DEFAULT 416,     -- id_proc de la bandera (la enciende y apaga Banbaj)
    p_esperados IN NUMBER DEFAULT NULL,    -- renglones que Banbaj mandó a JSP_TAB_TEL_DEPURA_486
    p_quejas    IN NUMBER DEFAULT 0        -- teléfonos nuestros que CYBER tiene con gestor de queja (para el validador)
) AS
    c_grupo    CONSTANT VARCHAR2(5)  := '1';
    c_cliente  CONSTANT VARCHAR2(5)  := '486';
    v_paso     NUMBER := 2;
    v_tabla    NUMBER;
    v_inac     NUMBER := 0;
    v_act      NUMBER := 0;
    v_nuevos   NUMBER := 0;

    PROCEDURE etapa (p_texto VARCHAR2) IS
    BEGIN
        v_paso := v_paso + 1;
        UPDATE RPT_LOG_CYBER_REG SET ETAPA = p_texto WHERE ID_PROC = p_proc;
        INSERT INTO RPT_LOG_CYBER VALUES (p_proc, v_paso, SYSDATE, 'PRODUCCION', p_texto);
        COMMIT;
    END;
BEGIN
    etapa('INICIANDO DEPURACION DE TELEFONOS 486 (DIFERENCIA)');

    /* 1. Lo que mandó Banbaj */
    SELECT COUNT(*), NVL(SUM(CASE WHEN ACCION = 'N' THEN 1 ELSE 0 END), 0)
      INTO v_tabla, v_nuevos
      FROM JSP_TAB_TEL_DEPURA_486;
    IF p_esperados IS NOT NULL AND v_tabla <> p_esperados THEN
        RAISE_APPLICATION_ERROR(-20486, 'JSP_TAB_TEL_DEPURA_486 tiene ' || v_tabla || ' renglones y Banbaj mandó ' || p_esperados || '; no se toca PHONE');
    END IF;

    /* 2. Inactivar los que ya no vienen (si siguen activos y no son de queja) */
    etapa('INACTIVANDO TELEFONOS QUE YA NO VIENEN 486');
    UPDATE PHONE p
    SET p.PHSTCOLLID = 'HIAS', p.PHSTATDT = SYSDATE, p.PHSTATUS = 'I'
    WHERE p.PHACCTG = c_grupo
      AND p.PHSTATUS = 'A'
      AND UPPER(NVL(p.PHSTCOLLID, ' ')) NOT IN ('HOMS', 'HPHPI', 'BLACK', 'ZZZTE')
      AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_DEPURA_486 r
                  WHERE r.ACCION = 'I' AND r.CUENTA = p.PHACCT AND r.AREA = p.PHAREACODE AND r.TELEFONO = p.PHPHONE);
    v_inac := SQL%ROWCOUNT;
    COMMIT;

    /* 3. Activar los que vienen y estaban inactivos (sin gestores de queja) */
    etapa('ACTIVANDO TELEFONOS QUE VIENEN 486');
    UPDATE PHONE p
    SET p.PHSTCOLLID = 'HAAS', p.PHSTATDT = SYSDATE, p.PHSTATUS = 'A'
    WHERE p.PHACCTG = c_grupo
      AND p.PHSTATUS = 'I'
      AND UPPER(NVL(p.PHSTCOLLID, ' ')) NOT IN ('HOMS', 'HPHPI', 'BLACK', 'ZZZTE')
      AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_DEPURA_486 r
                  WHERE r.ACCION = 'A' AND r.CUENTA = p.PHACCT AND r.AREA = p.PHAREACODE AND r.TELEFONO = p.PHPHONE);
    v_act := SQL%ROWCOUNT;
    COMMIT;

    /* 4. Validador del día (TOTAL_TELS lo pone el script TEL_BORRA de Banbaj) */
    etapa('ACTUALIZANDO BITACORA');
    INSERT INTO JSP_VALIDADOR_TELEFONOS (CLIENTE, FECHA, TOTAL_TELS)
    SELECT c_cliente, SYSDATE, NULL FROM DUAL
    WHERE NOT EXISTS (SELECT 1 FROM JSP_VALIDADOR_TELEFONOS
                      WHERE CLIENTE = c_cliente AND FIN IS NULL AND TRUNC(FECHA) = TRUNC(SYSDATE));

    UPDATE JSP_VALIDADOR_TELEFONOS v
    SET DIF_TELSAN_ARRI       = NVL(p_esperados, v_tabla) - v_tabla,
        TELS_INACTIVOS        = NVL(p_quejas, 0),
        VALIDAR_LADA          = (SELECT COUNT(*) FROM JSP_TAB_TEL_DEPURA_486 r
                                 WHERE r.ACCION = 'N' AND NOT EXISTS (SELECT 1 FROM PHNVAL x WHERE x.VTARECOD = r.AREA)),
        TOT_ACT               = v_act,
        TOT_INAC              = v_inac,
        HISTORICOS_INSERTADOS = 0,   -- los nuevos los da de alta el SCBTEL
        NUEVOS                = v_nuevos,
        FIN                   = TO_CHAR(SYSDATE, 'HH24:MI:SS')
    WHERE v.CLIENTE = c_cliente AND v.FIN IS NULL AND TRUNC(v.FECHA) = TRUNC(SYSDATE);
    COMMIT;

    etapa('DEPURACION TERMINADA: ' || v_inac || ' INACTIVADOS, ' || v_act || ' ACTIVADOS, ' || v_nuevos || ' NUEVOS PARA SCBTEL');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        UPDATE RPT_LOG_CYBER_REG SET ETAPA = SUBSTR('ERROR: ' || SQLERRM, 1, 200) WHERE ID_PROC = p_proc;
        INSERT INTO RPT_LOG_CYBER VALUES (p_proc, 99, SYSDATE, 'PRODUCCION', SUBSTR('ERROR: ' || SQLERRM, 1, 200));
        COMMIT;
        RAISE;
END JSP_TELEFONOS_DEPURA_486;
/
