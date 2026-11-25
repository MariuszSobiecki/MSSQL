--check
USE [SSISDB]
GO

SELECT 
    MIN([created_time]) AS [Oldest_Log_In_Database],
    MAX([created_time]) AS [Newest_Log_In_Database],
    DATEDIFF(day, MIN([created_time]), GETDATE()) AS [Days_Of_Data_Retained],
    COUNT(*) AS [Total_Operations]
FROM [internal].[operations];

--delete
USE [SSISDB]
GO

SET NOCOUNT ON;
DECLARE @deleted_total INT = 1;
DECLARE @batch_count INT = 0;

-- Loop will process data in batches as long as records older than 7 days remain
WHILE @deleted_total > 0
BEGIN
    DELETE TOP (5000) FROM [internal].[operation_messages]
    WHERE [operation_id] IN (
        SELECT [operation_id] 
        FROM [internal].[operations] 
        WHERE [created_time] < DATEADD(day, -7, GETDATE())
    );
    
    SET @deleted_total = @@ROWCOUNT;
    SET @batch_count = @batch_count + 1;

    -- Print progress in the Messages tab every 10 batches to show the process is still running
    IF @batch_count % 10 = 0
    BEGIN
        PRINT 'Deleted ' + CAST(@batch_count * 5000 AS VARCHAR) + ' message rows...';
    END

    -- Short pause to avoid overloading the transaction log in Always On
    WAITFOR DELAY '00:00:02';
END
GO

-- Finally, delete orphaned operations from the main table
DECLARE @op_deleted INT = 1;
WHILE @op_deleted > 0
BEGIN
    DELETE TOP (2000) FROM [internal].[operations]
    WHERE [created_time] < DATEADD(day, -2, GETDATE());
    
    SET @op_deleted = @@ROWCOUNT;
    WAITFOR DELAY '00:00:01';
END
GO
