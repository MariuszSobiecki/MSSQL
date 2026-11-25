USE master;
GO

-- 1. Create a temporary table to store data from all databases
IF OBJECT_ID('tempdb..#AllDatabasesSpace') IS NOT NULL 
    DROP TABLE #AllDatabasesSpace;

CREATE TABLE #AllDatabasesSpace (
    DatabaseName SYSNAME,
    FileGroupName NVARCHAR(128),
    FileName SYSNAME,
    PhysicalName NVARCHAR(260),
    TotalSizeMB DECIMAL(18,2),
    UsedSpaceMB DECIMAL(18,2),
    FreeSpaceMB DECIMAL(18,2),
    FreeSpacePercent DECIMAL(18,2)
);

-- 2. Use a cursor to safely iterate through online databases (better than sp_MSforeachdb)
DECLARE @DBName SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name 
FROM sys.databases 
WHERE state_desc = 'ONLINE' -- Skip offline/restoring databases
  AND database_id > 4;      -- Skip system databases (master, model, msdb, tempdb). Remove this condition to include them.

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'
    USE ' + QUOTENAME(@DBName) + N';
    INSERT INTO #AllDatabasesSpace
    SELECT 
        DB_NAME() AS DatabaseName,
        ISNULL(fg.name, ''LOG / SYSTEM'') AS FileGroupName,
        df.name AS FileName,
        df.physical_name AS PhysicalName,
        ROUND(df.size * 8.0 / 1024, 2) AS TotalSizeMB,
        ROUND(FILEPROPERTY(df.name, ''SpaceUsed'') * 8.0 / 1024, 2) AS UsedSpaceMB,
        ROUND((df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) * 8.0 / 1024, 2) AS FreeSpaceMB,
        ROUND(((df.size - FILEPROPERTY(df.name, ''SpaceUsed'')) / CAST(df.size AS DECIMAL(18,2))) * 100, 2) AS FreeSpacePercent
    FROM sys.database_files df
    LEFT JOIN sys.filegroups fg ON df.data_space_id = fg.data_space_id
    WHERE df.type_desc = ''ROWS'';'; -- Analyze data files (ROWS) only; log shrinking is handled differently

    EXEC sp_executesql @SQL;
    
    FETCH NEXT FROM db_cursor INTO @DBName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- 3. Display results sorted by the file with the most free space
SELECT * 
FROM #AllDatabasesSpace
ORDER BY FreeSpaceMB DESC;

-- Clean up the temporary table
DROP TABLE #AllDatabasesSpace;
