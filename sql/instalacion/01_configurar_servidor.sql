/* =====================================================================
   Banbaj · Instalación 1 de 3 · Configuración del servidor (una vez, sysadmin)
   ---------------------------------------------------------------------
   - Automatización OLE: escribir los archivos planos (ops.sp_exportar_salidas)
   - xp_cmdshell: armar el ZIP de retiros con 7-Zip
   - Database Mail: perfil asig.486.cdmx para las plantillas del 486
   Revisa el servidor SMTP antes de correrlo (hoy los .prg usan 192.168.50.7:25).
   No está en sql/*.sql: se corre a mano en master, una sola vez.
   ===================================================================== */
USE master;
GO
EXEC sp_configure 'show advanced options', 1;            RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 1;        RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1;                      RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1;                RECONFIGURE;
GO

USE msdb;
GO
DECLARE @perfil SYSNAME = N'asig.486.cdmx',
        @cuenta SYSNAME = N'asig.486.cdmx',
        @correo NVARCHAR(256) = N'asig.486.cdmx@sertec.com.mx',
        @nombre NVARCHAR(128) = N'Asignaciones',
        @smtp   SYSNAME = N'192.168.50.7',
        @puerto INT = 25;

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = @cuenta)
    EXEC msdb.dbo.sysmail_add_account_sp @account_name = @cuenta, @email_address = @correo, @display_name = @nombre,
         @replyto_address = @correo, @mailserver_name = @smtp, @port = @puerto;
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = @perfil)
BEGIN
    EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = @perfil, @description = N'Correos del cliente 486 (Banbaj)';
    EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = @perfil, @account_name = @cuenta, @sequence_number = 1;
END;
/* Que cualquier usuario de msdb pueda usar el perfil (el job y quien corra los procesos a mano) */
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysmail_principalprofile pp JOIN msdb.dbo.sysmail_profile p ON p.profile_id = pp.profile_id WHERE p.name = @perfil)
    EXEC msdb.dbo.sysmail_add_principalprofile_sp @profile_name = @perfil, @principal_name = N'public', @is_default = 0;

/* Prueba: debe llegar al buzón */
EXEC msdb.dbo.sp_send_dbmail @profile_name = @perfil, @recipients = @correo,
     @subject = N'Prueba Database Mail Banbaj', @body = N'Si lees esto, el perfil asig.486.cdmx funciona.';
SELECT TOP (5) mailitem_id, sent_status, sent_date FROM msdb.dbo.sysmail_allitems ORDER BY mailitem_id DESC;
GO
