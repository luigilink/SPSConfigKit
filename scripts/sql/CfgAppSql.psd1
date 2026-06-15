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
    SourcePath  = '\\PDC1\Softwarepackages'
    Drives      = @{
      Data = 'F:'
      Logs = 'G:'
      Temp = 'F:'
    }
    # Optional installation-media path overrides for customers whose file hierarchy
    # differs from the kit's defaults. When omitted the script falls back to:
    #   SourcePath      = <NonNodeData.SourcePath>\SQL
    #   DestinationPath = <Drives.Data>\SoftwarePackages\SQL
    # SQL setup.exe is expected at the root of DestinationPath (no BIN/LP/CU subfolders).
    SQL         = @{
      # SourcePath      = '\\PDC1\Softwarepackages\SQL'
      # DestinationPath = 'F:\SoftwarePackages\SQL'
    }
  }
}
