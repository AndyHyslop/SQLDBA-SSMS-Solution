create function utc2local (@utc_datetime datetime2)
returns datetime2
as
begin
	declare @local_time datetime2;
	select @local_time = Dateadd(MILLISECOND, Datediff(MILLISECOND, Getutcdate(), Getdate()), @utc_datetime);

	return (@local_time);
end
go

create function local2utc (@local_datetime datetime2)
returns datetime2
as
begin
	declare @utc_time datetime2;
	select @utc_time = DATEADD(second, DATEDIFF(second, GETDATE(), GETUTCDATE()), @local_datetime);

	return (@utc_time);
end
go

alter function time2duration (@time bigint, @unit varchar(20) = 'second')
returns varchar(30)
as
begin
	declare @duration varchar(30);

	if @unit in ('datetime','datetime2','smalldatetime')
	begin
		select @duration =
				Concat
					(
						RIGHT('00'+CAST(ISNULL((datediff(second,@time,GETDATE()) / 3600 / 24), 0) AS VARCHAR(2)),2)
						,' '
						,RIGHT('00'+CAST(ISNULL(datediff(second,@time,GETDATE()) / 3600  % 24, 0) AS VARCHAR(2)),2)
						,':'
						,RIGHT('00'+CAST(ISNULL(datediff(second,@time,GETDATE()) / 60 % 60, 0) AS VARCHAR(2)),2)
						,':'
						,RIGHT('00'+CAST(ISNULL(datediff(second,@time,GETDATE()) % 3600 % 60, 0) AS VARCHAR(2)),2)
					) --as [dd hh:mm:ss]
	end

	if @unit in ('second','ss','s')
	begin
		select @duration =
				Concat
					(
						RIGHT('00'+CAST(ISNULL((@time / 3600 / 24), 0) AS VARCHAR(2)),2)
						,' '
						,RIGHT('00'+CAST(ISNULL(@time / 3600  % 24, 0) AS VARCHAR(2)),2)
						,':'
						,RIGHT('00'+CAST(ISNULL(@time / 60 % 60, 0) AS VARCHAR(2)),2)
						,':'
						,RIGHT('00'+CAST(ISNULL(@time % 3600 % 60, 0) AS VARCHAR(2)),2)
					) --as [dd hh:mm:ss]
	end

	return (@duration);
end
go

--select master.dbo.time2duration(121,'s')