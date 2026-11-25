USE [YourDatabase];
GO

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
    AND i.type IN (0, 1) -- Heap (0) and Clustered Rowstore (1) only
    AND NOT EXISTS (
        -- Exclude tables that already have any Columnstore index (5 = Clustered, 6 = Nonclustered)
        SELECT 1 
        FROM sys.indexes ci 
        WHERE ci.object_id = t.object_id 
          AND ci.type IN (5, 6)
    )
GROUP BY 
    s.name, t.name
HAVING 
    SUM(p.rows) >= 1048576 -- Show only tables with at least 1M rows (technical minimum for 1 full rowgroup)
ORDER BY 
    [TotalRows] DESC;
