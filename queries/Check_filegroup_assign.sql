SELECT 
    OBJECT_SCHEMA_NAME(p.object_id) AS SchemaName,
    OBJECT_NAME(p.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    f.name AS FilegroupName,
    p.partition_number AS PartitionNumber,
    p.rows AS [RowCount]
FROM 
    sys.allocation_units au
INNER JOIN 
    sys.partitions p ON au.container_id = 
        CASE 
            WHEN au.type IN (1, 3) THEN p.hobt_id 
            WHEN au.type = 2 THEN p.partition_id 
        END
INNER JOIN 
    sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
INNER JOIN 
    sys.filegroups f ON au.data_space_id = f.data_space_id
ORDER BY 
    SchemaName, 
    TableName, 
    i.index_id,
    p.partition_number;
