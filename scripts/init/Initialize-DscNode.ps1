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
  Bootstraps a Windows node so that the SPSConfigKit DSC configurations can
  compile and apply successfully.

.DESCRIPTION
  Reads a manifest (Initialize-DscNode.psd1 by default, located next to this
  script) and:
    * installs Chocolatey + the Chocolatey packages listed under Chocolatey.Packages
    * registers the NuGet PowerShellGet provider
    * installs each entry in Modules at the *exact* pinned version
    * imports the DSC document-encryption certificate into
      Cert:\LocalMachine\My so the Local Configuration Manager can decrypt
      credentials inside MOF files (mandatory for a smooth
      Start-DscConfiguration when MOFs are encrypted)

  The Chocolatey and Install-Module phases are skipped automatically when the
  node has no outbound internet access. The certificate import is a local /
  SMB operation and runs regardless of internet availability.

.PARAMETER InputFile
  Path to the .psd1 manifest. Defaults to Initialize-DscNode.psd1 alongside
  this script.

.PARAMETER PfxPassword
  SecureString used to import the .pfx file referenced by
  Certificate.PfxFileName. If omitted and a .pfx is present on the share, the
  script prompts interactively via Read-Host -AsSecureString. Ignored when
  only the .cer (public key) is available.

.EXAMPLE
  .\Initialize-DscNode.ps1

.EXAMPLE
  .\Initialize-DscNode.ps1 -InputFile 'C:\Lab\Initialize-DscNode.psd1'

.EXAMPLE
  $pfxPwd = Read-Host 'PFX password' -AsSecureString
  .\Initialize-DscNode.ps1 -PfxPassword $pfxPwd
#>
param(
    [Parameter()]
    [System.String]
    $InputFile,

    [Parameter()]
    [System.Security.SecureString]
    $PfxPassword
)

# Clear the host console
Clear-Host

#Resolve a reliable base path even when $PSScriptRoot is empty (for example when executed interactively)
[System.String] $scriptBasePath = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
else {
    (Get-Location).Path
}

#Import configuration data from the specified .psd1 file
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    $InputFile = Join-Path -Path $scriptBasePath -ChildPath 'Initialize-DscNode.psd1'
    Write-Host "No -InputFile provided. Falling back to '$InputFile'."
}
if (Test-Path -Path $InputFile) {
    Write-Host "Importing configuration data from '$InputFile'."
    $configurationData = Import-PowerShellDataFile -Path $InputFile
}
else {
    throw "Missing manifest file '$InputFile'."
}

# Detect outbound internet access once. Steps that require the public
# internet (Chocolatey bootstrap, Install-Module) honour this flag.
Write-Host 'Checking outbound internet access...'
$hasInternet = $false
try {
    $hasInternet = Test-NetConnection -ComputerName 'www.microsoft.com' `
        -CommonTCPPort HTTP -InformationLevel Quiet -WarningAction SilentlyContinue
}
catch {
    $hasInternet = $false
}
if ($hasInternet) {
    Write-Host 'Internet access detected.'
}
else {
    Write-Warning 'No outbound internet access detected. Chocolatey and Install-Module steps will be skipped.'
}

# Install Chocolatey and the requested packages.
if ($configurationData.Chocolatey.Ensure -eq 'Present') {
    if (-not $hasInternet) {
        Write-Warning 'Skipping Chocolatey step: no internet access.'
    }
    else {
        Write-Host 'Ensuring Chocolatey is installed...'
        $chocoInstalled = Get-Command -Name choco -ErrorAction SilentlyContinue
        if ($chocoInstalled) {
            Write-Host 'Chocolatey is already installed.'
        }
        else {
            Write-Host 'Chocolatey is not installed. Installing...'
            Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing |
                Invoke-Expression
        }

        # Enable global confirmation to avoid prompts during installation
        choco feature enable -n allowGlobalConfirmation

        foreach ($package in $configurationData.Chocolatey.Packages) {
            Write-Host "Installing Chocolatey package: $package"
            choco install $package
        }
    }
}
else {
    Write-Host 'Chocolatey installation is not required as per configuration.'
}

# Install required PowerShell modules at their pinned versions.
if ($configurationData.Modules.Count -ne 0) {
    if (-not $hasInternet) {
        Write-Warning 'Skipping Install-Module step: no internet access.'
    }
    else {
        Write-Host 'Ensuring required PowerShell modules are installed...'

        # Register the NuGet provider if it is not already available. Note: do NOT
        # pipe Get-PackageProvider to Out-Null — that swallows the object and the
        # subsequent -not check would always be true.
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nugetProvider) {
            Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' `
                -Force -Scope AllUsers -Confirm:$false | Out-Null
        }

        foreach ($module in $configurationData.Modules) {
            $name    = $module.Name
            $version = $module.Version

            $installed = Get-InstalledModule -Name $name -RequiredVersion $version `
                -ErrorAction SilentlyContinue
            if ($installed) {
                Write-Host "Module '$name' v$version is already installed."
            }
            else {
                Write-Host "Installing module '$name' v$version..."
                Install-Module -Name $name -RequiredVersion $version `
                    -Force -AllowClobber -Scope AllUsers -Confirm:$false
            }
        }
    }
}
else {
    Write-Host 'No PowerShell modules specified for installation.'
}

# Import the DSC document-encryption certificate. Mandatory for a smooth
# Start-DscConfiguration when MOFs carry encrypted credentials: without the
# matching private key in Cert:\LocalMachine\My the LCM cannot decrypt.
$cert = $configurationData.Certificate
if ($cert -and $cert.Ensure -eq 'Present') {
    Write-Host 'Importing DSC document-encryption certificate...'

    $store       = if ($cert.Store) { $cert.Store } else { 'Cert:\LocalMachine\My' }
    $cerPath     = Join-Path -Path $cert.SourcePath -ChildPath $cert.CerFileName
    $pfxPath     = if ($cert.PfxFileName) { Join-Path -Path $cert.SourcePath -ChildPath $cert.PfxFileName } else { $null }
    $cerExists   = Test-Path -Path $cerPath
    $pfxExists   = $pfxPath -and (Test-Path -Path $pfxPath)

    # Idempotency: skip if a cert with the configured Subject is already in the
    # store AND we already have a private key for it (when a .pfx is expected).
    $existing = Get-ChildItem -Path $store -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $cert.Subject }

    $needsPfx    = $pfxExists
    $alreadyDone = $existing -and ((-not $needsPfx) -or ($existing | Where-Object HasPrivateKey))

    if ($alreadyDone) {
        $tp = ($existing | Select-Object -First 1).Thumbprint
        Write-Host "Certificate '$($cert.Subject)' already present in '$store' (thumbprint $tp). Skipping."
    }
    elseif ($pfxExists) {
        Write-Host "Importing '$pfxPath' into '$store'."
        if (-not $PfxPassword) {
            $PfxPassword = Read-Host -Prompt 'PFX password' -AsSecureString
        }
        try {
            Import-PfxCertificate -FilePath $pfxPath `
                -CertStoreLocation $store -Password $PfxPassword -Exportable:$false | Out-Null
            Write-Host 'PFX import succeeded.'
        }
        catch {
            Write-Error "Failed to import PFX '$pfxPath': $($_.Exception.Message)"
        }
    }
    elseif ($cerExists) {
        Write-Warning @"
Only the public .cer was found at '$cerPath' (no .pfx). The node will be able
to reference the public key but the LCM CANNOT decrypt MOFs without the
private key. Re-run Initialize-DscEncryption.ps1 with -PfxPassword to export
the .pfx, or copy it onto the share, then re-run this script.
"@
        try {
            Import-Certificate -FilePath $cerPath -CertStoreLocation $store | Out-Null
            Write-Host 'Public certificate imported (no private key).'
        }
        catch {
            Write-Error "Failed to import certificate '$cerPath': $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "No certificate files found at '$($cert.SourcePath)' (looked for '$($cert.CerFileName)' and '$($cert.PfxFileName)'). Run Initialize-DscEncryption.ps1 first."
    }
}
else {
    Write-Host 'DSC certificate import is not required as per configuration.'
}
