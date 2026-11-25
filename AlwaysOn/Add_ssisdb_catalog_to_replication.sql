--change replica to read and change again to no read after those steps (if needed)

USE [master];
GO

-- This targets the correct wrapper procedure that Microsoft uses for SSISDB
EXEC sp_procoption @ProcName = N'dbo.sp_ssis_startup', 
                   @OptionName = 'startup', 
                   @OptionValue = 'on';
GO


USE [SSISDB];
GO

-- Manually register your named instance into the SSIS tracking configuration
IF NOT EXISTS (SELECT 1 FROM [catalog].[alwayson_replicas] WHERE [server_name] = N'PLSQL1QANOD02\INSTANCE_1')
BEGIN
    INSERT INTO [catalog].[alwayson_replicas] ([server_name])
    VALUES (N'PLSQL1QANOD02\INSTANCE_1');
END
GO