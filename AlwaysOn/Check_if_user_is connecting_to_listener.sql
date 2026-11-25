SELECT 
    s.session_id,
    s.login_name,
    DB_NAME(s.database_id) AS [Connected_Database],
    s.host_name AS [Client_Machine_Name],
    s.program_name,
    c.client_net_address AS [Client_IP],
    c.local_net_address AS [Server_Destination_IP],
    c.local_tcp_port AS [Server_Destination_Port],
    -- Evaluate connection origin
    CASE 
        WHEN agl.listener_id IS NOT NULL THEN 'Always On AG Listener'
        ELSE 'Direct Connection to Node/IP'
    END AS [Connection_Route],
    ISNULL(agl.dns_name, 'N/A') AS [AG_Listener_Name]
FROM sys.dm_exec_sessions s
INNER JOIN sys.dm_exec_connections c 
    ON s.session_id = c.session_id
LEFT JOIN sys.availability_group_listener_ip_addresses aglip 
    ON c.local_net_address = aglip.ip_address
LEFT JOIN sys.availability_group_listeners agl 
    ON aglip.listener_id = agl.listener_id
WHERE s.is_user_process = 1 -- and agl.dns_name is null
