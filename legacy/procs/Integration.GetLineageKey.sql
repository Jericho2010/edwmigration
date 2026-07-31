-- Vendored from microsoft/sql-server-samples (MIT), wwi-dw-ssdt project:
-- samples/databases/wide-world-importers/wwi-dw-ssdt/wwi-dw-ssdt/Integration/Stored Procedures/GetLineageKey.sql
-- Offline copy so the Convert agent has proc source without a live Azure SQL export.
-- Refresh from a live database with legacy/procs/export_proc_source.sh.
CREATE PROCEDURE Integration.GetLineageKey
	@TableName sysname,
	@NewCutoffTime datetime2(7)
WITH EXECUTE AS OWNER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @DataLoadStartedWhen datetime2(7) = SYSDATETIME();

	INSERT Integration.Lineage
	([Data Load Started], [Table Name], [Data Load Completed],
	 [Was Successful], [Source System Cutoff Time])
	OUTPUT
		inserted.[Lineage Key] as LineageKey
	VALUES
	(@DataLoadStartedWhen, @TableName, NULL,
	 0, @NewCutoffTime);

	RETURN 0;
END;
