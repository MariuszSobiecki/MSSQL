CREATE PROCEDURE dbo.BackupDatabaseToFolder
    @DatabaseName NVARCHAR(128),
    @BackupFolder NVARCHAR(260),
    @ExpireDays INT = NULL -- Nowy parametr: ilość dni, po których backup jest usuwany. NULL oznacza brak usuwania.
	--example
	--EXEC dbo.BackupDatabaseToFolder 
    --@DatabaseName = 'YourDatabaseName', 
    --@BackupFolder = 'C:\SQLBackups';
AS
BEGIN
    SET NOCOUNT ON;

    -- Ensure the backup folder path ends with a backslash
    IF RIGHT(@BackupFolder, 1) <> '\'
    BEGIN
        SET @BackupFolder = @BackupFolder + '\';
    END

    -- Generate a unique filename with a timestamp (YYYYMMDD_HHMMSS)
    DECLARE @Timestamp NVARCHAR(15);
    SET @Timestamp = CONVERT(NVARCHAR(8), GETDATE(), 112) + '_' + 
                     REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), ':', '');

    -- Hardcoded to reflect Copy-Only in the file path
    DECLARE @BackupPath NVARCHAR(500);
    SET @BackupPath = @BackupFolder + @DatabaseName + '_CopyOnly_' + @Timestamp + '.bak';

    -- Build the backup command with hardcoded COPY_ONLY
    DECLARE @SqlBackupCommand NVARCHAR(MAX);
    SET @SqlBackupCommand = N'
        BACKUP DATABASE ' + QUOTENAME(@DatabaseName) + N'
        TO DISK = @Path
        WITH FORMAT, 
             MEDIANAME = ''LocalSQLBackup'', 
             NAME = @BackupName,
             COMPRESSION, 
             COPY_ONLY, 
             STATS = 10;';

    -- Hardcoded to reflect Copy-Only in the backup set metadata
    DECLARE @BackupName NVARCHAR(255);
    SET @BackupName = 'Copy-Only Full Backup of ' + @DatabaseName;

    -- Execute the backup command safely with parameters
    BEGIN TRY
        EXEC sp_executesql 
            @SqlBackupCommand, 
            N'@Path NVARCHAR(500), @BackupName NVARCHAR(255)', 
            @Path = @BackupPath,
            @BackupName = @BackupName;

        PRINT 'Backup successfully created at: ' + @BackupPath;

        -- --- KROK USUWANIA STARYCH BACKUPOW ---
        IF @ExpireDays IS NOT NULL AND @ExpireDays > 0
        BEGIN
            DECLARE @DeleteCutoffDate DATETIME;
            -- Obliczenie daty granicznej
            SET @DeleteCutoffDate = DATEADD(day, -@ExpireDays, GETDATE());

            -- xp_delete_file wymaga: typu pliku (0=backup, 1=log), ścieżki, rozszerzenia, daty oraz flagi podfolderów (0=nie)
            EXEC master.dbo.xp_delete_file 
                0, 
                @BackupFolder, 
                N'bak', 
                @DeleteCutoffDate, 
                0;

            PRINT 'Zakończono proces usuwania backupów starszych niż ' + CAST(@ExpireDays AS NVARCHAR(10)) + ' dni.';
        END
    END TRY
    BEGIN CATCH
        PRINT 'Error occurred during backup or cleanup!';
        PRINT ERROR_MESSAGE();
    END CATCH
END;
GO
