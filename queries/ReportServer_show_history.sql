USE ReportServer;
GO

SELECT 
    c.Name AS ReportName,
    c.Path AS ReportPath,
    e.UserName AS UserName,
    e.TimeStart AS StartTime,
    e.TimeEnd AS EndTime,
    CAST(DATEDIFF(MILLISECOND, e.TimeStart, e.TimeEnd) / 1000.0 AS DECIMAL(10, 2)) AS DurationSeconds,
    -- DATEDIFF(MILLISECOND, e.TimeStart, e.TimeEnd) AS DurationMilliseconds, -- Alternative in milliseconds
    e.Status
FROM dbo.ExecutionLogStorage e
INNER JOIN dbo.Catalog c 
    ON e.ReportID = c.ItemID
WHERE e.TimeStart > '2026-08-01 00:00:00'
ORDER BY e.TimeStart DESC;
