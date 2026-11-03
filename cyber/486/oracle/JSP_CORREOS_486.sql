--------------------------------------------------------
--  Banbaj · Propuesta de RCVRY.JSP_CORREOS_486 (02/11/2026)
--  Sustituye a la versión actual (JSP_CORREOS_486_actual.sql).
--
--  Cambio: correos y domicilios se tratan por separado.
--  * Correos (adtype 3): igual que hoy. Activo = viene en la remesa
--    (JSP_TAB_MAIL_REMESA_486, que se carga con sub_mail.TXT de Banbaj).
--  * Domicilios (adtype 1): activo = es el domicilio vigente de la cuenta,
--    el que llegó en la última base maestra y subió con el SCBSDOS
--    (DELQMST.DMADDR1). Los demás domicilios de la cuenta se inactivan.
--    Antes se comparaban contra la remesa de correos y por eso se
--    inactivaban todos los domicilios del 486 en cada corrida.
--  * Se compara sin espacios a los lados y sin distinguir mayúsculas.
--  * No se tocan gestores HOMS ni HPHPI (igual que hoy).
--  * Solo cuentas activas del 486 (dmstatus nulo), grupo 1.
--  * Optimizado: la lista de correos fuera de remesa se arma sin duplicados en una
--    sola sentencia y las cuentas activas se revisan con EXISTS.
--  Índice recomendado: JSP_TAB_MAIL_REMESA_486 (CUENTA).
--
--  Confirmado (03/11): DELQMST.DMADDR1 es la columna donde
--  queda el domicilio del SCBSDOS (campo DMADDR1 del layout).
--------------------------------------------------------
set define off;

CREATE OR REPLACE PROCEDURE "RCVRY"."JSP_CORREOS_486" AS
BEGIN

    /* ---------------------------------------------------------------
       1. CORREOS (adtype 3): activo solo lo que viene en la remesa
       --------------------------------------------------------------- */
    EXECUTE IMMEDIATE 'TRUNCATE TABLE JSP_TAB_MAIL_NOREMESA_486';
    COMMIT;

    -- correos del 486 que no vienen en la remesa, sin duplicados (antes se insertaban y luego se borraban los repetidos)
    INSERT INTO JSP_TAB_MAIL_NOREMESA_486 (CUENTA, CORREO, STATUS, STCOLLID, ORIGEN, DUP)
    SELECT a.adacct, a.adaddr1, a.adstatus, a.adstcollid, a.adcollid, 0
    FROM address a
    WHERE a.ROWID IN (
        SELECT MIN(x.ROWID)
        FROM address x
        WHERE x.adacctg = '1'
          AND x.adtype = '3'
          AND EXISTS (SELECT 1 FROM delqmst c
                      WHERE c.dmacctg = '1' AND c.dmacct = x.adacct AND c.dmcompany = '486' AND c.dmstatus IS NULL)
          AND NOT EXISTS (SELECT 1 FROM JSP_TAB_MAIL_REMESA_486 b
                          WHERE b.cuenta = x.adacct AND UPPER(TRIM(b.correo)) = UPPER(TRIM(x.adaddr1)))
        GROUP BY x.adacct, x.adaddr1
    );
    COMMIT;

    -- inactiva correos que ya no llegan
    UPDATE ADDRESS SET ADSTATUS = 'I', ADSTCOLLID = 'HIAS', ADSTATDT = SYSDATE
    WHERE ADDRESS.ADACCTG = '1'
      AND ADDRESS.ADTYPE = '3'
      AND ADDRESS.ADSTATUS = 'A'
      AND UPPER(ADSTCOLLID) NOT IN ('HOMS', 'HPHPI')
      AND EXISTS (
            SELECT 1 FROM JSP_TAB_MAIL_NOREMESA_486 n
            WHERE n.CUENTA = ADDRESS.ADACCT AND n.CORREO = ADDRESS.ADADDR1
          );
    COMMIT;

    -- activa correos de la remesa que estaban inactivos
    UPDATE ADDRESS SET ADSTATUS = 'A', ADSTCOLLID = 'HAAS', ADSTATDT = SYSDATE
    WHERE ADDRESS.ADACCTG = '1'
      AND ADDRESS.ADTYPE = '3'
      AND ADDRESS.ADSTATUS = 'I'
      AND UPPER(ADSTCOLLID) NOT IN ('HOMS', 'HPHPI')
      AND EXISTS (
            SELECT 1 FROM JSP_TAB_MAIL_REMESA_486 r
            WHERE r.CUENTA = ADDRESS.ADACCT AND UPPER(TRIM(r.CORREO)) = UPPER(TRIM(ADDRESS.ADADDR1))
          );
    COMMIT;

    /* ---------------------------------------------------------------
       2. DOMICILIOS (adtype 1): activo solo el domicilio vigente de la
          cuenta (DELQMST.DMADDR1, del SCBSDOS de la última base maestra)
       --------------------------------------------------------------- */
    UPDATE ADDRESS SET ADSTATUS = 'I', ADSTCOLLID = 'HIAS', ADSTATDT = SYSDATE
    WHERE ADDRESS.ADACCTG = '1'
      AND ADDRESS.ADTYPE = '1'
      AND ADDRESS.ADSTATUS = 'A'
      AND UPPER(ADSTCOLLID) NOT IN ('HOMS', 'HPHPI')
      AND EXISTS (
            SELECT 1 FROM DELQMST c
            WHERE c.DMACCTG = '1' AND c.DMACCT = ADDRESS.ADACCT
              AND c.DMCOMPANY = '486' AND c.DMSTATUS IS NULL
              AND UPPER(TRIM(NVL(c.DMADDR1, ' '))) <> UPPER(TRIM(NVL(ADDRESS.ADADDR1, ' ')))
          );
    COMMIT;

    UPDATE ADDRESS SET ADSTATUS = 'A', ADSTCOLLID = 'HAAS', ADSTATDT = SYSDATE
    WHERE ADDRESS.ADACCTG = '1'
      AND ADDRESS.ADTYPE = '1'
      AND ADDRESS.ADSTATUS = 'I'
      AND UPPER(ADSTCOLLID) NOT IN ('HOMS', 'HPHPI')
      AND EXISTS (
            SELECT 1 FROM DELQMST c
            WHERE c.DMACCTG = '1' AND c.DMACCT = ADDRESS.ADACCT
              AND c.DMCOMPANY = '486' AND c.DMSTATUS IS NULL
              AND UPPER(TRIM(c.DMADDR1)) = UPPER(TRIM(ADDRESS.ADADDR1))
          );
    COMMIT;

END JSP_CORREOS_486;
/
