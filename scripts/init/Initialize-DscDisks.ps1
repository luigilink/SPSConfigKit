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
  Initialises and formats a node's data disks during bootstrap, from the same
  NonNodeData.Disks definition the DSC configuration uses.

.DESCRIPTION
  Disk initialisation is a one-time NODE-PREPARATION step (like joining the
  domain or installing the DSC modules), so it is done here in the bootstrap
  phase rather than inside the recurring application MOF. Run it once per node,
  after Initialize-DscNode.ps1 and before compiling / applying the node's
  configuration, so that F: / G: (and any other declared volumes) exist before
  anything writes to them (for example Initialize-SoftwarePackages.ps1, which
  populates <Data>:\SoftwarePackages).

  The disk layout is the single source of truth already declared in the node's
  Cfg*.psd1 under NonNodeData.Disks (Id / Letter / Type / FSLabel /
  AllocationUnitSize) with the NonNodeData.ManageDisks switch. This script reads
  that same block via -ConfigPath, so nothing is duplicated:

    * ManageDisks = $false  -> the customer manages storage; the script exits
      without touching any disk (the Cfg*.ps1 still derives the Drives letters).
    * The OS disk (Type 'OS') is NEVER initialised or formatted.
    * Disks are keyed by their Windows disk NUMBER (Get-Disk), portable across
      bare-metal, VMware, Hyper-V and Azure (NOT an Azure LUN).

  Behaviour per data disk (idempotent, non-destructive):
    * a disk already carrying a volume on the target drive letter is left as-is
      (only its label is corrected if needed);
    * an offline / read-only / RAW disk is brought online and GPT-initialised,
      then a single max-size NTFS partition is created on the requested drive
      letter with the requested label and allocation unit size;
    * a disk that already has UNEXPECTED partitions (data we did not create) is
      left untouched and reported — this script never destroys existing data.
      Clear such a disk manually (Clear-Disk) if you really want it reformatted.

.PARAMETER ConfigPath
  Path to the node's Cfg*.psd1 whose NonNodeData.Disks / ManageDisks describe the
  disk layout (for example scripts\pull\CfgAppPull.psd1 on the pull server, or
  scripts\sql\CfgAppSql.psd1 on the SQL server).

.EXAMPLE
  .\Initialize-DscDisks.ps1 -ConfigPath ..\pull\CfgAppPull.psd1

.EXAMPLE
  # Dry-run: show what would happen without changing any disk
  .\Initialize-DscDisks.ps1 -ConfigPath ..\sql\CfgAppSql.psd1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [System.String]
    $ConfigPath
)

# Clear the host console
Clear-Host

# Tolerate a path pasted with surrounding quotes or stray whitespace (a common
# copy/paste / Bastion artefact that otherwise makes Test-Path look for a file
# whose name literally contains a quote character).
$ConfigPath = $ConfigPath.Trim().Trim('"', "'").Trim()

if (-not (Test-Path -Path $ConfigPath)) {
    throw "Missing configuration file '$ConfigPath'. Point -ConfigPath at the node's Cfg*.psd1 (e.g. ..\pull\CfgAppPull.psd1)."
}
Write-Host "Reading disk layout from '$ConfigPath'."
$configurationData = Import-PowerShellDataFile -Path $ConfigPath
$nonNodeData = $configurationData.NonNodeData
if ($null -eq $nonNodeData) {
    throw "'$ConfigPath' has no NonNodeData section."
}

# ManageDisks = $false -> the customer manages their own storage. Do nothing.
if ($null -ne $nonNodeData.ManageDisks -and [System.Boolean] $nonNodeData.ManageDisks -eq $false) {
    Write-Host 'NonNodeData.ManageDisks is $false: storage is managed by the customer. Nothing to do.'
    return
}

$disks = @($nonNodeData.Disks)
if ($disks.Count -eq 0) {
    Write-Warning "'$ConfigPath' declares no NonNodeData.Disks. Nothing to do."
    return
}

# Only the data disks are provisioned; the OS disk is never touched.
$dataDisks = $disks | Where-Object { $_.Type -ne 'OS' }
if (-not $dataDisks) {
    Write-Host 'No non-OS disks declared. Nothing to do.'
    return
}

[System.Int32] $failures = 0

foreach ($disk in $dataDisks) {
    [System.Int32] $number = [System.Int32] $disk.Id
    [System.String] $letter = ($disk.Letter -replace ':', '')
    [System.String] $label = $disk.FSLabel
    $allocationUnitSize = $disk.AllocationUnitSize

    Write-Host ''
    Write-Host "Processing disk Number $number -> ${letter}: ('$label')"

    $target = Get-Disk -Number $number -ErrorAction SilentlyContinue
    if ($null -eq $target) {
        Write-Error "No disk with Number $number found. Adjust the Id in '$ConfigPath' to match 'Get-Disk' on this node (an Azure temp disk shifts data/logs to 2/3)."
        $failures++
        continue
    }

    # Safety net: never touch the boot / system disk even if it was mis-typed.
    if ($target.IsBoot -or $target.IsSystem) {
        Write-Warning "Disk Number $number is the boot/system disk. Skipping (check the Type in the manifest)."
        continue
    }

    # Idempotency: a volume already on the target drive letter -> leave it, only
    # fix the label if it drifted.
    $existingVolume = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
    if ($existingVolume) {
        $ownerDisk = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty DiskNumber -First 1
        if ($ownerDisk -eq $number) {
            if ($existingVolume.FileSystemLabel -ne $label) {
                if ($PSCmdlet.ShouldProcess("${letter}: (disk $number)", "Set volume label to '$label'")) {
                    Set-Volume -DriveLetter $letter -NewFileSystemLabel $label
                    Write-Host "  Volume ${letter}: already present; label corrected to '$label'."
                }
            }
            else {
                Write-Host "  Volume ${letter}: already present and correctly labelled. Skipping."
            }
            continue
        }
        else {
            Write-Warning "  Drive letter ${letter}: is already used by disk $ownerDisk, not disk $number. Skipping to avoid a conflict."
            $failures++
            continue
        }
    }

    # Bring the disk online / writable if needed.
    if ($target.IsOffline) {
        if ($PSCmdlet.ShouldProcess("Disk $number", 'Set online')) {
            Set-Disk -Number $number -IsOffline $false
            Write-Host "  Disk $number set online."
        }
    }
    if ($target.IsReadOnly) {
        if ($PSCmdlet.ShouldProcess("Disk $number", 'Clear read-only')) {
            Set-Disk -Number $number -IsReadOnly $false
            Write-Host "  Disk $number set read-write."
        }
    }
    $target = Get-Disk -Number $number

    # A RAW disk is a fresh disk: initialise it as GPT.
    if ($target.PartitionStyle -eq 'RAW') {
        if ($PSCmdlet.ShouldProcess("Disk $number", 'Initialize as GPT')) {
            Initialize-Disk -Number $number -PartitionStyle GPT -ErrorAction Stop | Out-Null
            Write-Host "  Disk $number initialised (GPT)."
        }
    }

    # Look at the existing user partitions (ignore the GPT reserved partition).
    $userPartitions = Get-Partition -DiskNumber $number -ErrorAction SilentlyContinue |
        Where-Object { $_.Type -ne 'Reserved' -and $_.Size -gt 0 }

    if (-not $userPartitions) {
        # Fresh disk: create a single max-size partition and format it.
        if ($PSCmdlet.ShouldProcess("Disk $number", "Create ${letter}: partition and format NTFS ('$label', AUS $allocationUnitSize)")) {
            $partition = New-Partition -DiskNumber $number -UseMaximumSize -DriveLetter $letter -ErrorAction Stop
            Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label `
                -AllocationUnitSize $allocationUnitSize -Force -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "  Disk $number formatted: ${letter}: NTFS '$label' (AUS $allocationUnitSize)."
        }
    }
    else {
        # The disk already carries partitions we did not create. Do NOT destroy
        # data; report so the operator can decide (Clear-Disk to reformat).
        Write-Warning "  Disk $number already has partition(s) but none on ${letter}:. Leaving it untouched (non-destructive). Clear the disk manually if you intend to reformat it."
        $failures++
    }
}

Write-Host ''
if ($failures -gt 0) {
    throw "Disk initialisation completed with $failures issue(s). Review the warnings/errors above."
}
Write-Host 'Disk initialisation complete.'
