/* =====================================================================
   Banbaj · Instalación 2 de 3 · Jobs de SQL Server Agent (una vez)
   ---------------------------------------------------------------------
   "Banbaj 486 diario": cada 30 minutos, de lunes a viernes, de 07:00 a 22:00,
   ejecuta ops.sp_diario_486 en la base indicada. El procedimiento no repite
   lo que ya corrió: corre la actualización cuando llegan sus archivos y
   después la asignación si llegó.
   Cambia @base si la base no se llama Banbaj.
   ===================================================================== */
USE msdb;
GO
DECLARE @base SYSNAME = N'BNABAJ_486', @job SYSNAME = N'Banbaj 486 diario', @id UNIQUEIDENTIFIER;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @job)
    EXEC msdb.dbo.sp_delete_job @job_name = @job;

EXEC msdb.dbo.sp_add_job @job_name = @job, @enabled = 1,
     @description = N'Actualización y asignación del cliente 486 (ops.sp_diario_486)', @job_id = @id OUTPUT;
EXEC msdb.dbo.sp_add_jobstep @job_id = @id, @step_name = N'sp_diario_486', @subsystem = N'TSQL',
     @database_name = @base, @command = N'EXEC ops.sp_diario_486;', @retry_attempts = 0;
EXEC msdb.dbo.sp_add_jobschedule @job_id = @id, @name = N'Cada 30 min, L-V 07:00-22:00', @enabled = 1,
     @freq_type = 8, @freq_interval = 62, @freq_recurrence_factor = 1,     -- semanal; 62 = lunes a viernes
     @freq_subday_type = 4, @freq_subday_interval = 30,                     -- cada 30 minutos
     @active_start_time = 70000, @active_end_time = 220000;
EXEC msdb.dbo.sp_add_jobserver @job_id = @id, @server_name = N'(local)';
GO

/* 19/11: "Banbaj 486 ladas": el día 1 de cada mes a las 06:00 copia de CYBER la tabla de ladas válidas
   (PHNVAL) a cfg.PHNVAL con ops.sp_phnval_actualizar. Si falla, el paso queda en error, llega
   HALLAZGO_486 y los teléfonos se siguen validando con la copia anterior. */
DECLARE @base SYSNAME = N'BNABAJ_486', @job SYSNAME = N'Banbaj 486 ladas', @id UNIQUEIDENTIFIER;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @job)
    EXEC msdb.dbo.sp_delete_job @job_name = @job;

EXEC msdb.dbo.sp_add_job @job_name = @job, @enabled = 1,
     @description = N'Copia mensual de las ladas válidas de CYBER (PHNVAL) a cfg.PHNVAL (ops.sp_phnval_actualizar)', @job_id = @id OUTPUT;
EXEC msdb.dbo.sp_add_jobstep @job_id = @id, @step_name = N'sp_phnval_actualizar', @subsystem = N'TSQL',
     @database_name = @base, @command = N'EXEC ops.sp_phnval_actualizar;', @retry_attempts = 2, @retry_interval = 60;   -- dos reintentos, una hora entre cada uno
EXEC msdb.dbo.sp_add_jobschedule @job_id = @id, @name = N'Día 1 de cada mes, 06:00', @enabled = 1,
     @freq_type = 16, @freq_interval = 1, @freq_recurrence_factor = 1,     -- mensual, día 1
     @active_start_time = 60000;
EXEC msdb.dbo.sp_add_jobserver @job_id = @id, @server_name = N'(local)';
GO
