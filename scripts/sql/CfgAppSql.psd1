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
  }
}
