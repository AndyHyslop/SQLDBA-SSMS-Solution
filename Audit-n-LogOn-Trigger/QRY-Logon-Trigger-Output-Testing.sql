USE [master]
GO

--CREATE TRIGGER [audit_login_events] ON ALL SERVER 
--FOR LOGON 
--AS 
SET XACT_ABORT OFF
BEGIN
	-- Declare Variables
	declare @app_name sysname = 'dbatools-test';
	declare @login_name sysname = SUSER_NAME();
	declare @host_name sysname = host_name();
	declare @data xml;
	declare @ispooled bit;

	declare @engine_service_account sysname;
	declare @agent_service_account sysname;

	select @engine_service_account = service_account from sys.dm_server_services where servicename like ('SQL Server (%)');
	select @agent_service_account = service_account from sys.dm_server_services where servicename like ('SQL Server Agent (%)');

	select [@app_name] = @app_name, [@login_name] = @login_name, [@host_name] = @host_name, [@engine_service_account] = @engine_service_account, [@agent_service_account] = @agent_service_account;

	-- Determine whether the login should be excluded from tracking in DBA.dbo._hist_sysprocesses
    IF LOWER(@login_name) IN (@engine_service_account, @agent_service_account, 'sa','angeltrade\angeltrade_dba_team','.\sql','nt authority\system', LOWER(DEFAULT_DOMAIN()+'\'+CONVERT(nvarchar(128), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'))+'$')) 
        RETURN ;
    IF @login_name LIKE N'%_sa'
		RETURN;
    IF ISNULL(DATABASEPROPERTYEX('DBA', 'Status'), 'N/A') <> 'ONLINE'
		RETURN;

	select 'Crossed Login Exclusion part.' as RunningQuery;

	-- Reject connections above threshold limit defined in master.dbo.connection_limit_config
	IF EXISTS (SELECT OBJECT_ID('master.dbo.connection_limit_config'))
	BEGIN
		DECLARE @connection_limit smallint,
				@connection_count smallint;
		DECLARE @config_login_name sysname;
		DECLARE @config_program_name sysname;
		DECLARE @config_host_name sysname;
		DECLARE @message varchar(5000);

		-- Find specific limit with all 3 parameters match
		SELECT @connection_limit = limit, @config_login_name = [login_name], @config_program_name = [program_name], @config_host_name = [host_name]
		FROM master.dbo.connection_limit_config WITH (NOLOCK)
		WHERE [login_name] = @login_name
		and [program_name] = isnull(@app_name,'*')
		and [host_name] = @host_name;

		-- If no specific limit is defined, use default
		IF (@connection_limit IS NULL)
		BEGIN
			SELECT @connection_limit = limit, @config_login_name = [login_name], @config_program_name = [program_name], @config_host_name = [host_name]
			FROM (
					SELECT	TOP 1 
							(case when [login_name] = @login_name then 200 else 0 end) +
							(case when [login_name] = '*' then 5 else 0 end) +
							(case when [program_name] = isnull(@app_name,'*') then 100 else 0 end) +
							(case when [program_name] = '*' then 5 else 0 end) +
							(case when [host_name] = @host_name then 100 else 0 end) +
							(case when [host_name] = '*' then 5 else 0 end) as [score], *
					FROM master.dbo.connection_limit_config WITH (NOLOCK)
					WHERE ([login_name] = @login_name  or [login_name] = '*')
					and ([program_name] = isnull(@app_name,'*') or [program_name] = '*')
					and ([host_name] = @host_name or [host_name] = '*')
					order by [score] desc
			) t_limit;					
		END;

		if @config_login_name = '*' and @config_program_name = '*' and @config_host_name = '*'
			select @connection_count = count(1)
			from sys.dm_exec_sessions es
			where  es.login_name = @login_name
		else
			select @connection_count = count(1)
			from sys.dm_exec_sessions es
			where (es.login_name = @login_name or @login_name = '*')
			and (es.program_name = @config_program_name or @config_program_name = '*')
			and (es.host_name = @config_host_name or @config_host_name = '*');

		select [@connection_count] = @connection_count, [@connection_limit] = @connection_limit, [@config_login_name] = @config_login_name, [@config_program_name] = @config_program_name, [@config_host_name] = @config_host_name;

	  IF (@connection_count > @connection_limit)
	  BEGIN
		select 'Connection Limit Breached.' as RunningQuery;
		SET @message='Connection attempt by { login || program } = {{ ' + @login_name+' || '+@app_name+' }}' + ' from host ' + @host_name +' has been rejected due to breached concurrent connection limit (' + convert(varchar, @connection_count) + '>=' + convert(varchar, @connection_limit) + ').';
		RAISERROR (@message, 10, 1);
		ROLLBACK;
		RETURN;
	  END;
	END;

	-- Determine whether the connection is pooled
	SET @data = EVENTDATA()
    SET @ispooled = @data.value('(/EVENT_INSTANCE/IsPooled)[1]', 'bit');

	-- Try to log the information in DBA, but allow the login even if unsuccessful.
	BEGIN TRY
		INSERT INTO [DBA].[dbo].[connection_history]
		(session_id, host_process_id, login_time, host_name, client_net_address, program_name, client_version, login_name, client_interface_name, auth_scheme, is_pooled)
		SELECT	@@SPID,  
				des.host_process_id,     
				des.login_time,     
				des.host_name,     
				dec.client_net_address,     
				@app_name,  
				des.client_version,
				@login_name,
				des.client_interface_name,  
				dec.auth_scheme,
				@ispooled 
		FROM	sys.dm_exec_sessions des
		JOIN	sys.dm_exec_connections dec ON des.session_id=dec.session_id AND des.session_id=@@SPID and dec.net_transport <> 'Session';
		REVERT;
	END TRY
	BEGIN CATCH
		--IF @@TRANCOUNT > 0 ROLLBACK;
		REVERT;
	END CATCH
END
GO
