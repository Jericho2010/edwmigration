-- Vendored from microsoft/sql-server-samples (MIT), wwi-dw-ssdt project:
-- samples/databases/wide-world-importers/wwi-dw-ssdt/wwi-dw-ssdt/Integration/Stored Procedures/GetLastETLCutoffTime.sql
-- Offline copy so the Convert agent has proc source without a live Azure SQL export.
-- Refresh from a live database with legacy/procs/export_proc_source.sh.
CREATE PROCEDURE Integration.GetLastETLCutoffTime
	@TableName sysname
WITH EXECUTE AS OWNER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	SELECT [Cutoff Time] AS CutoffTime
	FROM Integration.[ETL Cutoff]
	WHERE [Table Name] = @TableName;

	IF @@ROWCOUNT = 0
	BEGIN
		PRINT N'Invalid ETL table name';
		THROW 51000, N'Invalid ETL table name', 1;
		RETURN -1;
	END;

	RETURN 0;
END;
