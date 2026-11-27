# SPSConfigKit - Release Notes

## [1.11.0] - 2026-MM-DD

This release lets `CfgAppSql` create the SQL Agent schedules of the Ola Hallengren Maintenance Solution jobs.
The option is **opt-in and create-only**: `NonNodeData.SQL.MaintenanceSolution.Schedules` is empty by default, so
the jobs stay unscheduled and existing deployments are unaffected. The SQL brick remains a reference example.

### Added

- Create the SQL Agent schedules of the Maintenance Solution jobs in `CfgAppSql` (#119)
  - Each entry of `Schedules` declares a `Name`, `FreqType` (4 daily, 8 weekly), `FreqInterval`, `StartTime`
    (HHMMSS), optional `SubdayType` / `SubdayInterval` / `EndTime`, and the `Jobs` to attach.
  - A `SqlScript` resource creates a schedule only if no schedule of that name exists in `msdb`, then attaches
    it to the listed jobs if not already attached. It never modifies an existing schedule, and its Test ignores
    the time and days: a change made by a DBA is kept and is not reported as drift. A job missing from `msdb`
    is skipped.
  - `CfgAppSql.psd1` carries a commented "lab VMs shut down at 20:00" profile; the configuration test checks
    the list; `scripts/sql/README.md` and the wiki describe the option and its limits.

### Validation and known limits

- The Pester configuration test and the T-SQL generator were run on a workstation. The schedules were not
  applied to a live SQL Server from the kit yet: validate on the lab before tagging.
- Changing a schedule in `CfgAppSql.psd1` does not update an existing schedule (create-only): edit it in SQL
  Server Agent, or delete it in `msdb` to let DSC create it again.
- A DBA who detaches a schedule from a job gets it attached again at the next consistency check; disable the
  schedule or the job instead.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
