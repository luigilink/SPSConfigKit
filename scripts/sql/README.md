# SQL Server configuration (CfgAppSql)

`CfgAppSql.ps1` compiles the stand-alone SQL Server instance for the SharePoint farm
(engine install, service accounts, sysadmin members, TempDB layout, max-memory / MAXDOP,
firewall rule, optional TLS encryption, and the optional Ola Hallengren maintenance plan).

## SQL Server Maintenance Solution (Ola Hallengren)

When `NonNodeData.SQL.InstallMaintenanceSolution = $true`, the configuration runs the
[SQL Server Maintenance Solution](https://ola.hallengren.com) by Ola Hallengren to create
the `DatabaseBackup`, `IndexOptimize` and `DatabaseIntegrityCheck` stored procedures and
their SQL Agent jobs.

**The `MaintenanceSolution.sql` script is not distributed with this kit.** It is a
third-party work by Ola Hallengren, published under its own licence. `Initialize-SoftwarePackages`
downloads it for you (entry `OlaHallengrenMaintenanceSolution`, staged to
`SQL\MaintenanceSolution.sql` on the SoftwarePackages share). To use this feature:

1. Run `Initialize-SoftwarePackages.ps1` (it fetches `MaintenanceSolution.sql` from
   <https://ola.hallengren.com> into the SQL source folder). To stage it by hand instead,
   download the full script and drop it at
   `<NonNodeData.SourcePath>\SQL\MaintenanceSolution.sql`.
2. (Optional) Edit the `DECLARE @...` parameters at the top of the file to tune it before
   staging:
   - `@BackupDirectory` — backup root directory.
   - `@CleanupTime` — retention in hours, after which old backup files are deleted.
   - `@OutputFileDirectory` — job output/log directory.
   - `@LogToTable` — log commands to the `CommandLog` table (`'Y'` recommended).
   - `@CreateJobs` — whether to create the SQL Agent jobs (`'Y'`).
3. The file is staged to the node by the same copy that stages the SQL install media, so no
   runtime download is needed on an offline SQL server.
4. Set `NonNodeData.SQL.InstallMaintenanceSolution = $true` and (optionally) adjust the
   `MaintenanceSolution` block (`ScriptFileName`, `DatabaseName`, or an explicit
   `SourcePath` override).

The install is idempotent: a generated test script checks for the `CommandExecute`
procedure in the target database and the `SqlScript` resource is skipped once it exists.
The script runs under the SQL sysadmin RunAs account (Ola's installer requires sysadmin).

### Job schedules (left to the SQL admin)

By design, the SQL Agent jobs created by the solution are **not scheduled** — the kit
provisions the jobs, but *when* they run is an operational decision (backup window, RPO/RTO,
business load, other SQL jobs) that belongs to the SQL administrator. This is also why the
kit does **not** manage the schedules in DSC: a schedule pinned by the configuration would be
overwritten on every consistency check, fighting any manual tuning a DBA applies in
production.

After the jobs exist, add the schedules by hand (SQL Server Agent, or T-SQL). Example — a
daily full backup at 21:00 and hourly log backups:

```sql
USE [msdb];
GO
-- Daily full backup of user databases at 21:00
EXEC dbo.sp_add_jobschedule
    @job_name      = N'DatabaseBackup - USER_DATABASES - FULL',
    @name          = N'Daily 21:00',
    @freq_type     = 4,        -- daily
    @freq_interval = 1,
    @active_start_time = 210000;
GO
-- Transaction-log backup of user databases every hour
EXEC dbo.sp_add_jobschedule
    @job_name      = N'DatabaseBackup - USER_DATABASES - LOG',
    @name          = N'Hourly',
    @freq_type     = 4,
    @freq_interval = 1,
    @freq_subday_type = 8,     -- hours
    @freq_subday_interval = 1,
    @active_start_time = 000000;
GO
```

See <https://ola.hallengren.com> for the full list of jobs (`DatabaseBackup`,
`IndexOptimize`, `DatabaseIntegrityCheck`, `CommandLog` cleanup, output-file cleanup) and
recommended scheduling guidance.

### Attribution

The SQL Server Maintenance Solution is © Ola Hallengren and is provided under the terms
published at <https://ola.hallengren.com>. This kit only orchestrates a script you supply;
it does not include or modify Ola's code.
