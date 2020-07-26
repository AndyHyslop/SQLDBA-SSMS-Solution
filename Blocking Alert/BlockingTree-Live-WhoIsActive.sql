USE tempdb;

DECLARE @s VARCHAR(MAX), @t VARCHAR(MAX);
DECLARE @tableName varchar(255);
DECLARE @DeleteFlag tinyint; /* 0 = drop, 1 = truncate, 2 = No Action */
SET @DeleteFlag = 2;
SET @tableName = 'tempdb.dbo.WhoIsActive_ResultSet';

EXEC sp_WhoIsActive @sort_order = '[start_time] ASC', @get_outer_command=1, @find_block_leaders=1 --,@get_full_inner_text=1
					--,@get_transaction_info=1
					--,@get_task_info=2, @get_avg_time=1, @get_additional_info=1
					--,@get_plans=1 /* 1 = current query, 2 = entire batch */
					,@return_schema = 1, @schema = @s OUTPUT

SET @s = REPLACE(@s, '<table_name>', @tableName)

IF @DeleteFlag = 0
	SET @t = 'IF OBJECT_ID('''+@tableName+''') IS NOT NULL DROP TABLE '+@tableName;
IF @DeleteFlag = 1
	SET @t = 'IF EXISTS(SELECT * FROM '+@tableName+') TRUNCATE TABLE '+@tableName;
IF @DeleteFlag = 2
	SET @t = '-- ignore';

EXEC(@t);
PRINT @t;
SET @s = 'IF OBJECT_ID('''+@tableName+''') IS NULL BEGIN '+@s+'; CREATE CLUSTERED INDEX [CI_WhoIsActive_ResultSet] ON '+@tableName+' ( [collection_time] ASC, session_id ); END'
EXEC(@s);


EXEC sp_WhoIsActive @sort_order = '[start_time] ASC', @get_outer_command=1, @find_block_leaders=1 --,@get_full_inner_text=1
					--,@get_transaction_info=1
					--,@get_task_info=2, @get_avg_time=1, @get_additional_info=1
					--,@get_plans=1 /* 1 = current query, 2 = entire batch */
					,@destination_table = @tableName;

-- Delete records when No Blocking was Found
delete from tempdb.dbo.WhoIsActive_ResultSet
where collection_time in (select r.collection_time from tempdb.dbo.WhoIsActive_ResultSet as r 
						group by r.collection_time having count(r.blocking_session_id) = 0);

--select * from tempdb.dbo.WhoIsActive_ResultSet
--where [blocking_session_id] is not null
--or [blocked_session_count] > 0


;WITH T_BLOCKERS AS
(
	-- Find block Leaders
	SELECT	r.[dd hh:mm:ss.mss], r.[session_id], r.[sql_text],
			[batch_text] = REPLACE(REPLACE(REPLACE(REPLACE(CAST(COALESCE(r.[sql_command],r.[sql_text]) AS VARCHAR(MAX)),char(13),''),CHAR(10),''),'<?query --',''),'--?>',''),
			r.[sql_command], r.[login_name], r.[wait_info], r.[tempdb_allocations], r.[tempdb_current], 
			r.[blocking_session_id], r.[blocked_session_count], r.[reads], r.[writes], r.[physical_reads], r.[CPU], r.[used_memory], r.[status], r.[open_tran_count], 
			r.[percent_complete], r.[host_name], r.[database_name], r.[program_name], r.[start_time], r.[login_time], r.[request_id], r.[collection_time]
			,[LEVEL] = CAST (REPLICATE ('0', 4-LEN (CAST (r.session_id AS VARCHAR))) + CAST (r.session_id AS VARCHAR) AS VARCHAR (1000))
	FROM	tempdb.dbo.WhoIsActive_ResultSet AS r
	WHERE	(ISNULL(r.blocking_session_id,0) = 0 OR ISNULL(r.blocking_session_id,0) = r.session_id)
		AND EXISTS (SELECT * FROM tempdb.dbo.WhoIsActive_ResultSet AS R2 WHERE R2.collection_time = r.collection_time AND ISNULL(R2.blocking_session_id,0) = r.session_id AND ISNULL(R2.blocking_session_id,0) <> R2.session_id)
	--	
	UNION ALL
	--
	SELECT	r.[dd hh:mm:ss.mss], r.[session_id], r.[sql_text],
			[batch_text] = REPLACE(REPLACE(REPLACE(REPLACE(CAST(COALESCE(r.[sql_command],r.[sql_text]) AS VARCHAR(MAX)),char(13),''),CHAR(10),''),'<?query --',''),'--?>',''),
			r.[sql_command], r.[login_name], r.[wait_info], r.[tempdb_allocations], r.[tempdb_current], 
			r.[blocking_session_id], r.[blocked_session_count], r.[reads], r.[writes], r.[physical_reads], r.[CPU], r.[used_memory], r.[status], r.[open_tran_count], 
			r.[percent_complete], r.[host_name], r.[database_name], r.[program_name], r.[start_time], r.[login_time], r.[request_id], r.[collection_time]
			,CAST (B.LEVEL + RIGHT (CAST ((1000 + r.session_id) AS VARCHAR (100)), 4) AS VARCHAR (1000)) AS LEVEL
	FROM	tempdb.dbo.WhoIsActive_ResultSet AS r
	INNER JOIN 
			T_BLOCKERS AS B
		ON	r.collection_time = B.collection_time
		AND	r.blocking_session_id = B.session_id
	WHERE	r.blocking_session_id <> r.session_id
)
--select * from T_BLOCKERS
	
SELECT	r.[collection_time],
		[BLOCKING_TREE] = N'    ' + REPLICATE (N'|         ', LEN (LEVEL)/4 - 1) 
						+	CASE	WHEN (LEN(LEVEL)/4 - 1) = 0
									THEN 'HEAD -  '
									ELSE '|------  ' 
							END
						+	CAST (r.session_id AS NVARCHAR (10)) + N' ' + (CASE WHEN LEFT(r.[batch_text],1) = '(' THEN SUBSTRING(r.[batch_text],CHARINDEX('exec',r.[batch_text]),LEN(r.[batch_text]))  ELSE r.[batch_text] END),
		r.[dd hh:mm:ss.mss], r.[wait_info], r.[blocked_session_count], r.[blocking_session_id], --r.[sql_text], r.[sql_command],
		r.[login_name], r.[host_name], r.[database_name], r.[program_name], r.[tempdb_allocations], r.[tempdb_current], 
		r.[reads], r.[writes], r.[physical_reads], r.[CPU], r.[used_memory], r.[status], r.[open_tran_count], 
		r.[percent_complete], r.[start_time], r.[login_time], r.[request_id]
FROM	T_BLOCKERS AS r
ORDER BY collection_time, LEVEL ASC;

select @@servername as srvName, r.login_name, r.program_name, r.database_name, count(r.session_id) as session_counts
from tempdb.dbo.WhoIsActive_ResultSet AS r
group by r.login_name, r.program_name, r.database_name
having count(r.session_id) > (select count(distinct [collection_time]) from tempdb.dbo.WhoIsActive_ResultSet as r)
order by session_counts desc
go


