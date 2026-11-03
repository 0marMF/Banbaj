--------------------------------------------------------
-- Archivo creado  - lunes-noviembre-02-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Procedure JSP_TELEFONOS_REMESA_486
--------------------------------------------------------
set define off;

  CREATE OR REPLACE PROCEDURE "RCVRY"."JSP_TELEFONOS_REMESA_486" AS 
BEGIN

 /*
      CREADO POR:       ABKUX
      FECHA:            27/12/2025
      ULTIMA ACT:       
      SOLICITADO POR:   ERIKA CARMONA
    */
    
    DECLARE
    
        CNTC INT;
        GRUPO2 VARCHAR2(5);
        CLIENTE2 VARCHAR2(5);
        CLIENTE3 VARCHAR2(5);
        CLIENTE4 VARCHAR2(5);

    BEGIN
    
        GRUPO2 := '1';
        CLIENTE2 := '486';
        CLIENTE3 := '';
        CLIENTE4 := '';
        
        /*--------------------------------------------------------------------------------------------------------------------------------------------------------*/
        /*------------------------------------------------------COMIENZA INSERCION DE TELEFONOS EN REMESA---------------------------------------------------------*/
        /*--------------------------------------------------------------------------------------------------------------------------------------------------------*/
        
                UPDATE RPT_LOG_CYBER_REG SET ETAPA='TRUNCANDO TABLA JSP_INSERT_PHONE_486',status=1 where id_proc=376;
                INSERT INTO rpt_log_cyber VALUES(376,3,SYSDATE,'PRODUCCION','TRUNCANDO TABLA JSP_INSERT_PHONE_486');
                COMMIT;
     
        --TRUNCANDO TABLA DE PASO
        EXECUTE IMMEDIATE 'TRUNCATE TABLE JSP_INSERT_PHONE_486';
        COMMIT;
                        
                UPDATE RPT_LOG_CYBER_REG SET ETAPA='INSERTANDO REGISTROS EN JSP_INSERT_PHONE_486' where id_proc=376;
                INSERT INTO rpt_log_cyber VALUES(376,4,SYSDATE,'PRODUCCION','INSERTANDO REGISTROS EN JSP_INSERT_PHONE_486');
                COMMIT;
        
        --INSERTANDO EN TABLA DE PASO
        INSERT INTO JSP_INSERT_PHONE_486 (
            SELECT a.*
            FROM PHONE_G1 a
            WHERE NOT EXISTS (
                SELECT 1
                FROM phone b
                WHERE 
                    a.phacctg = GRUPO2 and
                    a.phacct = b.phacct and
                    a.phareacode = b.phareacode and
                    a.phphone = b.phphone
            ) AND
            a.phacct IN (SELECT dmacct FROM DELQMST WHERE dmacctg = GRUPO2 AND dmcompany IN (CLIENTE2, CLIENTE3, CLIENTE4) AND dmstatus IS NULL)
        );
        COMMIT;
        
                UPDATE RPT_LOG_CYBER_REG set ETAPA='ELIMINA REGISTROS TABLA DE PASO' where id_proc=376;
                INSERT INTO rpt_log_cyber VALUES(376,5,SYSDATE,'PRODUCCION','ELIMINA REGISTROS TABLA DE PASO');
                COMMIT;
        
        -- ELIMINANDO DATOS QUE ESTAN EN PRODUCTIVO
        DELETE FROM JSP_INSERT_PHONE_486
        WHERE
          EXISTS (
            SELECT 1
            FROM PHONE
            WHERE
              PHONE.PHACCTG = '1' AND
              PHONE.PHACCT = JSP_INSERT_PHONE_486.PHACCT AND
              PHONE.PHAREACODE = JSP_INSERT_PHONE_486.PHAREACODE AND
              PHONE.PHPHONE = JSP_INSERT_PHONE_486.PHPHONE
          );
        COMMIT;
  
        --BORRANDO TELEFONOS FUERA DE REMESA
        DELETE FROM JSP_INSERT_PHONE_486
        WHERE NOT EXISTS (
          SELECT 1
          FROM JSP_TAB_TEL_REMESA_486
          WHERE
            JSP_INSERT_PHONE_486.PHACCT = JSP_TAB_TEL_REMESA_486.CUENTA AND
            JSP_INSERT_PHONE_486.PHAREACODE = JSP_TAB_TEL_REMESA_486.AREA AND
            JSP_INSERT_PHONE_486.PHPHONE = JSP_TAB_TEL_REMESA_486.TELEFONO
        );
            
                UPDATE RPT_LOG_CYBER_REG set ETAPA='VALIDANDO REGISTROS DUPLICADOS' where id_proc=376;
                INSERT INTO rpt_log_cyber VALUES(376,6,SYSDATE,'PRODUCCION','VALIDANDO REGISTROS DUPLICADOS');
                COMMIT;
    
        ---- VALIDACION FINAL DE DUPLICADAS 
        DELETE FROM JSP_INSERT_PHONE_486 WHERE rowid not in (
            SELECT MIN(rowid)
            FROM JSP_INSERT_PHONE_486
            GROUP BY phacct, phareacode, phphone
            HAVING count(*) >= 1);
        COMMIT;
        
                UPDATE RPT_LOG_CYBER_REG set ETAPA='INSERTANDO EN PHONE' where id_proc=376;
                INSERT INTO rpt_log_cyber VALUES(376,7,SYSDATE,'PRODUCCION','INSERTANDO EN PHONE');
                COMMIT;
    
        --INSERTANDO EN LA PHONE
        INSERT INTO PHONE SELECT * FROM JSP_INSERT_PHONE_486;
        COMMIT;
        
        /*--------------------------------------------------------------------------------------------------------------------------------------------------------*/
        /*----------------------------------------------------------COMIENZA ACTIVACION E INACTIVACION------------------------------------------------------------*/
        /*--------------------------------------------------------------------------------------------------------------------------------------------------------*/
              
                UPDATE RPT_LOG_CYBER_REG set ETAPA='TRUNCANDO TABLA JSP_TAB_TEL_NO_REMESA_486' where id_proc=376;
                INSERT INTO rpt_log_cyber VALUES(376,8,SYSDATE,'PRODUCCION','TRUNCANDO TABLA JSP_TAB_TEL_NO_REMESA_486');
                COMMIT;
        
        EXECUTE IMMEDIATE 'TRUNCATE TABLE JSP_TAB_TEL_NO_REMESA_486';
        COMMIT;
        
        UPDATE JSP_TAB_TEL_REMESA_486
        SET NUEVO = 0;
        COMMIT;
        
                UPDATE RPT_LOG_CYBER_REG set ETAPA='INSERTANDO TELEFONOS FUERA DE REMESA' where id_proc=376;
                INSERT INTO rpt_log_cyber VALUES(376,9,SYSDATE,'PRODUCCION','INSERTANDO TELEFONOS FUERA DE REMESA');
                COMMIT;

        INSERT INTO JSP_TAB_TEL_NO_REMESA_486 (cuenta, area, telefono, gestor, stgestor) (
            SELECT a.phacct, a.phareacode, a.phphone, a.phcollid, a.phstcollid
            FROM PHONE a
            WHERE 
                a.phacctg = GRUPO2 AND
                a.phacct IN (SELECT dmacct FROM DELQMST WHERE dmacctg = GRUPO2 AND dmcompany IN (CLIENTE2, CLIENTE3, CLIENTE4) AND dmstatus IS NULL) AND
                a.phstatus = 'A' AND
                NOT EXISTS (
                    SELECT 1
                    FROM JSP_TAB_TEL_REMESA_486 b
                    WHERE 
                        a.phacct = b.cuenta and
                        a.phareacode = b.area and
                        a.phphone = b.telefono
                )
        );
        COMMIT;
        
        UPDATE RPT_LOG_CYBER_REG set ETAPA='QUITANDO TLEEFONOS DE QUEJAS' where id_proc=376;
            INSERT INTO rpt_log_cyber VALUES(376,10,SYSDATE,'PRODUCCION','QUITANDO TELEFONOS DE QUEJAS');
            COMMIT;
        
        DELETE FROM JSP_TAB_TEL_NO_REMESA_486
        WHERE UPPER(stgestor) IN ('HOMS', 'HPHPI','BLACK','ZZZTE');
        COMMIT;
        
            UPDATE RPT_LOG_CYBER_REG set ETAPA='INACTIVANDO TELEFONOS FUERA DE REMESA' where id_proc=376;
            INSERT INTO rpt_log_cyber VALUES(376,11,SYSDATE,'PRODUCCION','INACTIVANDO TELEFONOS FUERA DE REMESA 486');
            COMMIT;
            
       --- aabpy 10/03/2026 Lupita pide descomentar
        UPDATE PHONE
        SET phstcollid = 'HIAS', phstatdt = SYSDATE, phstatus = 'I'
        WHERE
            phacctg = GRUPO2 AND
            EXISTS (
                SELECT 1
                FROM JSP_TAB_TEL_NO_REMESA_486
                WHERE
                    PHONE.phacct = JSP_TAB_TEL_NO_REMESA_486.cuenta AND
                    PHONE.phareacode = JSP_TAB_TEL_NO_REMESA_486.area AND
                    PHONE.phphone = JSP_TAB_TEL_NO_REMESA_486.telefono
        );
        COMMIT;
        
            UPDATE RPT_LOG_CYBER_REG set ETAPA='ACTIVANDO TELEFONOS EN REMESA' where id_proc=376;
            INSERT INTO rpt_log_cyber VALUES(376,12,SYSDATE,'PRODUCCION','ACTIVANDO TELEFONOS EN REMESA');
            COMMIT;
            
       
        UPDATE PHONE
        SET phstcollid = 'HAAS', phstatdt = SYSDATE, phstatus = 'A'
        WHERE
            phacctg = GRUPO2 AND
            phstatus = 'I' AND
            UPPER(phstcollid) NOT IN ('HOMS', 'HPHPI','BLACK','ZZZTE') AND
            EXISTS (
                SELECT 1
                FROM JSP_TAB_TEL_REMESA_486
                WHERE
                    PHONE.phacct = JSP_TAB_TEL_REMESA_486.cuenta AND
                    PHONE.phareacode = JSP_TAB_TEL_REMESA_486.area AND
                    PHONE.phphone = JSP_TAB_TEL_REMESA_486.telefono
            );
        COMMIT;
       
            UPDATE RPT_LOG_CYBER_REG set ETAPA='SACANDO TELEFONOS NUEVOS' where id_proc=376;
            INSERT INTO rpt_log_cyber VALUES(376,13,SYSDATE,'PRODUCCION','SACANDO TELEFONOS NUEVOS');
            COMMIT;
        
        --VALIDANDO TELEFONOS NUEVOS
        UPDATE JSP_TAB_TEL_REMESA_486 
            SET nuevo = 1 
            WHERE NOT EXISTS (
                SELECT 1 
                FROM PHONE
                WHERE
                    cuenta = phacct AND
                    area = phareacode AND
                    telefono = phphone
            );
        COMMIT;
            
            UPDATE RPT_LOG_CYBER_REG set ETAPA='ACTUALIZANDO BITACORA' where id_proc=376;
            INSERT INTO rpt_log_cyber VALUES(376,14,SYSDATE,'PRODUCCION','ACTUALIZANDO BITACORA');
            COMMIT;
            
        SELECT COUNT(*) INTO CNTC
        FROM JSP_TAB_TEL_REMESA_486;
            
        UPDATE JSP_VALIDADOR_TELEFONOS
        SET 
          DIF_TELSAN_ARRI = TOTAL_TELS - CNTC,
          TELS_INACTIVOS = (SELECT COUNT(*) FROM PHONE WHERE PHACCTG = GRUPO2 AND UPPER(PHSTCOLLID) IN ('HOMS', 'HPHPI','BLACK','ZZZTE') AND EXISTS (SELECT 1 FROM JSP_TAB_TEL_REMESA_486 WHERE PHACCT = CUENTA AND PHAREACODE = AREA AND PHPHONE = TELEFONO)),
          VALIDAR_LADA = (SELECT COUNT(*) FROM JSP_TAB_TEL_REMESA_486 WHERE AREA NOT IN (SELECT VTARECOD FROM PHNVAL)),
          TOT_ACT = (SELECT COUNT(*) FROM PHONE WHERE PHACCTG = GRUPO2 AND UPPER(PHSTCOLLID) = 'HAAS' AND TRUNC(PHSTATDT) = TRUNC(SYSDATE) AND PHACCT IN (SELECT DMACCT FROM DELQMST WHERE DMACCTG = GRUPO2 AND DMCOMPANY IN (CLIENTE2, CLIENTE3, CLIENTE4) AND DMSTATUS IS NULL)),
          TOT_INAC = (SELECT COUNT(*) FROM PHONE WHERE PHACCTG = GRUPO2 AND UPPER(PHSTCOLLID) = 'HIAS' AND TRUNC(PHSTATDT) = TRUNC(SYSDATE) AND PHACCT IN (SELECT DMACCT FROM DELQMST WHERE DMACCTG = GRUPO2 AND DMCOMPANY IN (CLIENTE2, CLIENTE3, CLIENTE4) AND DMSTATUS IS NULL)),
          HISTORICOS_INSERTADOS = (SELECT COUNT(*) FROM JSP_INSERT_PHONE_486),
          NUEVOS = (SELECT COUNT(*) FROM JSP_TAB_TEL_REMESA_486 WHERE NUEVO = 1),
          FIN = TO_CHAR(SYSDATE, 'HH24:MI:SS')
        WHERE
          CLIENTE = CLIENTE2 AND
          FIN IS NULL AND
          TRUNC(FECHA) = TRUNC(SYSDATE);
            
        UPDATE RPT_LOG_CYBER_REG SET STATUS = 0, ETAPA = 'FINALIZANDO PROCESO' where id_proc=376;
        INSERT INTO rpt_log_cyber VALUES(376,15,SYSDATE,'PRODUCCION','FINALIZANDO PROCESO');
        COMMIT;
        
    END;


END JSP_TELEFONOS_REMESA_486  ;

/
