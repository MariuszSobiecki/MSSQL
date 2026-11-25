USE master;
GO

-- 1. Define variables (Set paths and database name)
DECLARE @DatabaseName NVARCHAR(128) = N'YourDatabaseName';
DECLARE @FullBackupPath NVARCHAR(260) = N'C:\Path\To\File\Backup_Full.bak';

-- If you HAVE a DIFF file -> enter the path. If you DO NOT -> leave as NULL
DECLARE @DiffBackupPath NVARCHAR(260) = N'C:\Path\To\File\Backup_Diff.bak'; 
-- DECLARE @DiffBackupPath NVARCHAR(260) = NULL; -- Variant without DIFF


-- 2. Disconnect users and force SINGLE_USER mode
DECLARE @AlterSql NVARCHAR(MAX);
SET @AlterSql = N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
BEGIN TRY
    EXEC sp_executesql @AlterSql;
END TRY
BEGIN CATCH
    PRINT 'Database does not exist or cannot be switched to SINGLE_USER mode. Continuing operation...';
END CATCH;


-- 3. RESTORE logic (Dynamic selection depending on DIFF file presence)
BEGIN TRY
    IF @DiffBackupPath IS NOT NULL AND @DiffBackupPath <> ''
    BEGIN
        PRINT 'Differential file detected. Starting FULL + DIFF restore procedure...';

        -- STEP A: Restore database from FULL backup (database remains in RESTORING state)
        RESTORE DATABASE @DatabaseName
        FROM DISK = @FullBackupPath
        WITH NORECOVERY, REPLACE;
        PRINT 'Step 1/2: FULL backup restored with NORECOVERY.';

        -- STEP B: Apply DIFF backup and bring database online (RECOVERY)
        RESTORE DATABASE @DatabaseName
        FROM DISK = @DiffBackupPath
        WITH RECOVERY;
        PRINT 'Step 2/2: DIFF backup applied with RECOVERY. Database is ready.';
    END
    ELSE
    BEGIN
        PRINT 'No differential file provided. Restoring FULL backup only...';

        -- Restore FULL backup only and bring database online immediately
        RESTORE DATABASE @DatabaseName
        FROM DISK = @FullBackupPath
        WITH RECOVERY, REPLACE;
        PRINT 'FULL backup restored with RECOVERY. Database is ready.';
    END
END TRY
BEGIN CATCH
    PRINT 'A critical error occurred during database restore: ' + ERROR_MESSAGE();
END CATCH;


-- 4. Restore multi-user access (MULTI_USER)
SET @AlterSql = N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET MULTI_USER;';
BEGIN TRY
    EXEC sp_executesql @AlterSql;
    PRINT 'MULTI_USER access has been restored.';
END TRY
BEGIN CATCH
    PRINT 'Failed to switch the database to MULTI_USER mode (manual intervention may be required).';
END CATCH;
GO
