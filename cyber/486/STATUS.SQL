/*SET heading off*/
/*SET linesize 32767*/
SET linesize 800
SET colsep "|"
SET pagesize 0
SET newpage none
SET feedback off
SET termout off
SET recsep off
SET sqlprompt ""
SET TRIMSPOOL ON
SET echo off

spool C:\STATUSBAJ.txt
select  DMCOMPANY as CLIENTE,
        DMADL1 as FOLIO,
        DMACCT as CUENTA, 
        DMACRC2 as status,
        DMACAC2 AS ACCION,
        DMACDT2 AS FECHA,
        DMACSC2 AS PESO,
        dmssnum as cuenta2
from RCVRY.delqmst 
where DMACCTG='1'
AND DMCOMPANY='486'
AND dmstatus is null;
spool off

EXIT
quit