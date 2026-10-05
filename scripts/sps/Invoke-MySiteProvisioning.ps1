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
  Run ONCE on a SharePoint server (as a farm administrator) after the User
  Profile AD Import has populated the profile store. Creating personal sites is
  a one-shot operation, not a desired state, so it lives in this script rather
  than a DSC resource.

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

# Load the SharePoint cmdlets. SharePoint registers the Microsoft.SharePoint.PowerShell PSSnapin
# (Windows PowerShell 5.1) rather than a module on $env:PSModulePath, so Add-PSSnapin is the
# reliable entry point — the same thing the SharePoint Management Shell does. Snap-ins are not
# available in PowerShell 7+, so this script must run in Windows PowerShell.
if ($PSVersionTable.PSEdition -eq 'Core') {
    throw 'Run this script in Windows PowerShell 5.1 (the SharePoint Management Shell), not PowerShell 7+: the Microsoft.SharePoint.PowerShell snap-in is not available in PowerShell Core.'
}
if (-not (Get-PSSnapin -Name 'Microsoft.SharePoint.PowerShell' -ErrorAction SilentlyContinue)) {
    Add-PSSnapin -Name 'Microsoft.SharePoint.PowerShell' -ErrorAction Stop
}

# Build the set of service-account sAMAccountNames to exclude (real users keep a My Site).
$excludedSam = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($sa in $secretsData.serviceAccounts) {
    if ($null -eq $sa.Username) { continue }
    [void]$excludedSam.Add(($sa.Username -replace '.*\\', ''))
}

Write-Host "My Site host    : $mySiteHostLocation"
Write-Host "Quota template  : $quotaTemplateName"
Write-Host "Excluded accts  : $($excludedSam.Count) service account(s)"

$site = Get-SPSite -Identity $mySiteHostLocation -ErrorAction Stop
$context = Get-SPServiceContext -Site $site
$profileManager = New-Object -TypeName 'Microsoft.Office.Server.UserProfiles.UserProfileManager' -ArgumentList $context

$created = 0
$skipped = 0
$failed = 0

foreach ($userProfile in $profileManager) {
    $accountName = [string]$userProfile.AccountName          # DOMAIN\sAMAccountName
    $sam = $accountName -replace '.*\\', ''

    if ($excludedSam.Contains($sam)) {
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
            # CreatePersonalSite() does not guarantee the site is immediately available
            # (a timer job may finish it), so re-query until it appears before applying the quota.
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
