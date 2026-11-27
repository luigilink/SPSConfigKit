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

### Job schedules (left to the SQL admin by default)

By design, the SQL Agent jobs created by the solution are **not scheduled** — the kit
provisions the jobs, but *when* they run is an operational decision (backup window, RPO/RTO,
business load, other SQL jobs) that belongs to the SQL administrator. This is also why the
kit does **not** manage the schedules in DSC by default: a schedule pinned by the configuration
would be overwritten on every consistency check, fighting any manual tuning a DBA applies in
production.

#### Optional: create the schedules (opt-in, create-only)

For labs and rebuildable VMs, `NonNodeData.SQL.MaintenanceSolution.Schedules` can list the
schedules to create. It is **empty by default**: nothing is created and the jobs stay
unscheduled. When it is not empty, the `MIDDLEWARE_SqlMaintenanceSchedules` `SqlScript`
resource runs after the installation of the solution and, for each entry:

1. creates the schedule **only if no schedule of that name exists** in `msdb`;
2. attaches it to the listed jobs if it is not already attached (a job missing from `msdb`
   is skipped).

It **never modifies an existing schedule**. The Test script only checks that the schedule and
its links exist, never the time or the days, so a schedule retouched by a DBA is not drift.

| Key | Required | Notes |
|---|---|---|
| `Name` | yes | Unique (case-insensitive), 128 characters max. The existence check is on this name. |
| `FreqType` | yes | `4` daily (`FreqInterval` = every N days, 1-365) or `8` weekly (`FreqInterval` = day bitmask). |
| `FreqInterval` | yes | Weekly bitmask: Sun 1, Mon 2, Tue 4, Wed 8, Thu 16, Fri 32, Sat 64. Mon-Fri = 62, Friday = 32, Wednesday = 8. |
| `StartTime` | yes | `HHMMSS` (e.g. `173000` = 17:30). |
| `SubdayType` | no | `1` once (default), `4` minutes, `8` hours. |
| `SubdayInterval` | with `SubdayType` 4 / 8 | 1-59 minutes or 1-23 hours. |
| `EndTime` | no | `HHMMSS`, default `235959`; must be later than `StartTime` with a sub-day frequency. |
| `Jobs` | yes | Names of the jobs created by the solution (see below). |

Jobs created by the solution: `DatabaseBackup - SYSTEM_DATABASES - FULL`,
`DatabaseBackup - USER_DATABASES - FULL` / `DIFF` / `LOG`,
`DatabaseIntegrityCheck - SYSTEM_DATABASES` / `USER_DATABASES`,
`IndexOptimize - USER_DATABASES`, `CommandLog Cleanup`, `Output File Cleanup`,
`sp_delete_backuphistory`, `sp_purge_jobhistory`. Other jobs (`syspolicy_purge_history`, SharePoint
jobs) are not managed.

Example profile "lab VMs shut down at 20:00" (hours are the VM's local time, working days).
It is also in `CfgAppSql.psd1`, commented:

```powershell
Schedules = @(
  @{ Name = 'SPSKit - Weekdays 17:30'; FreqType = 8; FreqInterval = 62; StartTime = 173000; Jobs = @('DatabaseBackup - SYSTEM_DATABASES - FULL') }
  @{ Name = 'SPSKit - Weekdays 18:00'; FreqType = 8; FreqInterval = 62; StartTime = 180000; Jobs = @('DatabaseBackup - USER_DATABASES - FULL') }
  @{ Name = 'SPSKit - Friday 12:00'; FreqType = 8; FreqInterval = 32; StartTime = 120000; Jobs = @('DatabaseIntegrityCheck - SYSTEM_DATABASES') }
  @{ Name = 'SPSKit - Friday 12:15'; FreqType = 8; FreqInterval = 32; StartTime = 121500; Jobs = @('DatabaseIntegrityCheck - USER_DATABASES') }
  @{ Name = 'SPSKit - Wednesday 12:30'; FreqType = 8; FreqInterval = 8; StartTime = 123000; Jobs = @('IndexOptimize - USER_DATABASES') }
  @{ Name = 'SPSKit - Friday 19:00'; FreqType = 8; FreqInterval = 32; StartTime = 190000; Jobs = @('CommandLog Cleanup', 'Output File Cleanup', 'sp_delete_backuphistory', 'sp_purge_jobhistory') }
)
```

`DatabaseBackup - USER_DATABASES - DIFF` is left unscheduled. `DatabaseBackup - USER_DATABASES - LOG`
is only useful for databases in the `FULL` recovery model; with `SIMPLE` databases (typical lab)
it has nothing to back up. For `FULL` databases, add for instance
`@{ Name = 'SPSKit - Weekdays log 30min'; FreqType = 8; FreqInterval = 62; SubdayType = 4; SubdayInterval = 30; StartTime = 083000; EndTime = 193000; Jobs = @('DatabaseBackup - USER_DATABASES - LOG') }`.

Behaviour to know:

- **Create-only**: changing a schedule in the `.psd1` does not update an existing one. Edit it in
  SQL Server Agent, or delete it in `msdb` and let DSC create it again at the next consistency check.
- **Re-attach**: a schedule detached from a job (or deleted) by a DBA is created / attached again at
  the next consistency check. To stop a schedule, disable it (or the job) instead of detaching it.
- **Shared schedule**: a schedule listed for several jobs (e.g. the Friday 19:00 cleanup) is one
  schedule; changing it in SQL Server Agent changes all its jobs.
- **Invalid entry**: the compilation fails with the list of the problems, including a job name
  that is not one of the jobs created by the solution (so `syspolicy_purge_history`, SharePoint jobs
  and typos are refused). The configuration test (`Invoke-ConfigDataTest.ps1`) checks the same rules.
  A valid job that is absent from `msdb` (e.g. the solution installed with `@CreateJobs = 'N'`) is skipped at run time.

#### Manual schedules

Without the option above, add the schedules by hand (SQL Server Agent, or T-SQL). Example — a
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
