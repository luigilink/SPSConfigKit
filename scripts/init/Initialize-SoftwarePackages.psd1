
@{
  # Root folder of the local SoftwarePackages repository. Every entry below
  # uses a Path RELATIVE to this root. The companion SMB share (typically
  # \\PULL\SoftwarePackages) is expected to publish exactly this folder.
  Repository = 'F:\SoftwarePackages'

  SoftwarePackages = @(
    @{ 
      Name = 'SQLServer2022'
      Description = 'SQL Server 2022 Developer Edition'
      FileName = 'SQLServer2022-x64-ENU-Dev.iso'
      Url = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso'
      Extract = $true
      Path = 'SQL'
    },
    @{ 
      Name = 'KB5081477'
      FileName = 'SQLServer2022-KB5081477-x64.exe'
      Description = 'KB5081477 - Cumulative Update 25 for SQL Server 2022'
      Url = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2026/05/sqlserver2022-kb5081477-x64_d6b081c55fd0a4dc3b21c25225654faccc508abe.exe'
      Extract = $false
      Path = 'SQL\CU'
    },
    @{ 
      Name = 'SharePointServerSE'
      Description = 'SharePoint Server Subscription Edition'
      FileName = 'OfficeServer.iso'
      Url = 'https://download.microsoft.com/download/3/f/5/3f5f8a7e-462b-41ff-a5b2-04bdf5821ceb/OfficeServer.iso'
      Extract = $true
      Path = 'SPS\BIN'
    },
    @{ 
      Name = 'SharePointServerSE-LP_FR-fr'
      Description = 'Language Pack FR-fr for SharePoint Server Subscription Edition'
      FileName = 'ServerLanguagePack.iso'
      Url = 'https://download.microsoft.com/download/f/0/0/f0050ddc-6ece-495d-a8ee-90c2b44cc3ff/ServerLanguagePack.iso'
      Extract = $true
      Path = 'SPS\LP\FR-fr'
    },
    @{ 
      Name = 'Prerequisite_DOTNET48'
      Description = 'Microsoft .NET Framework 4.8'
      FileName = 'ndp48-x86-x64-allos-enu.exe'
      Url = 'https://download.visualstudio.microsoft.com/download/pr/2d6bb6b2-226a-4baa-bdec-798822606ff1/8494001c276a4b96804cde7829c04d7f/ndp48-x86-x64-allos-enu.exe'
      Extract = $false
      Path = 'SPS\BIN\prerequisiteinstallerfiles'
    },
    @{ 
      Name = 'Prerequisite_VC2015-2019'
      Description = 'Visual C++ Redistributable Package for Visual Studio 2015-2019'
      FileName = 'VC_redist.x64.exe'
      Url = 'https://download.visualstudio.microsoft.com/download/pr/d3cbdace-2bb8-4dc5-a326-2c1c0f1ad5ae/9B9DD72C27AB1DB081DE56BB7B73BEE9A00F60D14ED8E6FDE45DAB3E619B5F04/VC_redist.x64.exe'
      Extract = $false
      Path = 'SPS\BIN\prerequisiteinstallerfiles'
    },
    @{ 
      Name = 'KB5002863'
      Description = 'KB5002863 - Cumulative Update for SharePoint Server Subscription Edition'
      FileName = 'uber-subscription-kb5002863-fullfile-x64-glb.exe'
      Url = 'https://download.microsoft.com/download/926a1266-38a6-4721-9cb8-700df61ffaa2/uber-subscription-kb5002863-fullfile-x64-glb.exe'
      Extract = $false
      Path = 'SPS\CU'
    }
    @{ 
      Name = 'KB5002871'
      Description = 'KB5002871 - Security Update for Microsoft Office Online Server'
      FileName = 'wacserver2019-kb5002871-fullfile-x64-glb.exe'
      Url = 'https://download.microsoft.com/download/f7e624ca-8ab2-4acd-89bc-e8b53af001fa/wacserver2019-kb5002871-fullfile-x64-glb.exe'
      Extract = $false
      Path = 'OOS\CU'
    }
    
  )
}
