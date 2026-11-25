USE SSISDB;
GO

SET NOCOUNT ON;

-- ==========================================
-- NEW FEATURE: FOLDER FILTERING
-- ==========================================
DECLARE @filter_by_folders BIT = 0; -- 1 = filter by the list below, 0 = iterate through all folders in the SSIS database

DECLARE @selected_folders TABLE (folder_name NVARCHAR(128));
INSERT INTO @selected_folders (folder_name) VALUES 
(N'CITIDIRECT'),
(N'CSSETL'),
(N'MISReports'); -- <--- ENTER YOUR FOLDERS HERE (if @filter_by_folders = 1)
-- ==========================================

DECLARE @current_folder NVARCHAR(128);
DECLARE @env_name NVARCHAR(128);
DECLARE @var_name NVARCHAR(128);
DECLARE @var_type NVARCHAR(128);
DECLARE @var_sensitive BIT;
DECLARE @var_value SQL_VARIANT;
DECLARE @var_desc NVARCHAR(1024);
DECLARE @sql_val NVARCHAR(MAX);

-- Create a global temporary table so the data remains available after the script finishes
IF OBJECT_ID('tempdb..##SSIS_Script') IS NOT NULL DROP TABLE ##SSIS_Script;
CREATE TABLE ##SSIS_Script (Id INT IDENTITY(1,1), [Clean T-SQL to copy] NVARCHAR(MAX));

-- 1. Outer cursor - iterate through FOLDERS
DECLARE folder_cursor CURSOR FOR
SELECT f.name
FROM [catalog].[folders] f
WHERE @filter_by_folders = 0 
   OR f.name IN (SELECT folder_name FROM @selected_folders);

OPEN folder_cursor;
FETCH NEXT FROM folder_cursor INTO @current_folder;

WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('================================================================================');
    INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('-- FOLDER: ' + UPPER(@current_folder));
    INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('================================================================================');
    INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('');

    -- 2. Cursor for environments inside the current folder
    DECLARE env_cursor CURSOR FOR 
    SELECT e.name
    FROM [catalog].[environments] e
    JOIN [catalog].[folders] f ON e.folder_id = f.folder_id
    WHERE f.name = @current_folder;

    OPEN env_cursor;
    FETCH NEXT FROM env_cursor INTO @env_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('  ------------------------------------------------------------------------------');
        INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('  -- ENVIRONMENT: ' + @env_name + ' (in folder ' + @current_folder + ')');
        INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('  ------------------------------------------------------------------------------');
        INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('  EXEC [SSISDB].[catalog].[create_environment] @folder_name = N''' + @current_folder + ''', @environment_name = N''' + @env_name + ''';');
        INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('  ');

        -- 3. Cursor for variables inside the current environment
        DECLARE var_cursor CURSOR FOR
        SELECT v.name, v.type, v.sensitive, v.value, v.description
        FROM [catalog].[environment_variables] v
        JOIN [catalog].[environments] e ON v.environment_id = e.environment_id
        JOIN [catalog].[folders] f ON e.folder_id = f.folder_id
        WHERE f.name = @current_folder AND e.name = @env_name;

        OPEN var_cursor;
        FETCH NEXT FROM var_cursor INTO @var_name, @var_type, @var_sensitive, @var_value, @var_desc;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @var_sensitive = 1
            BEGIN
                SET @sql_val = N'__ENTER_SENSITIVE_PASSWORD_OR_PARAMETER__';
            END
            ELSE
            BEGIN
                SET @sql_val = REPLACE(ISNULL(CONVERT(NVARCHAR(MAX), @var_value), ''), '''', '''''');
            END
            
            INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES (
                '  DECLARE @val_' + @var_name + ' SQL_VARIANT = N''' + @sql_val + '''; ' +
                'EXEC [SSISDB].[catalog].[create_environment_variable] ' +
                '@folder_name = N''' + @current_folder + ''', @environment_name = N''' + @env_name + ''', ' +
                '@variable_name = N''' + @var_name + ''', @data_type = N''' + @var_type + ''', ' +
                '@sensitive = ' + CAST(@var_sensitive AS VARCHAR(1)) + ', @value = @val_' + @var_name + 
                ', @description = N''' + REPLACE(ISNULL(@var_desc, ''), '''', '''''') + ''';'
            );

            FETCH NEXT FROM var_cursor INTO @var_name, @var_type, @var_sensitive, @var_value, @var_desc;
        END;

        CLOSE var_cursor;
        DEALLOCATE var_cursor;

        INSERT INTO ##SSIS_Script ([Clean T-SQL to copy]) VALUES ('  ');
        FETCH NEXT FROM env_cursor INTO @env_name;
    END;

    CLOSE env_cursor;
    DEALLOCATE env_cursor;

    FETCH NEXT FROM folder_cursor INTO @current_folder;
END;

CLOSE folder_cursor;
DEALLOCATE folder_cursor;

-- Display results in the standard grid
SELECT [Clean T-SQL to copy]
FROM ##SSIS_Script
ORDER BY Id;
