@{
  AllNodes    =
  @(
    @{
      NodeName                    = '*'
      PSDscAllowPlainTextPassword = $True
      PSDscAllowDomainUser        = $True
    }
    @{
      NodeName             = 'PULL'
      IsPullServer         = $true
      # Generated with: [guid]::NewGuid() in PowerShell
      RegistrationKey      = '********-****-****-****-************'
    }
  )
  NonNodeData = @{
    # Single share root — host the SoftwarePackages share on a MEMBER server
    # (e.g. this pull server), NOT on a domain controller. The certificate path is
    # derived from this by CfgAppPull.ps1 (SourcePath + CerFileName / PfxFileName).
    SourcePath = '\\PULL\Softwarepackages'
    # Set to $false when the customer manages storage themselves. Default $true.
    ManageDisks = $true
    # Data disks to initialise on first boot (StorageDsc, keyed by disk Number).
    # Drives.{Data,Logs} letters are DERIVED from this by Type. Best practice: at
    # least 3 disks (SYSTEM/DATA/LOGS). Adjust Id to match 'Get-Disk' on the node.
    Disks = @(
      @{ Id = '0'; Letter = 'C'; Type = 'OS';   FSLabel = 'SYSTEM' ; AllocationUnitSize = 4KB }
      @{ Id = '1'; Letter = 'F'; Type = 'Data'; FSLabel = 'DATA'   ; AllocationUnitSize = 4KB }
      @{ Id = '2'; Letter = 'G'; Type = 'Logs'; FSLabel = 'LOGS'   ; AllocationUnitSize = 4KB }
    )
    ADC        = @{
      certificates = @(
        @{
          Name         = 'DscPullCert'
          FriendlyName = 'DSCPull'
          CerFileName  = 'DscPull.cer'
          PfxFileName  = 'DscPull.pfx'
        }
      )
    }
    IIS        = @{
      LogFolder     = 'LOGS\IIS'
      httpErrFolder = 'LOGS\HTTPERR'
    }
  }
}
