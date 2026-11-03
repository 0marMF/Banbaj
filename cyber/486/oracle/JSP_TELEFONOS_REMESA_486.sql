--------------------------------------------------------
--  Banbaj · Versión optimizada de RCVRY.JSP_TELEFONOS_REMESA_486 (02/11/2026)
--  Sustituye a la versión actual (JSP_TELEFONOS_REMESA_486_actual.sql, 27/12/2025).
--  Hace lo mismo, con menos lecturas de PHONE y de DELQMST:
--
--  1. Teléfonos nuevos: los de la remesa que están en PHONE_G1 (arribo del
--     SCBTEL) y no en PHONE se insertan en PHONE. Antes se copiaba todo
--     PHONE_G1 a la tabla de paso y luego se borraba lo que no iba; ahora se
--     filtra al insertar (cuenta activa del 486, en la remesa, no está en PHONE,
--     sin duplicados) en una sola sentencia.
--     Corrección: el filtro de grupo (phacctg = '1') estaba dentro del
--     NOT EXISTS y no filtraba PHONE_G1; ahora sí se aplica.
--  2. Inactiva (HIAS) los activos del 486 que no vienen en la remesa, salvo
--     gestores de queja (HOMS, HPHPI, BLACK, ZZZTE). La lista se arma ya sin
--     esos gestores (antes se insertaban y luego se borraban).
--  3. Activa (HAAS) los de la remesa que estaban inactivos, salvo esos gestores.
--  4. Marca NUEVO en la remesa en una sola actualización.
--  5. Completa el renglón del día de JSP_VALIDADOR_TELEFONOS (lo inserta el
--     script TEL_BORRA de Banbaj con el total enviado; si no existe, lo crea).
--  6. Si algo falla, deja el error en la bitácora de CYBER y regresa el error.
--
--  Índices recomendados (si no existen):
--     JSP_TAB_TEL_REMESA_486 (CUENTA, AREA, TELEFONO)
--     PHONE_G1 (PHACCT, PHAREACODE, PHPHONE)
--------------------------------------------------------
set define off;

CREATE OR REPLACE PROCEDURE "RCVRY"."JSP_TELEFONOS_REMESA_486" AS
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
    etapa('INSERTANDO TELEFONOS NUEVOS EN JSP_INSERT_PHONE_486', 1);

    EXECUTE IMMEDIATE 'TRUNCATE TABLE JSP_INSERT_PHONE_486';

    /* 1. Nuevos: en PHONE_G1 y en la remesa, de cuenta activa del 486, que no están en PHONE (uno por cuenta/área/teléfono) */
    INSERT INTO JSP_INSERT_PHONE_486
    SELECT a.*
    FROM PHONE_G1 a
    WHERE a.ROWID IN (
        SELECT MIN(g.ROWID)
        FROM PHONE_G1 g
        WHERE g.PHACCTG = c_grupo
          AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_REMESA_486 r
                      WHERE r.CUENTA = g.PHACCT AND r.AREA = g.PHAREACODE AND r.TELEFONO = g.PHPHONE)
          AND EXISTS (SELECT 1 FROM DELQMST d
                      WHERE d.DMACCTG = c_grupo AND d.DMACCT = g.PHACCT AND d.DMCOMPANY = c_cliente AND d.DMSTATUS IS NULL)
          AND NOT EXISTS (SELECT 1 FROM PHONE p
                          WHERE p.PHACCTG = c_grupo AND p.PHACCT = g.PHACCT AND p.PHAREACODE = g.PHAREACODE AND p.PHPHONE = g.PHPHONE)
        GROUP BY g.PHACCT, g.PHAREACODE, g.PHPHONE
    );
    COMMIT;

    etapa('INSERTANDO EN PHONE');
    INSERT INTO PHONE SELECT * FROM JSP_INSERT_PHONE_486;
    COMMIT;

    /* 2. Activos del 486 que no vienen en la remesa (sin gestores de queja) */
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

    /* 3. Los de la remesa que estaban inactivos (sin gestores de queja) */
    etapa('ACTIVANDO TELEFONOS EN REMESA');
    UPDATE PHONE p
    SET p.PHSTCOLLID = 'HAAS', p.PHSTATDT = SYSDATE, p.PHSTATUS = 'A'
    WHERE p.PHACCTG = c_grupo
      AND p.PHSTATUS = 'I'
      AND UPPER(p.PHSTCOLLID) NOT IN ('HOMS', 'HPHPI', 'BLACK', 'ZZZTE')
      AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_REMESA_486 r
                  WHERE r.CUENTA = p.PHACCT AND r.AREA = p.PHAREACODE AND r.TELEFONO = p.PHPHONE);
    COMMIT;

    /* 4. NUEVO = 1 si el teléfono de la remesa no quedó en PHONE */
    etapa('SACANDO TELEFONOS NUEVOS');
    UPDATE JSP_TAB_TEL_REMESA_486 r
    SET r.NUEVO = CASE WHEN EXISTS (SELECT 1 FROM PHONE p
                                    WHERE p.PHACCTG = c_grupo AND p.PHACCT = r.CUENTA AND p.PHAREACODE = r.AREA AND p.PHPHONE = r.TELEFONO)
                       THEN 0 ELSE 1 END;
    COMMIT;

    /* 5. Validador del día */
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
        HISTORICOS_INSERTADOS = (SELECT COUNT(*) FROM JSP_INSERT_PHONE_486),
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
END JSP_TELEFONOS_REMESA_486;
/
