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
  Populates the SoftwarePackages file share consumed by every node in the lab.

.DESCRIPTION
  This script is meant to run ONCE, on the single VM that hosts the SMB share
  used by every other node in the SPSConfigKit lab (for example
  \\PULL\SoftwarePackages, backed by F:\SoftwarePackages).

  Reads a manifest (Initialize-SoftwarePackages.psd1 by default, located next
  to this script) and:
    * optionally installs Chocolatey + the packages listed under
      Chocolatey.Packages (left empty by default; the file-share host has
      no hard external dependency)
    * for each entry in SoftwarePackages:
        - downloads the file to %TEMP% (or directly to the target folder
          when Extract = $false)
        - expands ISO contents to the target folder when Extract = $true,
          using Windows' native Mount-DiskImage / Copy-Item / Dismount-DiskImage
          pipeline (no 7-Zip required)
        - unblocks downloaded .exe files (extracted ISO content carries no
          Mark-of-the-Web so does not need unblocking)

  The Chocolatey and download phases are skipped automatically when the host
  has no outbound internet access. Per-package failures are caught and
  logged so that one bad URL does not abort the whole run.

.PARAMETER InputFile
  Path to the .psd1 manifest. Defaults to Initialize-SoftwarePackages.psd1
  alongside this script.

.EXAMPLE
  .\Initialize-SoftwarePackages.ps1

.EXAMPLE
  .\Initialize-SoftwarePackages.ps1 -InputFile 'C:\Lab\Initialize-SoftwarePackages.psd1'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [System.String]
    $InputFile
)

# Clear the host console
Clear-Host

# Force TLS 1.2 for Microsoft download CDNs (Windows Server 2016 and older
# default to TLS 1.0/1.1 which the CDN rejects).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Silence the Invoke-WebRequest progress bar. Windows PowerShell 5.1 redraws it
# on every byte chunk, which makes large downloads CPU-bound on console
# rendering rather than bandwidth-bound and slows them by an order of magnitude.
$ProgressPreference = 'SilentlyContinue'

function Invoke-SPSDownload {
    <#
    .SYNOPSIS
      Downloads a file to disk, preferring BITS over Invoke-WebRequest.

    .DESCRIPTION
      Multi-GB ISOs (SQL Server, SharePoint Server, Language Packs) download much
      faster and more reliably over BITS (Background Intelligent Transfer Service):
      it is multi-part, resumable across a dropped Bastion/RDP session, and native
      to Windows Server. When the BitsTransfer module or the BITS service is not
      available (for example under PowerShell 7, or when blocked by GPO), the
      function transparently falls back to Invoke-WebRequest.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $Uri,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutFile
    )

    $bits = Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue
    if ($bits) {
        try {
            Start-BitsTransfer -Source $Uri -Destination $OutFile -ErrorAction Stop
            return
        }
        catch {
            Write-Warning "BITS transfer failed ($($_.Exception.Message)). Falling back to Invoke-WebRequest."
            # BITS can leave a partial .tmp next to the destination on failure.
            Remove-Item -Path ('{0}.tmp' -f $OutFile) -ErrorAction SilentlyContinue
        }
    }

    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

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

# Import configuration data from the specified .psd1 file.
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    $InputFile = Join-Path -Path $scriptBasePath -ChildPath 'Initialize-SoftwarePackages.psd1'
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
# internet (Chocolatey bootstrap, file downloads) honour this flag.
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
    Write-Warning 'No outbound internet access detected. Chocolatey and download steps will be skipped.'
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

# Download and extract required software packages.
if ($configurationData.SoftwarePackages.Count -ne 0) {
    Write-Host 'Ensuring required software packages are downloaded and extracted...'

    foreach ($software in $configurationData.SoftwarePackages) {
        $name        = $software.Name
        $description = $software.Description
        $fileName    = $software.FileName
        $url         = $software.Url
        $path        = Join-Path -Path $configurationData.Repository -ChildPath $software.Path
        # Optional sentinel file proving the archive has been extracted.
        # Defaults to 'setup.exe' which is correct for SQL Server, SharePoint
        # Server, and SharePoint Language Pack ISOs. Override with
        # Marker = '<file>' inside the manifest entry when needed.
        $marker      = if ($software.Marker) { $software.Marker } else { 'setup.exe' }

        Write-Host ''
        Write-Host "Processing package : $name"
        Write-Host "  Description      : $description"
        Write-Host "  FileName         : $fileName"
        Write-Host "  Url              : $url"
        Write-Host "  Target path      : $path"
        Write-Host "  Extract          : $([bool]$software.Extract)"

        if (-not $hasInternet) {
            Write-Warning "Skipping '$name': no internet access."
            continue
        }

        try {
            if ($software.Extract) {
                if (Test-Path -Path (Join-Path -Path $path -ChildPath $marker)) {
                    Write-Host "Package '$name' is already extracted (found '$marker'). Skipping."
                    continue
                }

                if (-not (Test-Path -Path $path)) {
                    New-Item -ItemType Directory -Path $path -Force | Out-Null
                }

                $fileTempPath = Join-Path -Path $env:TEMP -ChildPath $fileName
                if (-not (Test-Path -Path $fileTempPath)) {
                    Write-Host "Downloading '$fileName' to '$fileTempPath'..."
                    Invoke-SPSDownload -Uri $url -OutFile $fileTempPath
                }
                else {
                    Write-Host "Found previously downloaded '$fileTempPath'. Reusing."
                }

                # Expand the ISO using Windows' native disk-image API. No 7-Zip required.
                $mounted = $null
                try {
                    Write-Host "Mounting '$fileName'..."
                    $mounted = Mount-DiskImage -ImagePath $fileTempPath -PassThru -ErrorAction Stop

                    # Drive-letter assignment is asynchronous; poll briefly (up to ~5s).
                    $volume = $null
                    for ($i = 0; $i -lt 25 -and -not ($volume -and $volume.DriveLetter); $i++) {
                        Start-Sleep -Milliseconds 200
                        $volume = $mounted | Get-Volume
                    }
                    if (-not ($volume -and $volume.DriveLetter)) {
                        throw "ISO '$fileName' mounted but no drive letter was assigned."
                    }

                    $source = '{0}:\' -f $volume.DriveLetter
                    Write-Host "Copying contents from '$source' to '$path'..."
                    Copy-Item -Path (Join-Path -Path $source -ChildPath '*') `
                        -Destination $path -Recurse -Force
                }
                finally {
                    if ($mounted) {
                        Dismount-DiskImage -ImagePath $fileTempPath -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                Remove-Item -Path $fileTempPath -ErrorAction SilentlyContinue
            }
            else {
                $filePath = Join-Path -Path $path -ChildPath $fileName
                if (Test-Path -Path $filePath) {
                    Write-Host "Package '$name' is already downloaded. Skipping."
                    continue
                }

                if (-not (Test-Path -Path $path)) {
                    New-Item -ItemType Directory -Path $path -Force | Out-Null
                }

                Write-Host "Downloading '$fileName' to '$filePath'..."
                Invoke-SPSDownload -Uri $url -OutFile $filePath
                Unblock-File -Path $filePath
            }
        }
        catch {
            Write-Error "Failed to process package '$name': $($_.Exception.Message)"
            continue
        }
    }
}
else {
    Write-Host 'No software packages specified for download.'
}
