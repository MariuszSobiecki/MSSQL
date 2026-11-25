USE [YourDatabase];
GO

CREATE OR ALTER PROCEDURE dbo.sp_Monitor_AlwaysOn_Health
AS
BEGIN
    SET NOCOUNT ON;

    ----------------------------------------------------------------------
    -- INTERNAL CONFIGURATION PARAMETERS (Change your settings here)
    ----------------------------------------------------------------------
    DECLARE @UserDatabaseName NVARCHAR(128) = 'YourDatabase'; -- Set your user database name here
    DECLARE @ProfileName      NVARCHAR(128) = 'DBA_Profile';
    DECLARE @Recipients       NVARCHAR(MAX) = 'email@email.com';
    DECLARE @CooldownMinutes  INT           = 120; --seconds between resend mail
    DECLARE @SubjectPrefix    NVARCHAR(100) = '[listener_name]';

    ----------------------------------------------------------------------
    -- Variable declarations for internal SQL handling
    ----------------------------------------------------------------------
    DECLARE @DynamicSQL NVARCHAR(MAX);
    DECLARE @ParamDefinition NVARCHAR(500);
    DECLARE @SubjectPrefixClean NVARCHAR(110) = '';
    
    -- Format and clean the prefix
    IF LTRIM(RTRIM(@SubjectPrefix)) <> ''
    BEGIN
        SET @SubjectPrefixClean = CASE WHEN RIGHT(@SubjectPrefix, 1) = ' ' THEN @SubjectPrefix ELSE RTRIM(@SubjectPrefix) + ' ' END;
    END

    ----------------------------------------------------------------------
    -- AUTO-PROVISIONING: Check and create the history table if missing
    ----------------------------------------------------------------------
    SET @DynamicSQL = N'
        IF OBJECT_ID(''' + REPLACE(@UserDatabaseName, '''', '''''') + N'.dbo.AG_Alert_History'', ''U'') IS NULL
        BEGIN
            EXEC(N''USE ' + QUOTENAME(@UserDatabaseName) + N'; 
            CREATE TABLE dbo.AG_Alert_History (
                LogID INT IDENTITY(1,1) PRIMARY KEY,
                EventTimestamp DATETIME DEFAULT GETDATE(),
                EventType VARCHAR(20),             -- ALARM or RESOLUTION
                IssueCategory VARCHAR(50),         -- Replica_Offline or Database_Sync_Issue
                SubjectLine NVARCHAR(255),
                EmailBody NVARCHAR(MAX),
                CooldownMinutesApplied INT
            );'');
        END';
    
    EXEC sp_executesql @DynamicSQL;

    ----------------------------------------------------------------------
    -- 1. Build current state tracking tables
    ----------------------------------------------------------------------
    DECLARE @UnhealthyAGs TABLE (
        AGName SYSNAME,
        ReplicaName NVARCHAR(257),
        RoleDesc NVARCHAR(60),
        DatabaseName SYSNAME NULL,
        SyncState NVARCHAR(60) NULL,
        HealthDesc NVARCHAR(60) NULL,
        IssueDescription NVARCHAR(255),
        Category VARCHAR(50)
    );

    -- Check Case A: Replica offline
    INSERT INTO @UnhealthyAGs (AGName, ReplicaName, RoleDesc, IssueDescription, Category)
    SELECT 
        ag.name, rc.replica_server_name, ars.role_desc,
        'CRITICAL: Replica is DISCONNECTED or Offline', 'Replica_Offline'
    FROM sys.availability_groups ag
    JOIN sys.availability_replicas rc ON ag.group_id = rc.group_id
    JOIN sys.dm_hadr_availability_replica_states ars ON rc.replica_id = ars.replica_id
    WHERE ars.connected_state_desc = 'DISCONNECTED';

    -- Check Case B: Databases lagging
    INSERT INTO @UnhealthyAGs (AGName, ReplicaName, RoleDesc, DatabaseName, SyncState, HealthDesc, IssueDescription, Category)
    SELECT 
        ag.name, rc.replica_server_name, ars.role_desc, db_name(drs.database_id), 
        drs.synchronization_state_desc, drs.synchronization_health_desc,
        'WARNING: Database Sync Lag or Suspended', 'Database_Sync_Issue'
    FROM sys.availability_groups ag
    JOIN sys.availability_replicas rc ON ag.group_id = rc.group_id
    JOIN sys.dm_hadr_availability_replica_states ars ON rc.replica_id = ars.replica_id
    JOIN sys.dm_hadr_database_replica_states drs ON rc.replica_id = drs.replica_id AND ag.group_id = drs.group_id
    WHERE ars.connected_state_desc = 'CONNECTED'
      AND (drs.synchronization_state_desc NOT IN ('SYNCHRONIZED', 'SYNCHRONIZING') 
           OR drs.synchronization_health_desc <> 'HEALTHY'
           OR drs.redo_queue_size > 51200
           OR drs.log_send_queue_size > 51200);

    ----------------------------------------------------------------------
    -- 2. CASE 1: System is UNHEALTHY (Evaluate Cooldown & Log History)
    ----------------------------------------------------------------------
    DECLARE @ActiveCategory VARCHAR(50);
    IF EXISTS(SELECT 1 FROM @UnhealthyAGs WHERE Category = 'Replica_Offline')
        SET @ActiveCategory = 'Replica_Offline';
    ELSE IF EXISTS(SELECT 1 FROM @UnhealthyAGs WHERE Category = 'Database_Sync_Issue')
        SET @ActiveCategory = 'Database_Sync_Issue';

    IF @ActiveCategory IS NOT NULL
    BEGIN
        DECLARE @IsThrottled INT = 0;

        -- Query user table dynamic check
        SET @DynamicSQL = N'
            SELECT TOP 1 @IsThrottledOut = CASE WHEN EventTimestamp > DATEADD(MINUTE, -@Cooldown, GETDATE()) THEN 1 ELSE 0 END
            FROM ' + QUOTENAME(@UserDatabaseName) + N'.dbo.AG_Alert_History
            WHERE IssueCategory = @Category AND EventType = ''ALARM''
            ORDER BY EventTimestamp DESC;';
            
        SET @ParamDefinition = N'@Category VARCHAR(50), @Cooldown INT, @IsThrottledOut INT OUTPUT';
        
        EXEC sp_executesql @DynamicSQL, @ParamDefinition, 
                           @Category = @ActiveCategory, @Cooldown = @CooldownMinutes, @IsThrottledOut = @IsThrottled OUTPUT;

        IF ISNULL(@IsThrottled, 0) = 0
        BEGIN
            DECLARE @EmailBody NVARCHAR(MAX) = 'ALERT: SQL Server Always On Availability Group anomalies detected!' + CHAR(13) + CHAR(10);
            SET @EmailBody = @EmailBody + 'Note: This alert will be throttled for the next ' + CAST(@CooldownMinutes AS VARCHAR(5)) + ' minutes.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
            
            SELECT @EmailBody = @EmailBody + 
                'Type: ' + IssueDescription + CHAR(13) + CHAR(10) +
                'AG Group: ' + AGName + ' | Server: ' + ReplicaName + ' (' + RoleDesc + ')' + 
                CASE WHEN DatabaseName IS NOT NULL THEN ' | DB: ' + DatabaseName + ' | State: ' + SyncState ELSE '' END + CHAR(13) + CHAR(10) +
                '--------------------------------------------------' + CHAR(13) + CHAR(10)
            FROM @UnhealthyAGs WHERE Category = @ActiveCategory;

            DECLARE @ProblemSubject NVARCHAR(255) = @SubjectPrefixClean + 'SQL Server AG Alert: Problem Detected';

            EXEC msdb.dbo.sp_send_dbmail
                @profile_name = @ProfileName,
                @recipients = @Recipients,
                @subject = @ProblemSubject,
                @body = @EmailBody,
                @importance = 'High';

            -- Log to history table
            SET @DynamicSQL = N'
                INSERT INTO ' + QUOTENAME(@UserDatabaseName) + N'.dbo.AG_Alert_History 
                (EventType, IssueCategory, SubjectLine, EmailBody, CooldownMinutesApplied)
                VALUES (''ALARM'', @Category, @Subject, @Body, @Cooldown);';
                
            EXEC sp_executesql @DynamicSQL, N'@Category VARCHAR(50), @Subject NVARCHAR(255), @Body NVARCHAR(MAX), @Cooldown INT',
                               @Category = @ActiveCategory, @Subject = @ProblemSubject, @Body = @EmailBody, @Cooldown = @CooldownMinutes;
        END
    END

    ----------------------------------------------------------------------
    -- 3. CASE 2: System is HEALTHY (Check for Transition & Log Resolution)
    ----------------------------------------------------------------------
    IF NOT EXISTS(SELECT 1 FROM @UnhealthyAGs)
    BEGIN
        DECLARE @WasInAlarm INT = 0;

        -- Query history check
        SET @DynamicSQL = N'
            SELECT TOP 1 @WasInAlarmOut = CASE WHEN EventType = ''ALARM'' THEN 1 ELSE 0 END
            FROM ' + QUOTENAME(@UserDatabaseName) + N'.dbo.AG_Alert_History
            ORDER BY EventTimestamp DESC;';
            
        SET @ParamDefinition = N'@WasInAlarmOut INT OUTPUT';
        
        EXEC sp_executesql @DynamicSQL, @ParamDefinition, @WasInAlarmOut = @WasInAlarm OUTPUT;

        IF ISNULL(@WasInAlarm, 0) = 1
        BEGIN
            DECLARE @RecoveryBody NVARCHAR(MAX) = 'RECOVERY: SQL Server Always On Availability Group health has been fully restored.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
                                                  'All replicas are CONNECTED and databases are fully SYNCHRONIZED.' + CHAR(13) + CHAR(10) +
                                                  'Resolution Timestamp: ' + CONVERT(VARCHAR(20), GETDATE(), 120);

            DECLARE @RecoverySubject NVARCHAR(255) = @SubjectPrefixClean + 'SQL Server AG RESOLVED: Environment Is Healthy';

            EXEC msdb.dbo.sp_send_dbmail
                @profile_name = @ProfileName,
                @recipients = @Recipients,
                @subject = @RecoverySubject,
                @body = @RecoveryBody,
                @importance = 'Normal';

            -- Log resolution to history table
            SET @DynamicSQL = N'
                INSERT INTO ' + QUOTENAME(@UserDatabaseName) + N'.dbo.AG_Alert_History 
                (EventType, IssueCategory, SubjectLine, EmailBody, CooldownMinutesApplied)
                VALUES (''RESOLUTION'', ''All_Clear'', @Subject, @Body, 0);';
                
            EXEC sp_executesql @DynamicSQL, N'@Subject NVARCHAR(255), @Body NVARCHAR(MAX)',
                               @Subject = @RecoverySubject, @Body = @RecoveryBody;
        END
    END
END;
GO
