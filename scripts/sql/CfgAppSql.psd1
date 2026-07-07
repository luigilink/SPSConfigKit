@{
  AllNodes    =
  @(
    @{
      NodeName                    = '*'
      PSDscAllowPlainTextPassword = $True
      PSDscAllowDomainUser        = $True
    }
    @{
      NodeName             = 'SQL1'
      IsSQLServer          = $True
      IsSQLSetup           = $true
      SQLInstanceName      = 'MSSQLSERVER'
      SQLTcpPort           = 1433
      SQLCollation         = 'Latin1_General_CI_AS_KS_WS'
      SQLSysAdministrators = @('CONTOSO\svcspssetup', 'CONTOSO\svcspsfarm')
    }
  )
  NonNodeData = @{
    SourcePath  = '\\PULL\Softwarepackages'
    # Set to $false when the customer manages storage themselves (disks already
    # created, or a different layout): the WaitForDisk/Disk resources are skipped,
    # but the Drives.{Data,Logs,Temp} letters are still derived from Disks below,
    # so the rest of the configuration keeps working. Default $true.
    ManageDisks = $true
    # Data disks, initialised by scripts/init/Initialize-DscDisks.ps1 (keyed by disk Number).
    # The Drives.{Data,Logs,Temp} letters consumed elsewhere are DERIVED from this
    # list by Type, so a drive letter is declared only once.
    #   Id     : Windows disk NUMBER (see 'Get-Disk' on the node). NOT the LUN.
    #   Letter : drive letter to assign.
    #   Type   : semantic role — OS / Data / Logs / Temp. OS is never (re)initialised.
    #   FSLabel/AllocationUnitSize: NTFS volume label + AUS (SQL data/log = 64KB is common).
    # NOTE: disk numbers are environment-specific. A plain VM is usually
    #   0=OS, 1=Data, 2=Logs. An Azure VM WITH a temporary disk shifts to
    #   0=OS, 1=<temp>, 2=Data, 3=Logs — adjust Id to match 'Get-Disk'.
    Disks       = @(
      @{ Id = '0'; Letter = 'C'; Type = 'OS'  ; FSLabel = 'SYSTEM'; AllocationUnitSize = 4KB   }
      @{ Id = '2'; Letter = 'F'; Type = 'Data'; FSLabel = 'DATA'  ; AllocationUnitSize = 64KB  }
      @{ Id = '3'; Letter = 'G'; Type = 'Logs'; FSLabel = 'LOGS'  ; AllocationUnitSize = 64KB  }
    )
    # Certificate distribution (mirrors CfgAppSps ADC block). Paths are derived from
    # NonNodeData.SourcePath + CerFileName / PfxFileName by CfgAppSql.ps1, and each
    # entry's PFX password comes from the matching Secrets.psd1 serviceAccount (Name).
    # Only consumed when NonNodeData.SQL.ForceEncryption is enabled below.
    ADC         = @{
      certificates = @(
        @{
          Name         = 'SQLServerCert'
          FriendlyName = 'SQLCertSSL'
          CerFileName  = 'SQLServer.cer'
          PfxFileName  = 'SQLServer.pfx'
        }
      )
    }
    # Optional installation-media path overrides for customers whose file hierarchy
    # differs from the kit's defaults. When omitted the script falls back to:
    #   SourcePath      = <NonNodeData.SourcePath>\SQL
    #   DestinationPath = <Drives.Data>\SoftwarePackages\SQL
    # SQL setup.exe is expected at the root of DestinationPath (no BIN/LP/CU subfolders).
    SQL         = @{
      # SourcePath      = '\\PULL\Softwarepackages\SQL'
      # DestinationPath = 'F:\SoftwarePackages\SQL'
      # TLS encryption of SQL Server connections (secure-by-default in this kit). When
      # $true, CfgAppSql imports CertificateName (an ADC.certificates entry, default
      # 'SQLServerCert') into LocalMachine\My, binds it to the instance and enables
      # ForceEncryption. The SharePoint nodes must trust the certificate's issuing CA
      # (its root in their LocalMachine\Root) or connections fail with a certificate-chain
      # error — CfgAppSps imports the SQL certificate there under the same flag. Set to
      # $false only if you deliberately want unencrypted SQL connections.
      ForceEncryption = $true
      CertificateName = 'SQLServerCert'
    }
  }
}
