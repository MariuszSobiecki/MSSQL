CREATE OR ALTER PROCEDURE dbo.SafeDeleteOldData
    @FullTableName NVARCHAR(512),   -- Format: 'DatabaseName.SchemaName.TableName' or '[Database].[Schema].[Table]'
    @DateColumn NVARCHAR(128),
    @CutoffDate DATETIME,
    @BatchSize INT = 5000
	--example
	--EXEC dbo.SafeDeleteOldData
    --@FullTableName = N'DB.dbo.table',
    --@DateColumn = N'TIME_STAMP_',
    --@CutoffDate = '2026-01-01 00:00:00',
    --@BatchSize = 5000;
GO
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Object name validation including the database name
    IF PARSENAME(@FullTableName, 1) IS NULL OR PARSENAME(@FullTableName, 2) IS NULL
    BEGIN
        RAISERROR('Invalid table format. Required format: Database.Schema.Table or Schema.Table', 16, 1);
        RETURN;
    END

    -- Automatic parsing of component parts and wrapping in square brackets [] for security
    DECLARE @DatabaseName NVARCHAR(128) = ISNULL(PARSENAME(@FullTableName, 3), DB_NAME());
    DECLARE @SchemaName NVARCHAR(128) = PARSENAME(@FullTableName, 2);
    DECLARE @TableName NVARCHAR(128) = PARSENAME(@FullTableName, 1);

    -- Building a fully qualified and safe object name
    DECLARE @ValidatedTableName NVARCHAR(512) = QUOTENAME(@DatabaseName) + N'.' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);
    DECLARE @EscapedDateColumn NVARCHAR(128) = QUOTENAME(@DateColumn);

    -- Check if the table exists in the target database
    DECLARE @ObjectCheckSql NVARCHAR(MAX) = N'SELECT @IdOUT = OBJECT_ID(@ObjName, N''U'')';
    DECLARE @ObjectId INT;
    DECLARE @CheckExecSql NVARCHAR(MAX) = QUOTENAME(@DatabaseName) + N'..sp_executesql';

    EXEC @CheckExecSql @ObjectCheckSql, N'@ObjName NVARCHAR(512), @IdOUT INT OUTPUT', @ObjName = @ValidatedTableName, @IdOUT = @ObjectId OUTPUT;

    IF @ObjectId IS NULL
    BEGIN
        RAISERROR('Table %s does not exist in database %s.', 16, 1, @ValidatedTableName, @DatabaseName);
        RETURN;
    END

    -- 2. Preparing dynamic SQL query to be executed in the target database context
    DECLARE @Sql NVARCHAR(MAX);
    SET @Sql = N'
        DELETE TOP (@InnerBatchSize) FROM ' + @ValidatedTableName + N' WITH (ROWLOCK)
        WHERE ' + @EscapedDateColumn + N' < @InnerCutoffDate;
        
        SET @InnerRowsDeleted = @@ROWCOUNT;
    ';

    DECLARE @RowsDeleted INT = 0;
    DECLARE @TotalRowsDeleted BIGINT = 0;
    DECLARE @Iteration INT = 0;

    PRINT 'Starting data deletion from table: ' + @ValidatedTableName;
    PRINT 'Database context: ' + @DatabaseName;
    PRINT 'Cutoff date: ' + CONVERT(NVARCHAR(30), @CutoffDate, 120);
    PRINT 'Batch size: ' + CAST(@BatchSize AS NVARCHAR(10));
    PRINT '------------------------------------------------';

    -- 3. Main deletion loop
    WHILE 1 = 1
    BEGIN
        BEGIN TRY
            -- Each batch is a separate, short transaction
            BEGIN TRANSACTION;

            -- Execute the query using sp_executesql in the target database
            EXEC @CheckExecSql 
                @Sql, 
                N'@InnerBatchSize INT, @InnerCutoffDate DATETIME, @InnerRowsDeleted INT OUTPUT', 
                @InnerBatchSize = @BatchSize, 
                @InnerCutoffDate = @CutoffDate, 
                @InnerRowsDeleted = @RowsDeleted OUTPUT;

            COMMIT TRANSACTION;

            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted;
            SET @Iteration = @Iteration + 1;

            -- Log progress every 10 iterations to the console (Messages)
            IF @Iteration % 10 = 0
            BEGIN
                RAISERROR('Total rows deleted: %I64d...', 0, 1, @TotalRowsDeleted) WITH NOWAIT;
            END

            -- Loop exit condition - if fewer rows than the batch size were deleted, no more data remains
            IF @RowsDeleted < @BatchSize
            BEGIN
                BREAK;
            END

            -- Optional: uncomment the line below if disk I/O load becomes too high
            -- WAITFOR DELAY '00:00:00.050';

        END TRY
        BEGIN CATCH
            -- In case of an error, roll back the current small batch and abort the process
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
            RAISERROR('Error occurred while deleting data: %s', 16, 1, @ErrMsg);
            BREAK;
        END CATCH
    END

    PRINT '------------------------------------------------';
    PRINT 'Completed successfully. Total rows deleted: ' + CAST(@TotalRowsDeleted AS NVARCHAR(20));
END;
GO
