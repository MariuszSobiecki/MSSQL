-- Install Adam Machanic script
--https://github.com/amachanic/sp_whoisactive/blob/master/sp_WhoIsActive.sql
USE [DBA] --type your DBA database
GO
/****** Object:  StoredProcedure [dbo].[Capture_WhoIsActive_Daily]    Script Date: 30.06.2026 10:16:53 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[Capture_WhoIsActive_Daily]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @schema NVARCHAR(MAX);
    DECLARE @target_table NVARCHAR(256);
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @drop_date_string VARCHAR(10);
    DECLARE @old_table_name NVARCHAR(256);

    BEGIN TRY
        -- 1. GENERATE TODAY'S TABLE NAME (Format: dbo.WhoIsActive_YYYYMMDD)
        SET @target_table = 'dbo.WhoIsActive_' + CONVERT(VARCHAR(10), GETDATE(), 112);

        -- 2. CREATE TODAY'S TABLE IF IT DOES NOT EXIST
        IF OBJECT_ID(@target_table, 'U') IS NULL
        BEGIN
            -- Get the correct schema definition from the utility
            EXEC sp_WhoIsActive
                @get_plans = 1,
                @get_transaction_info = 1,
                @get_outer_command = 1,
                @format_output = 0, 
                @return_schema = 1,
                @schema = @schema OUTPUT;

            -- Swap the placeholder for our dynamic name safely
            SET @schema = REPLACE(@schema, '<table_name>', @target_table);
            EXEC sp_executesql @schema;

            -- Add a clustered index for performance
            SET @sql = 'CREATE CLUSTERED INDEX ' + QUOTENAME('CX_' + REPLACE(@target_table, '.', '_')) + 
                       ' ON ' + QUOTENAME(PARSENAME(@target_table, 2)) + '.' + QUOTENAME(PARSENAME(@target_table, 1)) + ' (collection_time);';
            EXEC sp_executesql @sql;
        END

        -- 3. LOG LIVE SNAPSHOT INTO TODAY'S TABLE
        EXEC sp_WhoIsActive
            @get_plans = 1,
            @get_transaction_info = 1,
            @get_outer_command = 1,
            @format_output = 0,
            @destination_table = @target_table;

        -- 4. AUTOMATICALLY DROP TABLES OLDER THAN 7 DAYS
        SET @drop_date_string = CONVERT(VARCHAR(10), GETDATE() - 8, 112);
        SET @old_table_name = 'dbo.WhoIsActive_' + @drop_date_string;

        -- If that specific old table exists, drop it safely
        IF OBJECT_ID(@old_table_name, 'U') IS NOT NULL
        BEGIN
            SET @sql = 'DROP TABLE ' + QUOTENAME(PARSENAME(@old_table_name, 2)) + '.' + QUOTENAME(PARSENAME(@old_table_name, 1));
            EXEC sp_executesql @sql;
        END

    END TRY
    BEGIN CATCH
        -- Raise the error back to the calling process or SQL Agent Job log
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
