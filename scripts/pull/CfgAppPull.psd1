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
    # Data disks, initialised by scripts/init/Initialize-DscDisks.ps1 (keyed by disk Number).
    # Drives.{Data,Logs} letters are DERIVED from this by Type. Best practice: at
    # least 3 disks (SYSTEM/DATA/LOGS). Disk numbers are environment-specific:
    #   a plain VM is usually 0=OS, 1=Data, 2=Logs; an Azure VM WITH a temp disk
    #   shifts to 0=OS, 1=<temp>, 2=Data, 3=Logs — adjust Id to match 'Get-Disk'.
    Disks = @(
      @{ Id = '0'; Letter = 'C'; Type = 'OS';   FSLabel = 'SYSTEM' ; AllocationUnitSize = 4KB }
      @{ Id = '2'; Letter = 'F'; Type = 'Data'; FSLabel = 'DATA'   ; AllocationUnitSize = 4KB }
      @{ Id = '3'; Letter = 'G'; Type = 'Logs'; FSLabel = 'LOGS'   ; AllocationUnitSize = 4KB }
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
