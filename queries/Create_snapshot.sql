-- Create snapshot
-- Switch to the master database
USE master;
GO

-- Create the database snapshot
DECLARE @DatabaseName NVARCHAR(128) = 'database_name';           
DECLARE @SnapshotPath NVARCHAR(260) = 'H:\snapshot\'; -- <--- folder for .ss (must exist)


DECLARE @SnapshotName NVARCHAR(128) = @DatabaseName + '_Snapshot_20261028';
DECLARE @SQL NVARCHAR(MAX);

-- Start building the query
SET @SQL = 'CREATE DATABASE ' + QUOTENAME(@SnapshotName) + ' ON ' + CHAR(13);

-- Dynamically generate files from all filegroups
SELECT @SQL = @SQL + '    (NAME = ' + QUOTENAME(name) + ', FILENAME = ''' + @SnapshotPath + name + '_snap.ss''),' + CHAR(13)
FROM sys.master_files
WHERE database_id = DB_ID(@DatabaseName) 
  AND type = 0; -- Data files only

-- Remove the trailing comma and add the AS SNAPSHOT OF clause
SET @SQL = SUBSTRING(@SQL, 1, LEN(@SQL) - 2) + CHAR(13) + 'AS SNAPSHOT OF ' + QUOTENAME(@DatabaseName) + ';';

-- TRICK: Instead of PRINT, output the text as an XML field.
-- This allows SSMS to display the full text without any length limits.
SELECT CAST('<?query --' + CHAR(13) + @SQL + CHAR(13) + '--?>' AS XML) AS [ClickToGetCode];



-- Restore from snapshot
-- Switch to the master database
USE master;
GO

-- Set the source database to SINGLE_USER mode to disconnect all active connections immediately
ALTER DATABASE YourDatabase 
SET SINGLE_USER 
WITH ROLLBACK IMMEDIATE;
GO

-- Restore the source database back to the exact state captured in the snapshot
RESTORE DATABASE YourDatabase
FROM DATABASE_SNAPSHOT = 'YourDatabase_Snapshot_20261028';
GO

-- Revert the database back to MULTI_USER mode so users can connect again
ALTER DATABASE YourDatabase 
SET MULTI_USER;
GO

-- Drop snapshot
-- Switch to the master database
USE master;
GO

-- Drop the snapshot when it is no longer needed (this also deletes the .ss file from the disk)
DROP DATABASE YourDatabase_Snapshot_20261028;
GO
