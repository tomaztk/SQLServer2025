/* =====================================================================
   05_log_backup_job.sql
   CES needs FULL recovery, so the log only truncates after LOG backups.
   This SQL Agent job takes a log backup every 15 minutes for the demo DB.
   Demo-grade: it overwrites one file (WITH INIT), which breaks the restore
   chain. Use your real backup solution (or Azure Automated Backup) in prod.
   Requires SQL Server Agent (not available on Express).
   ===================================================================== */
:setvar DatabaseName "CesDemo"

USE msdb;
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'CesDemo - log backup')
    EXEC msdb.dbo.sp_delete_job @job_name = N'CesDemo - log backup';
GO
EXEC msdb.dbo.sp_add_job      @job_name = N'CesDemo - log backup', @enabled = 1;
EXEC msdb.dbo.sp_add_jobstep  @job_name = N'CesDemo - log backup', @step_name = N'BACKUP LOG',
     @subsystem = N'TSQL', @database_name = N'master',
     @command = N'BACKUP LOG [$(DatabaseName)] TO DISK = N''$(DatabaseName)_log.trn'' WITH INIT;';
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'Every 15 minutes', @freq_type = 4, @freq_interval = 1,
     @freq_subday_type = 4, @freq_subday_interval = 15;
EXEC msdb.dbo.sp_attach_schedule @job_name = N'CesDemo - log backup', @schedule_name = N'Every 15 minutes';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'CesDemo - log backup';
GO
