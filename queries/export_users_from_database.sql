-- ====================================================================
-- 1. CREATE DATABASE USERS (CREATE USER + DEFAULT SCHEMA)
-- ====================================================================
SELECT 
    'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = ' + 
    QUOTENAME(name COLLATE DATABASE_DEFAULT, '''') + ') ' +
    'CREATE USER ' + QUOTENAME(name COLLATE DATABASE_DEFAULT) + 
    CASE 
        WHEN authentication_type = 1 THEN ' FOR LOGIN ' + QUOTENAME(name COLLATE DATABASE_DEFAULT) -- SQL/Windows Login
        ELSE ' WITHOUT LOGIN' -- User without login
    END + 
    CASE 
        WHEN default_schema_name IS NOT NULL THEN ' WITH DEFAULT_SCHEMA = ' + QUOTENAME(default_schema_name COLLATE DATABASE_DEFAULT)
        ELSE ''
    END + ';' AS [-- User Creation Scripts]
FROM sys.database_principals
WHERE type IN ('S', 'U', 'G') -- S = SQL User, U = Windows User, G = Windows Group
  AND name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys');

-- ====================================================================
-- 2. OBJECT PERMISSIONS (USER OBJECTS ONLY - EXCLUDING SYSTEM OBJECTS)
-- ====================================================================
SELECT 
    p.state_desc COLLATE DATABASE_DEFAULT + ' ' + 
    p.permission_name COLLATE DATABASE_DEFAULT + ' ON ' + 
    QUOTENAME(SCHEMA_NAME(o.schema_id)) + '.' + QUOTENAME(o.name) + 
    ' TO ' + QUOTENAME(dp.name COLLATE DATABASE_DEFAULT) + ';' AS [-- Object Permissions]
FROM sys.database_permissions p
JOIN sys.objects o ON p.major_id = o.object_id
JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE dp.name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
  AND dp.type IN ('S', 'U', 'G', 'R') 
  AND o.is_ms_shipped = 0; -- <-- KEY FIX: Ignores internal Microsoft objects (e.g., sysclones)


-- ====================================================================
-- 3. SCHEMA PERMISSIONS (e.g., GRANT SELECT ON SCHEMA::dbo)
-- ====================================================================
SELECT 
    p.state_desc COLLATE DATABASE_DEFAULT + ' ' + 
    p.permission_name COLLATE DATABASE_DEFAULT + ' ON SCHEMA::' + 
    QUOTENAME(SCHEMA_NAME(p.major_id)) + 
    ' TO ' + QUOTENAME(dp.name COLLATE DATABASE_DEFAULT) + ';' AS [-- Schema Permissions]
FROM sys.database_permissions p
JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE p.class_desc = 'SCHEMA'
  AND dp.name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys');

-- ====================================================================
-- 4. DATABASE-LEVEL PERMISSIONS (e.g., GRANT CONNECT, VIEW DEFINITION)
-- ====================================================================
SELECT 
    p.state_desc COLLATE DATABASE_DEFAULT + ' ' + 
    p.permission_name COLLATE DATABASE_DEFAULT + 
    ' TO ' + QUOTENAME(dp.name COLLATE DATABASE_DEFAULT) + ';' AS [-- Database Permissions]
FROM sys.database_permissions p
JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE p.class_desc = 'DATABASE'
  AND dp.name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
  AND p.permission_name NOT IN ('CONNECT') -- Usually we ignore standard CONNECT for cleaner code
  OR (p.permission_name = 'CONNECT' AND dp.name NOT IN ('dbo', 'guest'));

-- ====================================================================
-- 5. DATABASE ROLE MEMBERSHIPS (e.g., db_owner, db_datareader)
-- ====================================================================
SELECT 
    'ALTER ROLE ' COLLATE DATABASE_DEFAULT + QUOTENAME(role_dp.name COLLATE DATABASE_DEFAULT) + 
    ' ADD MEMBER ' COLLATE DATABASE_DEFAULT + QUOTENAME(member_dp.name COLLATE DATABASE_DEFAULT) + ';' AS [-- Role Memberships]
FROM sys.database_role_members rm
JOIN sys.database_principals role_dp ON rm.role_principal_id = role_dp.principal_id
JOIN sys.database_principals member_dp ON rm.member_principal_id = member_dp.principal_id
WHERE member_dp.name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys');
