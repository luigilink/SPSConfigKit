#Requires -Version 5.1
#Requires -RunAsAdministrator

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

<#
.SYNOPSIS
  Provisions My Sites (personal sites) for imported user profiles.

.DESCRIPTION
  Run ONCE from an elevated SharePoint Management Shell on a SharePoint server,
  as the SharePoint farm account (the "System Account"), after the User Profile
  AD Import has populated the profile store. Creating personal sites is a one-shot
  operation, not a desired state, so it lives in this script rather than a DSC
  resource.

  The farm account is required because creating personal sites on behalf of other
  users goes through self-service site creation, which only the farm account is
  allowed to perform — any other account, even a User Profile Service Application
  administrator, is denied in SelfServiceCreateSite. The script verifies this and
  stops with a clear message if it is run as any other account, or from a
  non-elevated shell (#Requires -RunAsAdministrator).

  The script:
    * reads the ConfigurationData (CfgAppSps.psd1) and Secrets (Secrets.psd1),
    * enumerates every user profile in the User Profile Service,
    * skips the farm service accounts declared in Secrets.psd1,
    * creates a personal site for each remaining profile that does not have one,
    * applies the My Site quota template (NonNodeData.SharePoint.Services.MySite)
      to each personal site.

  SharePoint load-balances the new personal sites across the dedicated content
  databases provisioned by CfgAppSps (SPContentDatabase), so no database is
  targeted explicitly here.

.PARAMETER InputFile
  Full path to the ConfigurationData .psd1. Defaults to CfgAppSps.psd1 in the
  same directory as this script.

.PARAMETER SecretsFile
  Full path to the Secrets.psd1. Defaults to ..\Secrets.psd1 relative to this
  script.

.PARAMETER WhatIf
  List the profiles that would be provisioned without creating any site.

.EXAMPLE
  .\Invoke-MySiteProvisioning.ps1

.EXAMPLE
  .\Invoke-MySiteProvisioning.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [System.String]
    $InputFile,

    [Parameter()]
    [System.String]
    $SecretsFile
)

# Resolve a reliable base path even when $PSScriptRoot is empty.
[System.String] $scriptBasePath = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
else {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}

if ([string]::IsNullOrWhiteSpace($InputFile)) {
    $InputFile = Join-Path -Path $scriptBasePath -ChildPath 'CfgAppSps.psd1'
}
if (-not (Test-Path -Path $InputFile)) { throw "ConfigurationData file not found: $InputFile" }
$configurationData = Import-PowerShellDataFile -Path $InputFile

if ([string]::IsNullOrWhiteSpace($SecretsFile)) {
    $SecretsFile = Join-Path -Path (Split-Path -Path $scriptBasePath -Parent) -ChildPath 'Secrets.psd1'
}
if (-not (Test-Path -Path $SecretsFile)) { throw "Secrets file not found: $SecretsFile" }
$secretsData = Import-PowerShellDataFile -Path $SecretsFile

$mySiteCfg = $configurationData.NonNodeData.SharePoint.Services.MySite
if ($null -eq $mySiteCfg) { throw 'NonNodeData.SharePoint.Services.MySite is not declared; nothing to provision.' }

$mySiteHostLocation = $configurationData.NonNodeData.SharePoint.Services.UserProfile.MySiteHostLocation
$quotaTemplateName = $mySiteCfg.QuotaTemplateName

# SharePoint Subscription Edition exposes its cmdlets through the SharePoint Management Shell, not
# through a loadable module or PSSnapin (Import-Module / Add-PSSnapin both fail). Run this script
# from the SharePoint Management Shell on a farm server; here we only verify the cmdlets are present.
if (-not (Get-Command -Name 'Get-SPSite' -ErrorAction SilentlyContinue)) {
    throw 'SharePoint cmdlets are not available. Run this script from the SharePoint Management Shell on a SharePoint farm server.'
}

# Creating personal sites goes through self-service site creation, which only the SharePoint farm
# account (the "System Account") is allowed to perform on behalf of other users — any other account,
# even a User Profile Service Application administrator, hits Access Denied in SelfServiceCreateSite.
# Fail fast if the shell is not running as the farm account.
$farmAccount = (Get-SPFarm).TimerService.ProcessIdentity.Username
$currentAccount = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($currentAccount -ne $farmAccount) {
    throw ("This script must run as the SharePoint farm account ('{0}'), which owns site provisioning. The current account is '{1}'. Open the SharePoint Management Shell (elevated) as the farm account and retry." -f $farmAccount, $currentAccount)
}

# Build the set of service accounts to exclude (real users keep a My Site). Match on the full
# DOMAIN\user identity, not just sAMAccountName: a sAMAccountName is unique only within a domain,
# so in a multi-domain forest CHILD\svcspsearch must not be skipped merely because Secrets.psd1
# lists CONTOSO\svcspsearch.
$excludedAccounts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($sa in $secretsData.serviceAccounts) {
    if ([string]::IsNullOrWhiteSpace($sa.Username)) { continue }
    [void]$excludedAccounts.Add($sa.Username)
}

Write-Host "My Site host    : $mySiteHostLocation"
Write-Host "Quota template  : $quotaTemplateName"
Write-Host "Excluded accts  : $($excludedAccounts.Count) service account(s)"

$site = Get-SPSite -Identity $mySiteHostLocation -ErrorAction Stop
$context = Get-SPServiceContext -Site $site
# Building the UserProfileManager and enumerating it requires the running account to be a
# User Profile Service Application administrator with "Manage Profiles"; fail fast with a
# clear message if it is not, instead of a raw access-denied deep in the loop.
try {
    $profileManager = New-Object -TypeName 'Microsoft.Office.Server.UserProfiles.UserProfileManager' -ArgumentList $context
}
catch [System.UnauthorizedAccessException] {
    throw ("Access denied building the UserProfileManager. Run this script as the SharePoint farm account from an elevated SharePoint Management Shell. Details: {0}" -f $_.Exception.Message)
}

$created = 0
$skipped = 0
$failed = 0

# UserProfileManager implements IEnumerable explicitly, so `foreach ($p in $profileManager)`
# does NOT unroll it — PowerShell would iterate once with the manager itself. Drive the
# enumerator directly (MoveNext/Current) so every profile is visited.
$profileEnumerator = $profileManager.GetEnumerator()
while ($profileEnumerator.MoveNext()) {
    $userProfile = $profileEnumerator.Current
    $accountName = [string]$userProfile.AccountName          # DOMAIN\sAMAccountName

    # Some entries enumerated from the UserProfileManager have no AccountName
    # (placeholder/system profiles); skip them so we never act on an empty identity.
    if ([string]::IsNullOrWhiteSpace($accountName)) {
        $skipped++
        continue
    }

    if ($excludedAccounts.Contains($accountName)) {
        $skipped++
        continue
    }

    # SPSite objects returned by UserProfile.PersonalSite are disposable; capture once and
    # release in finally so a bulk run does not leak SharePoint request resources.
    $personalSite = $null
    try {
        $personalSite = $userProfile.PersonalSite
        if ($null -ne $personalSite) {
            # Already has a personal site; just ensure the quota is applied.
            if ($PSCmdlet.ShouldProcess($accountName, 'Apply quota template to existing My Site')) {
                Set-SPSite -Identity $personalSite.Url -QuotaTemplate $quotaTemplateName -ErrorAction Stop
            }
            $skipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess($accountName, 'Create My Site and apply quota template')) {
            $userProfile.CreatePersonalSite()
            # CreatePersonalSite() is normally synchronous, so check immediately first and only
            # fall back to a short re-query loop if a timer job hasn't finished the site yet.
            $personalSite = $userProfile.PersonalSite
            for ($attempt = 0; $attempt -lt 12 -and $null -eq $personalSite; $attempt++) {
                Start-Sleep -Seconds 5
                $personalSite = $userProfile.PersonalSite
            }
            if ($null -eq $personalSite) {
                throw 'personal site was not available after CreatePersonalSite().'
            }
            # Fail loudly if the quota cannot be applied — count only a fully provisioned site.
            Set-SPSite -Identity $personalSite.Url -QuotaTemplate $quotaTemplateName -ErrorAction Stop
            $created++
            Write-Host ("  Created My Site for {0}" -f $accountName)
        }
    }
    catch {
        $failed++
        Write-Warning ("  Failed to provision My Site for {0}: {1}" -f $accountName, $_.Exception.Message)
    }
    finally {
        if ($null -ne $personalSite) { $personalSite.Dispose() }
    }
}

$site.Dispose()

Write-Host ("Done. Created: {0}  Skipped: {1}  Failed: {2}" -f $created, $skipped, $failed)

# Terminate with an error when any profile failed, so scheduled/automated runs do not report
# success while leaving users unprovisioned.
if ($failed -gt 0) {
    throw ("My Site provisioning completed with {0} failure(s); see the warnings above." -f $failed)
}
