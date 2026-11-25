--check users
USE [YourDatabaseName];
SELECT name, type_desc FROM sys.database_principals 
WHERE sid NOT IN (SELECT sid FROM sys.server_principals) 
  AND type IN ('S', 'U', 'G') 
  AND name NOT IN ('guest', 'INFORMATION_SCHEMA', 'sys', 'dbo');
  
--delete users
-- Step 1: Switch context to your target database
USE [YourDatabaseName]; 
GO

-- Step 2: Declare variables for the dynamic SQL loops
DECLARE @UserName NVARCHAR(256);
DECLARE @SchemaName NVARCHAR(256);
DECLARE @RoleName NVARCHAR(256); -- Added dedicated variable for role tracking
DECLARE @Sql NVARCHAR(MAX);

-- Step 3: Create a cursor to find all orphaned users
DECLARE OrphanedUserCursor CURSOR FOR
SELECT dp.name
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.type IN ('S', 'U', 'G')             
  AND sp.sid IS NULL                         
  AND dp.authentication_type_desc <> 'NONE'  
  AND dp.name NOT IN ('guest', 'INFORMATION_SCHEMA', 'sys', 'dbo'); 

OPEN OrphanedUserCursor;
FETCH NEXT FROM OrphanedUserCursor INTO @UserName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Step 4: Transfer ownership of any schemas owned by this user to dbo
    DECLARE SchemaCursor CURSOR FOR
    SELECT name 
    FROM sys.schemas 
    WHERE principal_id = USER_ID(@UserName);

    OPEN SchemaCursor;
    FETCH NEXT FROM SchemaCursor INTO @SchemaName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'ALTER AUTHORIZATION ON SCHEMA::' + QUOTENAME(@SchemaName) + N' TO [dbo];';
        PRINT 'Transferring ownership of schema [' + @SchemaName + '] from ' + @UserName + ' to dbo.';
        EXEC sp_executesql @Sql;
        
        FETCH NEXT FROM SchemaCursor INTO @SchemaName;
    END;
    CLOSE SchemaCursor;
    DEALLOCATE SchemaCursor;

    -- Step 5: Transfer ownership of any database roles owned by this user to dbo
    DECLARE RoleCursor CURSOR FOR
    SELECT name 
    FROM sys.database_principals 
    WHERE type = 'R' AND principal_id = USER_ID(@UserName);

    OPEN RoleCursor;
    FETCH NEXT FROM RoleCursor INTO @RoleName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- TYPO FIXED HERE: Removed dashes from QUOTENAME
        SET @Sql = N'ALTER AUTHORIZATION ON ROLE::' + QUOTENAME(@RoleName) + N' TO [dbo];';
        PRINT 'Transferring ownership of role [' + @RoleName + '] from ' + @UserName + ' to dbo.';
        EXEC sp_executesql @Sql;
        
        FETCH NEXT FROM RoleCursor INTO @RoleName;
    END;
    CLOSE RoleCursor;
    DEALLOCATE RoleCursor;

    -- Step 6: Drop the orphaned user
    SET @Sql = N'DROP USER ' + QUOTENAME(@UserName) + N';';
    PRINT 'Dropping orphaned user: ' + @UserName;
    BEGIN TRY
        EXEC sp_executesql @Sql;
    END TRY
    BEGIN CATCH
        PRINT 'ERROR dropping user ' + @UserName + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM OrphanedUserCursor INTO @UserName;
END;

-- Step 7: Clean up the main cursor resource
CLOSE OrphanedUserCursor;
DEALLOCATE OrphanedUserCursor;
GO