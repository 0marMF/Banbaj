USE [BNABAJ_486];
/* Pruebas de entorno · 2 de 8 · Bajada de información de CYBER (solo lectura)
   Revisa el servidor vinculado y que cada tabla que usa Banbaj se pueda consultar: DELQMST, PHONE, PHONE_G1,
   ADDRESS, UDA1, RPT_DAT_486_1, PHNVAL, la bandera 416, las tablas de remesa y los stores. Después corre las dos
   bajadas reales (arribo y vistas), que solo escriben en tablas de SQL Server.
   Solo regresa conteos. FALLA en JSP_TAB_TEL_DEPURA_486 o en los stores es normal mientras el DBA no instale
   cyber/486/oracle/JSP_TELEFONOS_DEPURA_486.sql (con TEL_DEPURACION = ACTUAL no se usa). */
EXEC ops.sp_prueba_cyber;
