SELECT 
    DB_NAME() AS [DatabaseName],
    df.name AS [LogicalName],
    CAST(df.size / 128.0 AS DECIMAL(18, 2)) AS [FileSize_MB],
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 AS DECIMAL(18, 2)) AS [InternalSpaceUsed_MB],
    dovs.volume_mount_point AS [DriveLetter],
    CAST(dovs.available_bytes / 1073741824.0 AS DECIMAL(18, 2)) AS [DiskFreeSpace_GB],
    CAST((dovs.available_bytes * 100.0) / dovs.total_bytes AS DECIMAL(5, 2)) AS [DiskFreeSpace_Percent]
FROM sys.database_files df
CROSS APPLY sys.dm_os_volume_stats(DB_ID(), df.file_id) dovs;