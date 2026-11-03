--------------------------------------------------------
-- Archivo creado  - lunes-noviembre-02-2026   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Procedure JSP_CORREOS_486
--------------------------------------------------------
set define off;

  CREATE OR REPLACE PROCEDURE "RCVRY"."JSP_CORREOS_486" AS 

BEGIN

EXECUTE IMMEDIATE 'TRUNCATE TABLE JSP_TAB_MAIL_NOREMESA_486';
commit;

INSERT INTO JSP_TAB_MAIL_NOREMESA_486 (CUENTA, CORREO, STATUS, STCOLLID, ORIGEN)(
 SELECT a.adacct, a.adaddr1, a.adstatus, a.adstcollid, a.adcollid
        FROM address a, delqmst c
        WHERE NOT EXISTS (
            SELECT 1
            FROM JSP_TAB_MAIL_REMESA_486 b
            WHERE
                a.adacctg ='1' and
                a.adacct = b.cuenta and
                a.adaddr1 = b.correo
              ) AND
        A.ADACCTG='1' and     
        a.adtype IN ('3','1') AND --&&&se agrega domicilios  24072026 
        A.ADACCT = C.DMACCT AND
        C.DMCOMPANY ='486' AND 
        C.DMSTATus is null
    );
    COMMIT;

 --ELIMINAMOS REGISTROS DUPLICADOS Y CON STATUS INACTIVO
    UPDATE JSP_TAB_MAIL_NOREMESA_486  SET DUP=0 WHERE rowid in (
        SELECT MIN(rowid)
        FROM JSP_TAB_MAIL_NOREMESA_486 
        GROUP BY CUENTA||CORREO
        HAVING count(*) >= 1
    );
    COMMIT;
   
   
    
    DELETE FROM JSP_TAB_MAIL_NOREMESA_486  WHERE DUP IS NULL;
    COMMIT;  
         
     
    UPDATE ADDRESS SET ADSTATUS='I', ADSTCOLLID='HIAS', ADSTATDT=SYSDATE WHERE EXISTS (
            SELECT 1
            FROM JSP_TAB_MAIL_NOREMESA_486 
            WHERE 
                JSP_TAB_MAIL_NOREMESA_486.CUENTA = ADDRESS.ADACCT AND
                JSP_TAB_MAIL_NOREMESA_486.CORREO = ADDRESS.ADADDR1
            ) AND
            UPPER(ADSTCOLLID) NOT IN ('HOMS', 'HPHPI') AND
            ADDRESS.ADACCTG = '1' AND
            ADDRESS.ADSTATUS='A';
    COMMIT;
    
    UPDATE ADDRESS SET ADSTATUS='A', ADSTCOLLID='HAAS', ADSTATDT=SYSDATE WHERE  EXISTS (
            SELECT 1
            FROM JSP_TAB_MAIL_REMESA_486
            WHERE 
                JSP_TAB_MAIL_REMESA_486.CUENTA = ADDRESS.ADACCT AND
                JSP_TAB_MAIL_REMESA_486.CORREO = ADDRESS.ADADDR1
            ) AND
            UPPER(ADSTCOLLID) NOT IN ('HOMS', 'HPHPI') AND
            ADDRESS.ADACCTG ='1' AND 
            ADDRESS.ADSTATUS='I';
    COMMIT;

END JSP_CORREOS_486;

/
