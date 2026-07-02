<#
  ---------------------------------------------------------------------------------
  The sample scripts are not supported under any Microsoft standard support
  program or service. The sample scripts are provided AS IS without warranty
  of any kind. Microsoft further disclaims all implied warranties including,
  without limitation, any implied warranties of merchantability or of fitness for
  a particular purpose. The entire risk arising out of the use or performance of
  the sample scripts and documentation remains with you. In no event shall
  Microsoft, its authors, or anyone else involved in the creation, production, or
  delivery of the scripts be liable for any damages whatsoever (including,
  without limitation, damages for loss of business profits, business interruption,
  loss of business information, or other pecuniary loss) arising out of the use
  of or inability to use the sample scripts or documentation, even if Microsoft
  has been advised of the possibility of such damages
  ---------------------------------------------------------------------------------
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
  .SYNOPSIS
  Grants the DSC pull server's IIS application-pool identity write access to the
  DSC service folder, so the ESENT repository (Devices.edb) can be created.

  .DESCRIPTION
  The classic Windows DSC pull server stores its registration and status-report
  database (Devices.edb, plus its ESENT logs) under the DSC service folder,
  by default C:\Program Files\WindowsPowerShell\DscService. That folder is owned
  by NT SERVICE\TrustedInstaller and grants SYSTEM / Administrators only *Modify*
  on the folder object itself (no Change-Permissions / WRITE_DAC), so the ACL
  cannot be edited in place — Set-Acl fails with "Attempted to perform an
  unauthorized operation" and icacls /grant fails with "Access is denied".

  This is why the grant is a dedicated, one-shot post-configuration step rather
  than a DSC resource: it needs a takeown + icacls sequence (take ownership, then
  grant), which does not belong in the recurring DSC consistency loop.

  Run this ONCE, in an elevated session, after applying CfgAppPull.ps1 on the
  pull server. It is idempotent: re-running it re-asserts the grant and exits 0.

  .PARAMETER AppPoolIdentity
  The IIS application-pool identity that runs the pull server (the PSWS app pool),
  e.g. 'CONTOSO\svcpulliisapp'. This must match the IISPULLAPP account from
  Secrets.psd1 that CfgAppPull.ps1 assigned to the pull-server AppPool.

  .PARAMETER DscServicePath
  The DSC service folder to grant on. Defaults to
  "$env:PROGRAMFILES\WindowsPowerShell\DscService" (the RegistrationKeyPath used
  by CfgAppPull.ps1).

  .PARAMETER TakeOwnership
  Take ownership of the folder (via takeown /a) before granting. Enabled by
  default because the folder is normally TrustedInstaller-owned and the grant
  cannot proceed otherwise. Pass -TakeOwnership:$false if your folder is already
  owned by Administrators / SYSTEM and you only want the grant.

  .EXAMPLE
  .\Set-SPSPullServerPermission.ps1 -AppPoolIdentity 'CONTOSO\svcpulliisapp'

  .EXAMPLE
  .\Set-SPSPullServerPermission.ps1 -AppPoolIdentity 'CONTOSO\svcpulliisapp' `
      -DscServicePath 'D:\DscService'

  .NOTES
  Project : SPSConfigKit
  Requires: PowerShell 5.1, RunAsAdministrator. Run on the pull server, once,
  after CfgAppPull.ps1 has been applied.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $AppPoolIdentity,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $DscServicePath = (Join-Path -Path $env:PROGRAMFILES -ChildPath 'WindowsPowerShell\DscService'),

  [Parameter()]
  [switch]
  $TakeOwnership = $true
)

$ErrorActionPreference = 'Stop'

function Test-GrantPresent {
  param([System.String] $Path, [System.String] $Identity)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $acl = Get-Acl -LiteralPath $Path
  }
  catch {
    return $false
  }
  $match = $acl.Access | Where-Object {
    $_.IdentityReference.Value -eq $Identity -and
    $_.AccessControlType -eq 'Allow' -and
    ($_.FileSystemRights.ToString() -match 'Modify|FullControl')
  }
  return ($null -ne $match)
}

$startDate = Get-Date
Write-Host '-----------------------------------------------'
Write-Host '| SPSConfigKit - Set-SPSPullServerPermission'
Write-Host ("| Started on      {0}" -f $startDate.ToString('o'))
Write-Host ("| DscServicePath  {0}" -f $DscServicePath)
Write-Host ("| AppPool         {0}" -f $AppPoolIdentity)
Write-Host '-----------------------------------------------'

try {
  # Create the folder if the pull server hasn't been applied yet (defensive).
  if (-not (Test-Path -LiteralPath $DscServicePath)) {
    Write-Host "DSC service folder not found; creating $DscServicePath"
    if ($PSCmdlet.ShouldProcess($DscServicePath, 'Create directory')) {
      New-Item -Path $DscServicePath -ItemType Directory -Force | Out-Null
    }
  }

  # Fast path: already granted -> nothing to do (idempotent).
  if (Test-GrantPresent -Path $DscServicePath -Identity $AppPoolIdentity) {
    Write-Host ("[=] '{0}' already has Modify on '{1}'. Nothing to do." -f $AppPoolIdentity, $DscServicePath) -ForegroundColor Green
    return
  }

  # Step 1 - take ownership so the DACL becomes editable. The folder is normally
  # owned by TrustedInstaller; /a assigns ownership to the Administrators group
  # (of which the elevated caller is a member), which then holds WRITE_DAC.
  if ($TakeOwnership) {
    Write-Host "Taking ownership of $DscServicePath (takeown /a)"
    if ($PSCmdlet.ShouldProcess($DscServicePath, 'takeown /a')) {
      $takeownOutput = & takeown.exe /f $DscServicePath /a 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw ("takeown failed on '{0}': {1}" -f $DscServicePath, ($takeownOutput -join ' '))
      }
    }
  }

  # Step 2 - grant the AppPool identity Modify, inherited by children.
  # (OI)(CI)M = Object inherit + Container inherit + Modify. icacls edits only the
  # DACL (never the owner), which is exactly what is needed here.
  $grant = '{0}:(OI)(CI)M' -f $AppPoolIdentity
  Write-Host ("Granting Modify to '{0}' (icacls /grant)" -f $AppPoolIdentity)
  if ($PSCmdlet.ShouldProcess($DscServicePath, ("icacls /grant {0}" -f $grant))) {
    $icaclsOutput = & icacls.exe $DscServicePath /grant $grant 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw ("icacls failed to grant Modify to '{0}' on '{1}': {2}" -f $AppPoolIdentity, $DscServicePath, ($icaclsOutput -join ' '))
    }
  }

  # Step 3 - verify.
  if (Test-GrantPresent -Path $DscServicePath -Identity $AppPoolIdentity) {
    Write-Host ("[+] '{0}' now has Modify on '{1}'." -f $AppPoolIdentity, $DscServicePath) -ForegroundColor Green
  }
  else {
    throw ("Grant verification failed: '{0}' still lacks Modify on '{1}'." -f $AppPoolIdentity, $DscServicePath)
  }
}
catch {
  Write-Error -Message ("Set-SPSPullServerPermission failed at {0}:{1} - {2}" -f `
      $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message) -ErrorAction Continue
  throw
}

$endDate = Get-Date
Write-Host '-----------------------------------------------'
Write-Host '| Set-SPSPullServerPermission complete'
Write-Host ("| Duration        {0}" -f ($endDate - $startDate))
Write-Host '-----------------------------------------------'
