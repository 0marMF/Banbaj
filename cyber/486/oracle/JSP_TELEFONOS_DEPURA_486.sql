--------------------------------------------------------
--  Banbaj · RCVRY.JSP_TELEFONOS_DEPURA_486 (18/11/2026)
--  Depuración de teléfonos del 486 con el orden del equipo: corre DESPUÉS de
--  que suben los saldos y ANTES del SCBTEL. El SCBTEL ya solo lleva los
--  teléfonos nuevos que marca este store, y al subirlo quedan activos.
--
--  Con la remesa completa (RCVRY.JSP_TAB_TEL_REMESA_486, que Banbaj carga y
--  cuadra contra su archivo antes de ejecutar esto):
--  1. Inactiva (HIAS) todo lo activo de las cuentas activas del 486 que no
--     viene en la remesa, incluido lo que un gestor haya agregado hace un
--     momento, salvo gestores de queja (HOMS, HPHPI, BLACK, ZZZTE).
--  2. Activa (HAAS) lo de la remesa que estaba inactivo, salvo esos gestores.
--  3. Marca NUEVO = 1 en la remesa lo que no existe en PHONE: es lo único
--     que va en el SCBTEL (Banbaj lo baja de aquí).
--  4. Completa el renglón del día de JSP_VALIDADOR_TELEFONOS (lo inserta el
--     script TEL_BORRA de Banbaj con el total enviado; si no existe, lo crea).
--  5. Si algo falla, deja el error en la bitácora de CYBER (id 376) y regresa
--     el error.
--
--  Ya no inserta en PHONE desde PHONE_G1 (JSP_INSERT_PHONE_486): antes el
--  SCBTEL se subía primero; ahora llega después y él da de alta los nuevos.
--
--  Instalación (DBA de CYBER), con el usuario dueño de RCVRY:
--     @JSP_TELEFONOS_DEPURA_486.sql
--     GRANT EXECUTE ON RCVRY.JSP_TELEFONOS_DEPURA_486 TO <usuario de CYBER_ORACLE>;
--  Después, en Banbaj:
--     UPDATE cfg.PARAMETRO SET VALOR = 'NUEVOS' WHERE CLIENTE = '486' AND CLAVE = 'TEL_DEPURACION';
--  Para bajar los nuevos, el usuario de CYBER_ORACLE usa el SELECT en
--  RCVRY.JSP_TAB_TEL_REMESA_486 que ya tiene para el conteo.
--
--  Índices recomendados (si no existen):
--     JSP_TAB_TEL_REMESA_486 (CUENTA, AREA, TELEFONO)
--     PHONE (PHACCTG, PHACCT, PHAREACODE, PHPHONE)
--------------------------------------------------------
set define off;

CREATE OR REPLACE PROCEDURE "RCVRY"."JSP_TELEFONOS_DEPURA_486" AS
    c_proc     CONSTANT NUMBER       := 376;
    c_grupo    CONSTANT VARCHAR2(5)  := '1';
    c_cliente  CONSTANT VARCHAR2(5)  := '486';
    v_paso     NUMBER := 2;
    v_remesa   NUMBER;

    PROCEDURE etapa (p_texto VARCHAR2, p_status NUMBER DEFAULT NULL) IS
    BEGIN
        v_paso := v_paso + 1;
        UPDATE RPT_LOG_CYBER_REG SET ETAPA = p_texto, STATUS = NVL(p_status, STATUS) WHERE ID_PROC = c_proc;
        INSERT INTO RPT_LOG_CYBER VALUES (c_proc, v_paso, SYSDATE, 'PRODUCCION', p_texto);
        COMMIT;
    END;
BEGIN
    etapa('INICIANDO DEPURACION DE TELEFONOS 486', 1);

    /* 1. Activos del 486 que no vienen en la remesa (sin gestores de queja) */
    etapa('ARMANDO TELEFONOS FUERA DE REMESA');
    EXECUTE IMMEDIATE 'TRUNCATE TABLE JSP_TAB_TEL_NO_REMESA_486';
    INSERT INTO JSP_TAB_TEL_NO_REMESA_486 (CUENTA, AREA, TELEFONO, GESTOR, STGESTOR)
    SELECT p.PHACCT, p.PHAREACODE, p.PHPHONE, p.PHCOLLID, p.PHSTCOLLID
    FROM PHONE p
    WHERE p.PHACCTG = c_grupo
      AND p.PHSTATUS = 'A'
      AND UPPER(p.PHSTCOLLID) NOT IN ('HOMS', 'HPHPI', 'BLACK', 'ZZZTE')
      AND EXISTS (SELECT 1 FROM DELQMST d
                  WHERE d.DMACCTG = c_grupo AND d.DMACCT = p.PHACCT AND d.DMCOMPANY = c_cliente AND d.DMSTATUS IS NULL)
      AND NOT EXISTS (SELECT 1 FROM JSP_TAB_TEL_REMESA_486 r
                      WHERE r.CUENTA = p.PHACCT AND r.AREA = p.PHAREACODE AND r.TELEFONO = p.PHPHONE);
    COMMIT;

    etapa('INACTIVANDO TELEFONOS FUERA DE REMESA 486');
    UPDATE PHONE p
    SET p.PHSTCOLLID = 'HIAS', p.PHSTATDT = SYSDATE, p.PHSTATUS = 'I'
    WHERE p.PHACCTG = c_grupo
      AND p.PHSTATUS = 'A'
      AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_NO_REMESA_486 n
                  WHERE n.CUENTA = p.PHACCT AND n.AREA = p.PHAREACODE AND n.TELEFONO = p.PHPHONE);
    COMMIT;

    /* 2. Los de la remesa que estaban inactivos (sin gestores de queja) */
    etapa('ACTIVANDO TELEFONOS EN REMESA');
    UPDATE PHONE p
    SET p.PHSTCOLLID = 'HAAS', p.PHSTATDT = SYSDATE, p.PHSTATUS = 'A'
    WHERE p.PHACCTG = c_grupo
      AND p.PHSTATUS = 'I'
      AND UPPER(p.PHSTCOLLID) NOT IN ('HOMS', 'HPHPI', 'BLACK', 'ZZZTE')
      AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_REMESA_486 r
                  WHERE r.CUENTA = p.PHACCT AND r.AREA = p.PHAREACODE AND r.TELEFONO = p.PHPHONE);
    COMMIT;

    /* 3. NUEVO = 1 si el teléfono de la remesa no quedó en PHONE */
    etapa('SACANDO TELEFONOS NUEVOS');
    UPDATE JSP_TAB_TEL_REMESA_486 r
    SET r.NUEVO = CASE WHEN EXISTS (SELECT 1 FROM PHONE p
                                    WHERE p.PHACCTG = c_grupo AND p.PHACCT = r.CUENTA AND p.PHAREACODE = r.AREA AND p.PHPHONE = r.TELEFONO)
                       THEN 0 ELSE 1 END;
    COMMIT;

    /* 4. Validador del día */
    etapa('ACTUALIZANDO BITACORA');
    SELECT COUNT(*) INTO v_remesa FROM JSP_TAB_TEL_REMESA_486;

    INSERT INTO JSP_VALIDADOR_TELEFONOS (CLIENTE, FECHA, TOTAL_TELS)
    SELECT c_cliente, SYSDATE, v_remesa FROM DUAL
    WHERE NOT EXISTS (SELECT 1 FROM JSP_VALIDADOR_TELEFONOS
                      WHERE CLIENTE = c_cliente AND FIN IS NULL AND TRUNC(FECHA) = TRUNC(SYSDATE));

    UPDATE JSP_VALIDADOR_TELEFONOS v
    SET DIF_TELSAN_ARRI       = v.TOTAL_TELS - v_remesa,
        TELS_INACTIVOS        = (SELECT COUNT(*) FROM PHONE p
                                 WHERE p.PHACCTG = c_grupo AND UPPER(p.PHSTCOLLID) IN ('HOMS', 'HPHPI', 'BLACK', 'ZZZTE')
                                   AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_REMESA_486 r
                                               WHERE r.CUENTA = p.PHACCT AND r.AREA = p.PHAREACODE AND r.TELEFONO = p.PHPHONE)),
        VALIDAR_LADA          = (SELECT COUNT(*) FROM JSP_TAB_TEL_REMESA_486 r
                                 WHERE NOT EXISTS (SELECT 1 FROM PHNVAL x WHERE x.VTARECOD = r.AREA)),
        TOT_ACT               = (SELECT COUNT(*) FROM PHONE p
                                 WHERE p.PHACCTG = c_grupo AND p.PHSTCOLLID = 'HAAS' AND p.PHSTATDT >= TRUNC(SYSDATE)
                                   AND EXISTS (SELECT 1 FROM DELQMST d WHERE d.DMACCTG = c_grupo AND d.DMACCT = p.PHACCT
                                                 AND d.DMCOMPANY = c_cliente AND d.DMSTATUS IS NULL)),
        TOT_INAC              = (SELECT COUNT(*) FROM PHONE p
                                 WHERE p.PHACCTG = c_grupo AND p.PHSTCOLLID = 'HIAS' AND p.PHSTATDT >= TRUNC(SYSDATE)
                                   AND EXISTS (SELECT 1 FROM DELQMST d WHERE d.DMACCTG = c_grupo AND d.DMACCT = p.PHACCT
                                                 AND d.DMCOMPANY = c_cliente AND d.DMSTATUS IS NULL)),
        HISTORICOS_INSERTADOS = 0,   -- ya no se insertan desde PHONE_G1: los nuevos los da de alta el SCBTEL
        NUEVOS                = (SELECT COUNT(*) FROM JSP_TAB_TEL_REMESA_486 WHERE NUEVO = 1),
        FIN                   = TO_CHAR(SYSDATE, 'HH24:MI:SS')
    WHERE v.CLIENTE = c_cliente AND v.FIN IS NULL AND TRUNC(v.FECHA) = TRUNC(SYSDATE);
    COMMIT;

    etapa('FINALIZANDO PROCESO', 0);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        UPDATE RPT_LOG_CYBER_REG SET STATUS = 0, ETAPA = SUBSTR('ERROR: ' || SQLERRM, 1, 200) WHERE ID_PROC = c_proc;
        INSERT INTO RPT_LOG_CYBER VALUES (c_proc, 99, SYSDATE, 'PRODUCCION', SUBSTR('ERROR: ' || SQLERRM, 1, 200));
        COMMIT;
        RAISE;
END JSP_TELEFONOS_DEPURA_486;
/
