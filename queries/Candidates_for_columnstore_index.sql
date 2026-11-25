SELECT 
    s.name AS [Schema],
    t.name AS [TableName],
    COUNT(DISTINCT p.partition_number) AS [PartitionCount],
    SUM(p.rows) AS [TotalRows],
    CAST((SUM(a.total_pages) * 8) / 1024.0 AS DECIMAL(18, 2)) AS [TotalSizeMB],
    CAST((SUM(a.used_pages) * 8) / 1024.0 AS DECIMAL(18, 2)) AS [UsedSizeMB],
    CASE 
        WHEN SUM(p.rows) >= 50000000 THEN '🔥 IDEAL (50M+ rows - High compression & Batch Mode gains)'
        WHEN SUM(p.rows) >= 10000000 THEN '⭐ RECOMMENDED (10M+ rows - Strong analytical & space gains)'
        WHEN SUM(p.rows) >= 1048576  THEN '✔️ WORTH CONSIDERING (1M+ rows - Minimum 1 full rowgroup; check workload)'
        ELSE '❌ Skip (Keep as Rowstore - Below 1M rowgroup threshold)'
    END AS [Columnstore_Eligibility]
FROM 
    sys.tables t
INNER JOIN 
    sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN 
    sys.indexes i ON t.object_id = i.object_id
INNER JOIN 
    sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN 
    sys.allocation_units a ON p.partition_id = a.container_id
WHERE 
    t.is_ms_shipped = 0
    AND i.type IN (0, 1) -- 0: Heap, 1: Clustered Rowstore (exclude tables that are already Columnstore)
GROUP BY 
    s.name, t.name
ORDER BY 
    [TotalRows] DESC;
