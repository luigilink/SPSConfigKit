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
  Optionally points a node's DNS at the domain controller and joins it to the
  Active Directory domain, before the node's DSC configuration is applied.

.DESCRIPTION
  A freshly provisioned cloud node (for example an Azure VM, whose default DNS
  is 168.63.129.16) does not resolve the SPSConfigKit domain and therefore
  cannot join it. This helper is a deliberately SEPARATE, OPTIONAL script (it is
  NOT part of Initialize-DscNode.ps1, which must stay idempotent and free of
  network / reboot side effects). Customers whose DNS already resolves the
  domain simply do not run it.

  Reads a manifest (Add-DscNodeToDomain.psd1 by default, located next to this
  script) and:
    * skips everything when the node is already a member of the target domain
    * sets the DNS server(s) on the active adapter(s) when DnsServers is set
    * waits for the domain to become resolvable (SRV lookup, with a timeout)
    * joins the domain using the credential named by JoinAccount, read from
      Secrets.psd1 with the same serviceAccounts pattern as the Cfg*.ps1 scripts
    * restarts the node when Restart = $true (required to complete membership)

  The script is idempotent: run it again after the reboot and it detects the
  existing membership and exits without changes.

.PARAMETER InputFile
  Path to the .psd1 manifest. Defaults to Add-DscNodeToDomain.psd1 alongside
  this script.

.PARAMETER SecretsFile
  Path to Secrets.psd1. Defaults to Secrets.psd1 in the parent directory of this
  script (scripts\Secrets.psd1), matching the Cfg*.ps1 convention.

.EXAMPLE
  .\Add-DscNodeToDomain.ps1

.EXAMPLE
  .\Add-DscNodeToDomain.ps1 -InputFile 'C:\Lab\Add-DscNodeToDomain.psd1'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [System.String]
    $InputFile,

    [Parameter()]
    [System.String]
    $SecretsFile
)

# Clear the host console
Clear-Host

# Resolve a reliable base path even when $PSScriptRoot is empty (for example
# when executed interactively).
[System.String] $scriptBasePath = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
else {
    (Get-Location).Path
}

# Import the manifest.
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    $InputFile = Join-Path -Path $scriptBasePath -ChildPath 'Add-DscNodeToDomain.psd1'
    Write-Host "No -InputFile provided. Falling back to '$InputFile'."
}
if (Test-Path -Path $InputFile) {
    Write-Host "Importing configuration data from '$InputFile'."
    $configurationData = Import-PowerShellDataFile -Path $InputFile
}
else {
    throw "Missing manifest file '$InputFile'."
}

[System.String] $domainName = $configurationData.DomainName
if ([string]::IsNullOrWhiteSpace($domainName)) {
    throw "The manifest '$InputFile' does not define a DomainName."
}
[System.Object[]] $dnsServers = @($configurationData.DnsServers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
[System.String] $ouPath = $configurationData.OUPath
[System.String] $joinAccountName = if ([string]::IsNullOrWhiteSpace($configurationData.JoinAccount)) { 'ADSETUP' } else { $configurationData.JoinAccount }
[System.Boolean] $restart = if ($null -eq $configurationData.Restart) { $true } else { [System.Boolean] $configurationData.Restart }

# Idempotency: bail out early when the node is already in the target domain.
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
if ($computerSystem.PartOfDomain -and $computerSystem.Domain -eq $domainName) {
    Write-Host "Node '$($computerSystem.Name)' is already a member of domain '$domainName'. Nothing to do."
    return
}
if ($computerSystem.PartOfDomain -and $computerSystem.Domain -ne $domainName) {
    throw "Node is already joined to a different domain '$($computerSystem.Domain)'. Refusing to move it to '$domainName'."
}

# Build the join credential from Secrets.psd1 (same pattern as the Cfg*.ps1
# scripts: one PSCredential per serviceAccounts entry, keyed by Name).
if ([string]::IsNullOrWhiteSpace($SecretsFile)) {
    $SecretsFile = Join-Path -Path (Split-Path -Path $scriptBasePath -Parent) -ChildPath 'Secrets.psd1'
    Write-Host "No -SecretsFile provided. Falling back to '$SecretsFile'."
}
if (-not (Test-Path -Path $SecretsFile)) {
    throw "Missing secrets file '$SecretsFile'."
}
Write-Host "Importing secrets data from '$SecretsFile'."
$secretsData = Import-PowerShellDataFile -Path $SecretsFile
$joinAccount = $secretsData.serviceAccounts | Where-Object -FilterScript { $_.Name -eq $joinAccountName } | Select-Object -First 1
if ($null -eq $joinAccount) {
    throw "Secrets.psd1 has no serviceAccounts entry named '$joinAccountName' (JoinAccount)."
}
$securePassword = ConvertTo-SecureString -String $joinAccount.Password -AsPlainText -Force
$joinCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $joinAccount.Username, $securePassword

# Set the DNS servers on the active adapter(s) so the domain can be resolved.
# Target only the up, non-loopback adapters that own an IPv4 default gateway
# (the primary NIC) to avoid touching secondary / disconnected interfaces.
if ($dnsServers.Count -gt 0) {
    $targetAdapters = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' }
    if (-not $targetAdapters) {
        # Fallback: any up, non-virtual adapter.
        $targetAdapters = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' }
    }
    if (-not $targetAdapters) {
        throw 'No active network adapter found to set DNS servers on.'
    }
    foreach ($adapter in $targetAdapters) {
        Write-Host "Setting DNS servers on adapter '$($adapter.InterfaceAlias)' to: $($dnsServers -join ', ')"
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dnsServers
    }
    Clear-DnsClientCache
}
else {
    Write-Host 'No DnsServers specified in the manifest. Keeping the current DNS configuration.'
}

# Wait for the domain to become resolvable before attempting the join. Query the
# LDAP SRV record rather than a plain A record so we know a domain controller is
# actually reachable, not just that the name resolves.
[System.String] $srvRecord = "_ldap._tcp.dc._msdcs.$domainName"
[System.Int32] $retryCount = 30
[System.Int32] $retryIntervalSec = 10
[System.Boolean] $domainReady = $false
Write-Host "Waiting for domain '$domainName' to become resolvable (up to $($retryCount * $retryIntervalSec) seconds)..."
for ($i = 1; $i -le $retryCount -and -not $domainReady; $i++) {
    try {
        $records = Resolve-DnsName -Name $srvRecord -Type SRV -DnsOnly -ErrorAction Stop
        if ($records) {
            $domainReady = $true
            Write-Host "Domain '$domainName' is resolvable (found a domain controller SRV record)."
        }
    }
    catch {
        Start-Sleep -Seconds $retryIntervalSec
    }
}
if (-not $domainReady) {
    throw "Domain '$domainName' did not become resolvable in time. Check DnsServers and that the domain controller is reachable."
}

# Join the domain. -Force suppresses the confirmation prompt; the OUPath is
# passed only when supplied so the computer object lands in the default
# Computers container otherwise.
$addComputerParams = @{
    DomainName  = $domainName
    Credential  = $joinCredential
    Force       = $true
    ErrorAction = 'Stop'
}
if (-not [string]::IsNullOrWhiteSpace($ouPath)) {
    $addComputerParams['OUPath'] = $ouPath
}
if ($restart) {
    $addComputerParams['Restart'] = $true
}

Write-Host "Joining domain '$domainName' as '$($joinAccount.Username)'..."
Add-Computer @addComputerParams
if ($restart) {
    Write-Host "Domain join requested; the node will restart to complete membership."
}
else {
    Write-Host "Domain join complete. Restart the node manually before applying its DSC configuration."
}
