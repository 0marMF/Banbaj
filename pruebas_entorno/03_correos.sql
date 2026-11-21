USE [BNABAJ_486];
/* Pruebas de entorno · 3 de 8 · Envío de correos
   Revisa el perfil de Database Mail, que todas las plantillas se armen y manda un correo real
   (solo a la dirección del paso 1). Revisa tu bandeja. */
EXEC ops.sp_prueba_correo;

/* Si no llega: los últimos envíos y lo que dice Database Mail */
SELECT TOP (10) ID, PLANTILLA, PARA, ASUNTO, ESTATUS, ERROR, FECHA FROM mail.ENVIO ORDER BY ID DESC;
SELECT TOP (10) mailitem_id, recipients, subject, sent_status, sent_date FROM msdb.dbo.sysmail_allitems ORDER BY mailitem_id DESC;
SELECT TOP (10) log_date, description FROM msdb.dbo.sysmail_event_log ORDER BY log_id DESC;
