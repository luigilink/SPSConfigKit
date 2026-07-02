<#
  Generates samples/mock-data.json mirroring the pull-server OData shape (including
  the doubly-encoded StatusData string), so New-SPSDscDashboard.ps1 can be exercised
  offline without a live pull server.
#>
[CmdletBinding()]
param(
  [string] $OutputPath = (Join-Path $PSScriptRoot 'mock-data.json')
)

function New-Resource {
  param([string]$Id, [string]$Module, [string]$Version, [bool]$InState, [string]$Duration, [string]$ErrorText)
  return [ordered]@{
    ResourceId        = $Id
    ModuleName        = $Module
    ModuleVersion     = $Version
    InstanceName      = $Id
    InDesiredState    = "$InState"
    DurationInSeconds = $Duration
    Error             = $ErrorText
  }
}

function New-StatusData {
  param([array]$InState, [array]$NotInState, [string]$Status, [string]$Duration)
  $obj = [ordered]@{
    StartDate                  = (Get-Date).ToString('o')
    DurationInSeconds          = $Duration
    Status                     = $Status
    LCMVersion                 = '2.0'
    NumberOfResources          = "$(@($InState).Count + @($NotInState).Count)"
    Type                       = 'Consistency'
    Mode                       = 'Pull'
    ResourcesInDesiredState    = @($InState)
    ResourcesNotInDesiredState = @($NotInState)
  }
  # OData returns StatusData as an array whose single element is a JSON string.
  $inner = $obj | ConvertTo-Json -Depth 8 -Compress
  return , @($inner)
}

$now = Get-Date

$nodes = @(
  [ordered]@{ AgentId = '52DA826D-00DE-4166-8ACB-73F2B46A7E00'; NodeName = 'APP1'; ConfigurationNames = @('CfgAppSps'); IPAddress = '10.1.1.11' }
  [ordered]@{ AgentId = '7B1C0A44-9F2E-4C81-B6D3-2A5E9F0C1D22'; NodeName = 'WFE1'; ConfigurationNames = @('CfgAppSps'); IPAddress = '10.1.1.12' }
  [ordered]@{ AgentId = '9C3E1B77-4D6A-4E2F-8B10-6F7A2C4E8D33'; NodeName = 'SCH1'; ConfigurationNames = @('CfgAppSps'); IPAddress = '10.1.1.13' }
  [ordered]@{ AgentId = 'A1F2D399-8E5B-4A73-9C24-7D8B3E5F1A44'; NodeName = 'OOS1'; ConfigurationNames = @('CfgAppSps'); IPAddress = '10.1.1.14' }
  [ordered]@{ AgentId = 'B4A5E611-2C7D-4F90-A138-9E0C4B6D2E55'; NodeName = 'SQL1'; ConfigurationNames = @('CfgAppSql'); IPAddress = '10.1.1.10' }
)

$reports = [ordered]@{}

# APP1 — Compliant
$app1In = @(
  (New-Resource '[SPFarm]APPLICATION_SpsCreateSPFarm' 'SharePointDsc' '5.7.0' $true '42.1' '')
  (New-Resource '[SPInstall]APPLICATION_SpsInstallSharePoint' 'SharePointDsc' '5.7.0' $true '310.8' '')
  (New-Resource '[xCredSSP]SECURITY_CredSSPServer' 'xCredSSP' '1.4.0' $true '0.9' '')
)
$reports['52DA826D-00DE-4166-8ACB-73F2B46A7E00'] = @(
  [ordered]@{ JobId = [guid]::NewGuid().ToString(); Id = '52DA826D-00DE-4166-8ACB-73F2B46A7E00'; OperationType = 'Consistency'; RefreshMode = 'Pull'; Status = 'Success'; ConfigurationVersion = '2.0.0'; NodeName = 'APP1'; StartTime = $now.AddMinutes(-8).ToString('o'); EndTime = $now.AddMinutes(-7).ToString('o'); Errors = @(); StatusData = (New-StatusData $app1In @() 'Success' '353.8') }
)

# WFE1 — Non-compliant (1 drift)
$wfe1In = @( (New-Resource '[SPFarm]APPLICATION_SpsJoinSPFarm' 'SharePointDsc' '5.7.0' $true '38.4' '') )
$wfe1Not = @( (New-Resource '[SPDistributedCacheService]APPLICATION_SpsEnableDistributedCache' 'SharePointDsc' '5.7.0' $false '5.2' '') )
$reports['7B1C0A44-9F2E-4C81-B6D3-2A5E9F0C1D22'] = @(
  [ordered]@{ JobId = [guid]::NewGuid().ToString(); Id = '7B1C0A44-9F2E-4C81-B6D3-2A5E9F0C1D22'; OperationType = 'Consistency'; RefreshMode = 'Pull'; Status = 'Success'; ConfigurationVersion = '2.0.0'; NodeName = 'WFE1'; StartTime = $now.AddMinutes(-6).ToString('o'); EndTime = $now.AddMinutes(-5).ToString('o'); Errors = @(); StatusData = (New-StatusData $wfe1In $wfe1Not 'Success' '43.6') }
)

# SCH1 — Failed
$sch1In = @( (New-Resource '[SPSearchServiceApp]APPLICATION_SpsSvcAppSearchServiceApp' 'SharePointDsc' '5.7.0' $true '22.0' '') )
$sch1Not = @( (New-Resource '[SPSearchTopology]APPLICATION_SpsSvcSearchTopo' 'SharePointDsc' '5.7.0' $false '0' 'The search service instance is not online on server SCH1.') )
$reports['9C3E1B77-4D6A-4E2F-8B10-6F7A2C4E8D33'] = @(
  [ordered]@{ JobId = [guid]::NewGuid().ToString(); Id = '9C3E1B77-4D6A-4E2F-8B10-6F7A2C4E8D33'; OperationType = 'Consistency'; RefreshMode = 'Pull'; Status = 'Failure'; ConfigurationVersion = '2.0.0'; NodeName = 'SCH1'; StartTime = $now.AddMinutes(-4).ToString('o'); EndTime = $now.AddMinutes(-3).ToString('o'); Errors = @('The search service instance is not online on server SCH1.'); StatusData = (New-StatusData $sch1In $sch1Not 'Failure' '22.0') }
)

# OOS1 — Compliant
$oos1In = @(
  (New-Resource '[OfficeOnlineServerInstall]APPLICATION_OOSInstallBinaries' 'OfficeOnlineServerDsc' '1.5.0' $true '120.5' '')
  (New-Resource '[OfficeOnlineServerFarm]APPLICATION_CreateWACFarm' 'OfficeOnlineServerDsc' '1.5.0' $true '18.7' '')
)
$reports['A1F2D399-8E5B-4A73-9C24-7D8B3E5F1A44'] = @(
  [ordered]@{ JobId = [guid]::NewGuid().ToString(); Id = 'A1F2D399-8E5B-4A73-9C24-7D8B3E5F1A44'; OperationType = 'Consistency'; RefreshMode = 'Pull'; Status = 'Success'; ConfigurationVersion = '2.0.0'; NodeName = 'OOS1'; StartTime = $now.AddMinutes(-9).ToString('o'); EndTime = $now.AddMinutes(-8).ToString('o'); Errors = @(); StatusData = (New-StatusData $oos1In @() 'Success' '139.2') }
)

# SQL1 — Unresponsive (no reports)
$reports['B4A5E611-2C7D-4F90-A138-9E0C4B6D2E55'] = @()

$mock = [ordered]@{ Nodes = $nodes; Reports = $reports }
$mock | ConvertTo-Json -Depth 12 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "mock-data.json written: $OutputPath ($((Get-Item $OutputPath).Length) bytes)"
