@{
  serviceAccounts = @(
    # DO NOT USE THESE ACCOUNTS IN PRODUCTION ENVIRONMENTS. THESE ARE SAMPLE ACCOUNTS FOR DEMO PURPOSES ONLY.
    # DO NO RENAME Name value as it is used as reference in the DSC configuration scripts.
    @{
      Name        = 'ADSETUP'
      DisplayName = 'Active Directory Setup'
      Description = 'Active Directory Setup Account'
      Username    = 'CONTOSO\svcadsetup'
      IsAdAccount = $False
      Password    = '******************'
    }
    @{
      # Dedicated DSRM (Directory Services Restore Mode) password consumed by
      # ADDomain.SafemodeAdministratorPassword. Only the password is read by
      # the resource; the Username value is required by New-Variable but is
      # otherwise ignored. KEEP THIS DISTINCT FROM ADSETUP.
      Name        = 'ADSAFEMODE'
      DisplayName = 'AD DSRM'
      Description = 'Directory Services Restore Mode (DSRM) password'
      Username    = 'DSRM'
      IsAdAccount = $False
      Password    = '******************'
    }
    @{
      Name        = 'SQLSERVER'
      DisplayName = 'SQL Server'
      Description = 'SQL Server Service Account'
      Username    = 'CONTOSO\svcsqlserver'
      Password    = '******************'
    }
    @{
      Name        = 'PULLSETUP'
      DisplayName = 'PULL SETUP'
      Description = 'Pull setup ServiceAccount'
      Username    = 'CONTOSO\svcpullsetup'
      Password    = '******************'
    }
    @{
      Name        = 'IISPULLAPP'
      DisplayName = 'PULL IISAPP'
      Description = 'Pull IIS App Service Account'
      Username    = 'CONTOSO\svcpulliisapp'
      Password    = '******************'
    }
    @{
      Name        = 'SETUP'
      DisplayName = 'SharePoint SETUP'
      Description = 'SharePoint Setup Account'
      Username    = 'CONTOSO\svcspssetup'
      Password    = '******************'
    }
    @{
      Name        = 'FARM'
      DisplayName = 'SharePoint FARM'
      Description = 'SharePoint Farm Account'
      Username    = 'CONTOSO\svcspsfarm'
      Password    = '******************'
    }
    @{
      Name        = 'IISAPP'
      DisplayName = 'SharePoint IISAPP'
      Description = 'SharePoint Application Pool Account'
      Username    = 'CONTOSO\svcspsiisapp'
      Password    = '******************'
    }
    @{
      Name        = 'SEARCH'
      DisplayName = 'SharePoint SEARCH'
      Description = 'SharePoint Search Service Account'
      Username    = 'CONTOSO\svcspsearch'
      Password    = '******************'
    }
    @{
      Name        = 'CONTENT'
      DisplayName = 'SharePoint CONTENT'
      Description = 'SharePoint Default Content Access Service Account'
      Username    = 'CONTOSO\svcspcontent'
      Password    = '******************'
    }
    @{
      Name        = 'SUPERUSER'
      DisplayName = 'SharePoint SUPERUSER'
      Description = 'SharePoint Super User Account'
      Username    = 'CONTOSO\svcspssuperuser'
      Password    = '******************'
    }
    @{
      Name        = 'SUPEREADER'
      DisplayName = 'SharePoint SUPEREADER'
      Description = 'SharePoint Super Reader Account'
      Username    = 'CONTOSO\svcspssupereader'
      Password    = '******************'
    }
    @{
      Name        = 'Passphrase'
      DisplayName = 'SharePoint Passphrase'
      Description = 'SharePoint Passphrase Account'
      Username    = 'Passphrase'
      IsAdAccount = $False
      Password    = '******************'
    }
    @{
      Name        = 'DscPullCert'
      DisplayName = 'Dsc Pull PFXCred'
      Description = 'Dsc Pull PFXCred Account'
      Username    = 'DscPullCert'
      IsAdAccount = $False
      Password    = '******************'
    }
    @{
      Name        = 'SharePointCert'
      DisplayName = 'SharePoint PFXCred'
      Description = 'SharePoint PFXCred Account'
      Username    = 'SharePointCert'
      IsAdAccount = $False
      Password    = '******************'
    }
    @{
      Name        = 'OfficeOnlineCert'
      DisplayName = 'Office Online PFXCred'
      Description = 'Office Online PFXCred Account'
      Username    = 'OfficeOnlineCert'
      IsAdAccount = $False
      Password    = '******************'
    }
    @{
      Name        = 'SQLServerCert'
      DisplayName = 'SQL Server PFXCred'
      Description = 'SQL Server PFXCred Account'
      Username    = 'SQLServerCert'
      IsAdAccount = $False
      Password    = '******************'
    }
  )
  users           = @(
    @{
      Name        = 'Ava Martin'
      GivenName   = 'Ava'
      SurName     = 'Martin'
      DisplayName = 'Ava Martin'
      Description = 'Ava Martin User'
      Username    = 'CONTOSO\avamartin'
      Password    = '******************'
    }
    @{
      Name        = 'Liam Bernard'
      GivenName   = 'Liam'
      SurName     = 'Bernard'
      DisplayName = 'Liam Bernard'
      Description = 'Liam Bernard User'
      Username    = 'CONTOSO\liambernard'
      Password    = '******************'
    }
    @{
      Name        = 'Emma Dubois'
      GivenName   = 'Emma'
      SurName     = 'Dubois'
      DisplayName = 'Emma Dubois'
      Description = 'Emma Dubois User'
      Username    = 'CONTOSO\emmadubois'
      Password    = '******************'
    }
    @{
      Name        = 'Noah Thomas'
      GivenName   = 'Noah'
      SurName     = 'Thomas'
      DisplayName = 'Noah Thomas'
      Description = 'Noah Thomas User'
      Username    = 'CONTOSO\noahthomas'
      Password    = '******************'
    }
    @{
      Name        = 'Chloe Robert'
      GivenName   = 'Chloe'
      SurName     = 'Robert'
      DisplayName = 'Chloe Robert'
      Description = 'Chloe Robert User'
      Username    = 'CONTOSO\chloerobert'
      Password    = '******************'
    }
    @{
      Name        = 'Lucas Petit'
      GivenName   = 'Lucas'
      SurName     = 'Petit'
      DisplayName = 'Lucas Petit'
      Description = 'Lucas Petit User'
      Username    = 'CONTOSO\lucaspetit'
      Password    = '******************'
    }
    @{
      Name        = 'Mia Laurent'
      GivenName   = 'Mia'
      SurName     = 'Laurent'
      DisplayName = 'Mia Laurent'
      Description = 'Mia Laurent User'
      Username    = 'CONTOSO\mialaurent'
      Password    = '******************'
    }
    @{
      Name        = 'Ethan Moreau'
      GivenName   = 'Ethan'
      SurName     = 'Moreau'
      DisplayName = 'Ethan Moreau'
      Description = 'Ethan Moreau User'
      Username    = 'CONTOSO\ethanmoreau'
      Password    = '******************'
    }
    @{
      Name        = 'Zoe Garcia'
      GivenName   = 'Zoe'
      SurName     = 'Garcia'
      DisplayName = 'Zoe Garcia'
      Description = 'Zoe Garcia User'
      Username    = 'CONTOSO\zoegarcia'
      Password    = '******************'
    }
    @{
      Name        = 'Hugo Lefevre'
      GivenName   = 'Hugo'
      SurName     = 'Lefevre'
      DisplayName = 'Hugo Lefevre'
      Description = 'Hugo Lefevre User'
      Username    = 'CONTOSO\hugolefevre'
      Password    = '******************'
    }
    @{
      Name        = 'Sarah Nguyen'
      GivenName   = 'Sarah'
      SurName     = 'Nguyen'
      DisplayName = 'Sarah Nguyen'
      Description = 'Sarah Nguyen User'
      Username    = 'CONTOSO\sarahnguyen'
      Password    = '******************'
    }
    @{
      Name        = 'Arthur Fournier'
      GivenName   = 'Arthur'
      SurName     = 'Fournier'
      DisplayName = 'Arthur Fournier'
      Description = 'Arthur Fournier User'
      Username    = 'CONTOSO\arthurfournier'
      Password    = '******************'
    }
    @{
      Name        = 'Camille Girard'
      GivenName   = 'Camille'
      SurName     = 'Girard'
      DisplayName = 'Camille Girard'
      Description = 'Camille Girard User'
      Username    = 'CONTOSO\camillegirard'
      Password    = '******************'
    }
    @{
      Name        = 'Jules Rousseau'
      GivenName   = 'Jules'
      SurName     = 'Rousseau'
      DisplayName = 'Jules Rousseau'
      Description = 'Jules Rousseau User'
      Username    = 'CONTOSO\julesrousseau'
      Password    = '******************'
    }
    @{
      Name        = 'Lea Fontaine'
      GivenName   = 'Lea'
      SurName     = 'Fontaine'
      DisplayName = 'Lea Fontaine'
      Description = 'Lea Fontaine User'
      Username    = 'CONTOSO\leafontaine'
      Password    = '******************'
    }
    @{
      Name        = 'Adam Lambert'
      GivenName   = 'Adam'
      SurName     = 'Lambert'
      DisplayName = 'Adam Lambert'
      Description = 'Adam Lambert User'
      Username    = 'CONTOSO\adamlambert'
      Password    = '******************'
    }
    @{
      Name        = 'Ines Lopez'
      GivenName   = 'Ines'
      SurName     = 'Lopez'
      DisplayName = 'Ines Lopez'
      Description = 'Ines Lopez User'
      Username    = 'CONTOSO\ineslopez'
      Password    = '******************'
    }
    @{
      Name        = 'Nathan Simon'
      GivenName   = 'Nathan'
      SurName     = 'Simon'
      DisplayName = 'Nathan Simon'
      Description = 'Nathan Simon User'
      Username    = 'CONTOSO\nathansimon'
      Password    = '******************'
    }
    @{
      Name        = 'Manon Andre'
      GivenName   = 'Manon'
      SurName     = 'Andre'
      DisplayName = 'Manon Andre'
      Description = 'Manon Andre User'
      Username    = 'CONTOSO\manonandre'
      Password    = '******************'
    }
    @{
      Name        = 'Tom Henry'
      GivenName   = 'Tom'
      SurName     = 'Henry'
      DisplayName = 'Tom Henry'
      Description = 'Tom Henry User'
      Username    = 'CONTOSO\tomhenry'
      Password    = '******************'
    }
    @{
      Name        = 'Louise Rey'
      GivenName   = 'Louise'
      SurName     = 'Rey'
      DisplayName = 'Louise Rey'
      Description = 'Louise Rey User'
      Username    = 'CONTOSO\louiserey'
      Password    = '******************'
    }
    @{
      Name        = 'Maxime Perrot'
      GivenName   = 'Maxime'
      SurName     = 'Perrot'
      DisplayName = 'Maxime Perrot'
      Description = 'Maxime Perrot User'
      Username    = 'CONTOSO\maximeperrot'
      Password    = '******************'
    }
    @{
      Name        = 'Olivia Scott'
      GivenName   = 'Olivia'
      SurName     = 'Scott'
      DisplayName = 'Olivia Scott'
      Description = 'Olivia Scott User'
      Username    = 'CONTOSO\oliviascott'
      Password    = '******************'
    }
    @{
      Name        = 'Paul Marchand'
      GivenName   = 'Paul'
      SurName     = 'Marchand'
      DisplayName = 'Paul Marchand'
      Description = 'Paul Marchand User'
      Username    = 'CONTOSO\paulmarchand'
      Password    = '******************'
    }
    @{
      Name        = 'Nina Caron'
      GivenName   = 'Nina'
      SurName     = 'Caron'
      DisplayName = 'Nina Caron'
      Description = 'Nina Caron User'
      Username    = 'CONTOSO\ninacaron'
      Password    = '******************'
    }
    @{
      Name        = 'Theo Vidal'
      GivenName   = 'Theo'
      SurName     = 'Vidal'
      DisplayName = 'Theo Vidal'
      Description = 'Theo Vidal User'
      Username    = 'CONTOSO\theovidal'
      Password    = '******************'
    }
    @{
      Name        = 'Julie Noel'
      GivenName   = 'Julie'
      SurName     = 'Noel'
      DisplayName = 'Julie Noel'
      Description = 'Julie Noel User'
      Username    = 'CONTOSO\julienoel'
      Password    = '******************'
    }
    @{
      Name        = 'Kevin Baker'
      GivenName   = 'Kevin'
      SurName     = 'Baker'
      DisplayName = 'Kevin Baker'
      Description = 'Kevin Baker User'
      Username    = 'CONTOSO\kevinbaker'
      Password    = '******************'
    }
    @{
      Name        = 'Sofia Meunier'
      GivenName   = 'Sofia'
      SurName     = 'Meunier'
      DisplayName = 'Sofia Meunier'
      Description = 'Sofia Meunier User'
      Username    = 'CONTOSO\sofameunier'
      Password    = '******************'
    }
    @{
      Name        = 'Gabriel Leroy'
      GivenName   = 'Gabriel'
      SurName     = 'Leroy'
      DisplayName = 'Gabriel Leroy'
      Description = 'Gabriel Leroy User'
      Username    = 'CONTOSO\gabrielleroy'
      Password    = '******************'
    }
    @{
      Name        = 'Clara Bonnet'
      GivenName   = 'Clara'
      SurName     = 'Bonnet'
      DisplayName = 'Clara Bonnet'
      Description = 'Clara Bonnet User'
      Username    = 'CONTOSO\clarabonnet'
      Password    = '******************'
    }
    @{
      Name        = 'Yanis Colin'
      GivenName   = 'Yanis'
      SurName     = 'Colin'
      DisplayName = 'Yanis Colin'
      Description = 'Yanis Colin User'
      Username    = 'CONTOSO\yaniscolin'
      Password    = '******************'
    }
    @{
      Name        = 'Eva Chevalier'
      GivenName   = 'Eva'
      SurName     = 'Chevalier'
      DisplayName = 'Eva Chevalier'
      Description = 'Eva Chevalier User'
      Username    = 'CONTOSO\evachevalier'
      Password    = '******************'
    }
    @{
      Name        = 'Benjamin Rolland'
      GivenName   = 'Benjamin'
      SurName     = 'Rolland'
      DisplayName = 'Benjamin Rolland'
      Description = 'Benjamin Rolland User'
      Username    = 'CONTOSO\benjaminrolland'
      Password    = '******************'
    }
    @{
      Name        = 'Anais Faure'
      GivenName   = 'Anais'
      SurName     = 'Faure'
      DisplayName = 'Anais Faure'
      Description = 'Anais Faure User'
      Username    = 'CONTOSO\anaisfaure'
      Password    = '******************'
    }
    @{
      Name        = 'Rayan Gauthier'
      GivenName   = 'Rayan'
      SurName     = 'Gauthier'
      DisplayName = 'Rayan Gauthier'
      Description = 'Rayan Gauthier User'
      Username    = 'CONTOSO\rayangauthier'
      Password    = '******************'
    }
    @{
      Name        = 'Elena Rossi'
      GivenName   = 'Elena'
      SurName     = 'Rossi'
      DisplayName = 'Elena Rossi'
      Description = 'Elena Rossi User'
      Username    = 'CONTOSO\elenarossi'
      Password    = '******************'
    }
    @{
      Name        = 'Oscar Perez'
      GivenName   = 'Oscar'
      SurName     = 'Perez'
      DisplayName = 'Oscar Perez'
      Description = 'Oscar Perez User'
      Username    = 'CONTOSO\oscarperez'
      Password    = '******************'
    }
    @{
      Name        = 'Iris Legrand'
      GivenName   = 'Iris'
      SurName     = 'Legrand'
      DisplayName = 'Iris Legrand'
      Description = 'Iris Legrand User'
      Username    = 'CONTOSO\irislegrand'
      Password    = '******************'
    }
    @{
      Name        = 'Matteo Bianchi'
      GivenName   = 'Matteo'
      SurName     = 'Bianchi'
      DisplayName = 'Matteo Bianchi'
      Description = 'Matteo Bianchi User'
      Username    = 'CONTOSO\matteobianchi'
      Password    = '******************'
    }
    @{
      Name        = 'Lina Ait'
      GivenName   = 'Lina'
      SurName     = 'Ait'
      DisplayName = 'Lina Ait'
      Description = 'Lina Ait User'
      Username    = 'CONTOSO\linaait'
      Password    = '******************'
    }
    @{
      Name        = 'Quentin Blanc'
      GivenName   = 'Quentin'
      SurName     = 'Blanc'
      DisplayName = 'Quentin Blanc'
      Description = 'Quentin Blanc User'
      Username    = 'CONTOSO\quentinblanc'
      Password    = '******************'
    }
    @{
      Name        = 'Alice Keller'
      GivenName   = 'Alice'
      SurName     = 'Keller'
      DisplayName = 'Alice Keller'
      Description = 'Alice Keller User'
      Username    = 'CONTOSO\alicekeller'
      Password    = '******************'
    }
    @{
      Name        = 'Louis Meyer'
      GivenName   = 'Louis'
      SurName     = 'Meyer'
      DisplayName = 'Louis Meyer'
      Description = 'Louis Meyer User'
      Username    = 'CONTOSO\louismeyer'
      Password    = '******************'
    }
    @{
      Name        = 'Sophie Schmidt'
      GivenName   = 'Sophie'
      SurName     = 'Schmidt'
      DisplayName = 'Sophie Schmidt'
      Description = 'Sophie Schmidt User'
      Username    = 'CONTOSO\sophieschmidt'
      Password    = '******************'
    }
    @{
      Name        = 'Hugo Weber'
      GivenName   = 'Hugo'
      SurName     = 'Weber'
      DisplayName = 'Hugo Weber'
      Description = 'Hugo Weber User'
      Username    = 'CONTOSO\hugoweber'
      Password    = '******************'
    }
    @{
      Name        = 'Emma Fischer'
      GivenName   = 'Emma'
      SurName     = 'Fischer'
      DisplayName = 'Emma Fischer'
      Description = 'Emma Fischer User'
      Username    = 'CONTOSO\emmafischer'
      Password    = '******************'
    }
    @{
      Name        = 'Noah Wagner'
      GivenName   = 'Noah'
      SurName     = 'Wagner'
      DisplayName = 'Noah Wagner'
      Description = 'Noah Wagner User'
      Username    = 'CONTOSO\noahwagner'
      Password    = '******************'
    }
    @{
      Name        = 'Chloe Braun'
      GivenName   = 'Chloe'
      SurName     = 'Braun'
      DisplayName = 'Chloe Braun'
      Description = 'Chloe Braun User'
      Username    = 'CONTOSO\chloebraun'
      Password    = '******************'
    }
    @{
      Name        = 'Lucas Vogel'
      GivenName   = 'Lucas'
      SurName     = 'Vogel'
      DisplayName = 'Lucas Vogel'
      Description = 'Lucas Vogel User'
      Username    = 'CONTOSO\lucasvogel'
      Password    = '******************'
    }
    @{
      Name        = 'Mia Hoffmann'
      GivenName   = 'Mia'
      SurName     = 'Hoffmann'
      DisplayName = 'Mia Hoffmann'
      Description = 'Mia Hoffmann User'
      Username    = 'CONTOSO\miahoffmann'
      Password    = '******************'
    }
    @{
      Name        = 'Ethan Konig'
      GivenName   = 'Ethan'
      SurName     = 'Konig'
      DisplayName = 'Ethan Konig'
      Description = 'Ethan Konig User'
      Username    = 'CONTOSO\ethankonig'
      Password    = '******************'
    }
    @{
      Name        = 'Zoe Roth'
      GivenName   = 'Zoe'
      SurName     = 'Roth'
      DisplayName = 'Zoe Roth'
      Description = 'Zoe Roth User'
      Username    = 'CONTOSO\zoeroth'
      Password    = '******************'
    }
    @{
      Name        = 'Theo Jung'
      GivenName   = 'Theo'
      SurName     = 'Jung'
      DisplayName = 'Theo Jung'
      Description = 'Theo Jung User'
      Username    = 'CONTOSO\theojung'
      Password    = '******************'
    }
    @{
      Name        = 'Julie Hartmann'
      GivenName   = 'Julie'
      SurName     = 'Hartmann'
      DisplayName = 'Julie Hartmann'
      Description = 'Julie Hartmann User'
      Username    = 'CONTOSO\juliehartmann'
      Password    = '******************'
    }
    @{
      Name        = 'Kevin Frank'
      GivenName   = 'Kevin'
      SurName     = 'Frank'
      DisplayName = 'Kevin Frank'
      Description = 'Kevin Frank User'
      Username    = 'CONTOSO\kevinfrank'
      Password    = '******************'
    }
    @{
      Name        = 'Sara Maier'
      GivenName   = 'Sara'
      SurName     = 'Maier'
      DisplayName = 'Sara Maier'
      Description = 'Sara Maier User'
      Username    = 'CONTOSO\saramaier'
      Password    = '******************'
    }
    @{
      Name        = 'Adam Becker'
      GivenName   = 'Adam'
      SurName     = 'Becker'
      DisplayName = 'Adam Becker'
      Description = 'Adam Becker User'
      Username    = 'CONTOSO\adambecker'
      Password    = '******************'
    }
    @{
      Name        = 'Ines Schwarz'
      GivenName   = 'Ines'
      SurName     = 'Schwarz'
      DisplayName = 'Ines Schwarz'
      Description = 'Ines Schwarz User'
      Username    = 'CONTOSO\inesschwarz'
      Password    = '******************'
    }
    @{
      Name        = 'Nathan Bauer'
      GivenName   = 'Nathan'
      SurName     = 'Bauer'
      DisplayName = 'Nathan Bauer'
      Description = 'Nathan Bauer User'
      Username    = 'CONTOSO\nathanbauer'
      Password    = '******************'
    }
    @{
      Name        = 'Manon Zimmer'
      GivenName   = 'Manon'
      SurName     = 'Zimmer'
      DisplayName = 'Manon Zimmer'
      Description = 'Manon Zimmer User'
      Username    = 'CONTOSO\manonzimmer'
      Password    = '******************'
    }
    @{
      Name        = 'Tom Walter'
      GivenName   = 'Tom'
      SurName     = 'Walter'
      DisplayName = 'Tom Walter'
      Description = 'Tom Walter User'
      Username    = 'CONTOSO\tomwalter'
      Password    = '******************'
    }
    @{
      Name        = 'Louise Kruger'
      GivenName   = 'Louise'
      SurName     = 'Kruger'
      DisplayName = 'Louise Kruger'
      Description = 'Louise Kruger User'
      Username    = 'CONTOSO\louisekruger'
      Password    = '******************'
    }
    @{
      Name        = 'Paul Neumann'
      GivenName   = 'Paul'
      SurName     = 'Neumann'
      DisplayName = 'Paul Neumann'
      Description = 'Paul Neumann User'
      Username    = 'CONTOSO\paulneumann'
      Password    = '******************'
    }

    # ---- 61 to 100 ----
    @{
      Name        = 'Clara Muller'
      GivenName   = 'Clara'
      SurName     = 'Muller'
      DisplayName = 'Clara Muller'
      Description = 'Clara Muller User'
      Username    = 'CONTOSO\claramuller'
      Password    = '******************'
    }
    @{
      Name        = 'Leo Lambert'
      GivenName   = 'Leo'
      SurName     = 'Lambert'
      DisplayName = 'Leo Lambert'
      Description = 'Leo Lambert User'
      Username    = 'CONTOSO\leolambert'
      Password    = '******************'
    }
    @{
      Name        = 'Maya Dupont'
      GivenName   = 'Maya'
      SurName     = 'Dupont'
      DisplayName = 'Maya Dupont'
      Description = 'Maya Dupont User'
      Username    = 'CONTOSO\mayadupont'
      Password    = '******************'
    }
    @{
      Name        = 'Hana Ito'
      GivenName   = 'Hana'
      SurName     = 'Ito'
      DisplayName = 'Hana Ito'
      Description = 'Hana Ito User'
      Username    = 'CONTOSO\hanaito'
      Password    = '******************'
    }
    @{
      Name        = 'Yusuf Demir'
      GivenName   = 'Yusuf'
      SurName     = 'Demir'
      DisplayName = 'Yusuf Demir'
      Description = 'Yusuf Demir User'
      Username    = 'CONTOSO\yusufdemir'
      Password    = '******************'
    }
    @{
      Name        = 'Nora Benali'
      GivenName   = 'Nora'
      SurName     = 'Benali'
      DisplayName = 'Nora Benali'
      Description = 'Nora Benali User'
      Username    = 'CONTOSO\norabenali'
      Password    = '******************'
    }
    @{
      Name        = 'Adam Kowalski'
      GivenName   = 'Adam'
      SurName     = 'Kowalski'
      DisplayName = 'Adam Kowalski'
      Description = 'Adam Kowalski User'
      Username    = 'CONTOSO\adamkowalski'
      Password    = '******************'
    }
    @{
      Name        = 'Lena Rossi'
      GivenName   = 'Lena'
      SurName     = 'Rossi'
      DisplayName = 'Lena Rossi'
      Description = 'Lena Rossi User'
      Username    = 'CONTOSO\lenarossi'
      Password    = '******************'
    }
    @{
      Name        = 'Owen Carter'
      GivenName   = 'Owen'
      SurName     = 'Carter'
      DisplayName = 'Owen Carter'
      Description = 'Owen Carter User'
      Username    = 'CONTOSO\owencarter'
      Password    = '******************'
    }
    @{
      Name        = 'Jade Morel'
      GivenName   = 'Jade'
      SurName     = 'Morel'
      DisplayName = 'Jade Morel'
      Description = 'Jade Morel User'
      Username    = 'CONTOSO\jademorel'
      Password    = '******************'
    }
    @{
      Name        = 'Ilyes Haddad'
      GivenName   = 'Ilyes'
      SurName     = 'Haddad'
      DisplayName = 'Ilyes Haddad'
      Description = 'Ilyes Haddad User'
      Username    = 'CONTOSO\ilyeshaddad'
      Password    = '******************'
    }
    @{
      Name        = 'Sana Ali'
      GivenName   = 'Sana'
      SurName     = 'Ali'
      DisplayName = 'Sana Ali'
      Description = 'Sana Ali User'
      Username    = 'CONTOSO\sanaali'
      Password    = '******************'
    }
    @{
      Name        = 'Romain Carpentier'
      GivenName   = 'Romain'
      SurName     = 'Carpentier'
      DisplayName = 'Romain Carpentier'
      Description = 'Romain Carpentier User'
      Username    = 'CONTOSO\romaincarpentier'
      Password    = '******************'
    }
    @{
      Name        = 'Lucie Perrin'
      GivenName   = 'Lucie'
      SurName     = 'Perrin'
      DisplayName = 'Lucie Perrin'
      Description = 'Lucie Perrin User'
      Username    = 'CONTOSO\lucieperrin'
      Password    = '******************'
    }
    @{
      Name        = 'Bastien Noel'
      GivenName   = 'Bastien'
      SurName     = 'Noel'
      DisplayName = 'Bastien Noel'
      Description = 'Bastien Noel User'
      Username    = 'CONTOSO\bastiennoel'
      Password    = '******************'
    }
    @{
      Name        = 'Helene Marchal'
      GivenName   = 'Helene'
      SurName     = 'Marchal'
      DisplayName = 'Helene Marchal'
      Description = 'Helene Marchal User'
      Username    = 'CONTOSO\helenemarchal'
      Password    = '******************'
    }
    @{
      Name        = 'Yann Leclerc'
      GivenName   = 'Yann'
      SurName     = 'Leclerc'
      DisplayName = 'Yann Leclerc'
      Description = 'Yann Leclerc User'
      Username    = 'CONTOSO\yannleclerc'
      Password    = '******************'
    }
    @{
      Name        = 'Mila Giraud'
      GivenName   = 'Mila'
      SurName     = 'Giraud'
      DisplayName = 'Mila Giraud'
      Description = 'Mila Giraud User'
      Username    = 'CONTOSO\milagiraud'
      Password    = '******************'
    }
    @{
      Name        = 'Nils Perrier'
      GivenName   = 'Nils'
      SurName     = 'Perrier'
      DisplayName = 'Nils Perrier'
      Description = 'Nils Perrier User'
      Username    = 'CONTOSO\nilsperrier'
      Password    = '******************'
    }
    @{
      Name        = 'Selma Diaz'
      GivenName   = 'Selma'
      SurName     = 'Diaz'
      DisplayName = 'Selma Diaz'
      Description = 'Selma Diaz User'
      Username    = 'CONTOSO\selmadiaz'
      Password    = '******************'
    }
    @{
      Name        = 'Dorian Millet'
      GivenName   = 'Dorian'
      SurName     = 'Millet'
      DisplayName = 'Dorian Millet'
      Description = 'Dorian Millet User'
      Username    = 'CONTOSO\dorianmillet'
      Password    = '******************'
    }
    @{
      Name        = 'Elsa Faure'
      GivenName   = 'Elsa'
      SurName     = 'Faure'
      DisplayName = 'Elsa Faure'
      Description = 'Elsa Faure User'
      Username    = 'CONTOSO\elsafaure'
      Password    = '******************'
    }
    @{
      Name        = 'Khalil Hamdi'
      GivenName   = 'Khalil'
      SurName     = 'Hamdi'
      DisplayName = 'Khalil Hamdi'
      Description = 'Khalil Hamdi User'
      Username    = 'CONTOSO\khalilhamdi'
      Password    = '******************'
    }
    @{
      Name        = 'Farah Saidi'
      GivenName   = 'Farah'
      SurName     = 'Saidi'
      DisplayName = 'Farah Saidi'
      Description = 'Farah Saidi User'
      Username    = 'CONTOSO\farahsaidi'
      Password    = '******************'
    }
    @{
      Name        = 'Amir Cohen'
      GivenName   = 'Amir'
      SurName     = 'Cohen'
      DisplayName = 'Amir Cohen'
      Description = 'Amir Cohen User'
      Username    = 'CONTOSO\amircohen'
      Password    = '******************'
    }
    @{
      Name        = 'Salome Aubert'
      GivenName   = 'Salome'
      SurName     = 'Aubert'
      DisplayName = 'Salome Aubert'
      Description = 'Salome Aubert User'
      Username    = 'CONTOSO\salomeaubert'
      Password    = '******************'
    }
    @{
      Name        = 'Raphael Dumas'
      GivenName   = 'Raphael'
      SurName     = 'Dumas'
      DisplayName = 'Raphael Dumas'
      Description = 'Raphael Dumas User'
      Username    = 'CONTOSO\raphaeldumas'
      Password    = '******************'
    }
    @{
      Name        = 'Nadia Benomar'
      GivenName   = 'Nadia'
      SurName     = 'Benomar'
      DisplayName = 'Nadia Benomar'
      Description = 'Nadia Benomar User'
      Username    = 'CONTOSO\nadiabenomar'
      Password    = '******************'
    }
    @{
      Name        = 'Victor Renaud'
      GivenName   = 'Victor'
      SurName     = 'Renaud'
      DisplayName = 'Victor Renaud'
      Description = 'Victor Renaud User'
      Username    = 'CONTOSO\victorrenaud'
      Password    = '******************'
    }
    @{
      Name        = 'Amelie Colin'
      GivenName   = 'Amelie'
      SurName     = 'Colin'
      DisplayName = 'Amelie Colin'
      Description = 'Amelie Colin User'
      Username    = 'CONTOSO\ameliecolin'
      Password    = '******************'
    }
    @{
      Name        = 'Julian Evans'
      GivenName   = 'Julian'
      SurName     = 'Evans'
      DisplayName = 'Julian Evans'
      Description = 'Julian Evans User'
      Username    = 'CONTOSO\julianevans'
      Password    = '******************'
    }
    @{
      Name        = 'Louna Vidal'
      GivenName   = 'Louna'
      SurName     = 'Vidal'
      DisplayName = 'Louna Vidal'
      Description = 'Louna Vidal User'
      Username    = 'CONTOSO\lounavidal'
      Password    = '******************'
    }
    @{
      Name        = 'Sami Rahmani'
      GivenName   = 'Sami'
      SurName     = 'Rahmani'
      DisplayName = 'Sami Rahmani'
      Description = 'Sami Rahmani User'
      Username    = 'CONTOSO\samirahmani'
      Password    = '******************'
    }
    @{
      Name        = 'Celia Brun'
      GivenName   = 'Celia'
      SurName     = 'Brun'
      DisplayName = 'Celia Brun'
      Description = 'Celia Brun User'
      Username    = 'CONTOSO\celiabrun'
      Password    = '******************'
    }
    @{
      Name        = 'Enzo Mercier'
      GivenName   = 'Enzo'
      SurName     = 'Mercier'
      DisplayName = 'Enzo Mercier'
      Description = 'Enzo Mercier User'
      Username    = 'CONTOSO\enzomercier'
      Password    = '******************'
    }
    @{
      Name        = 'Meryem Azzouzi'
      GivenName   = 'Meryem'
      SurName     = 'Azzouzi'
      DisplayName = 'Meryem Azzouzi'
      Description = 'Meryem Azzouzi User'
      Username    = 'CONTOSO\meryemazzouzi'
      Password    = '******************'
    }
    @{
      Name        = 'Ibrahim Kaya'
      GivenName   = 'Ibrahim'
      SurName     = 'Kaya'
      DisplayName = 'Ibrahim Kaya'
      Description = 'Ibrahim Kaya User'
      Username    = 'CONTOSO\ibrahimkaya'
      Password    = '******************'
    }
    @{
      Name        = 'Leonie Petit'
      GivenName   = 'Leonie'
      SurName     = 'Petit'
      DisplayName = 'Leonie Petit'
      Description = 'Leonie Petit User'
      Username    = 'CONTOSO\leoniepetit'
      Password    = '******************'
    }
    @{
      Name        = 'Tao Nguyen'
      GivenName   = 'Tao'
      SurName     = 'Nguyen'
      DisplayName = 'Tao Nguyen'
      Description = 'Tao Nguyen User'
      Username    = 'CONTOSO\taonguyen'
      Password    = '******************'
    }
    @{
      Name        = 'Aya Benjelloun'
      GivenName   = 'Aya'
      SurName     = 'Benjelloun'
      DisplayName = 'Aya Benjelloun'
      Description = 'Aya Benjelloun User'
      Username    = 'CONTOSO\ayabenjelloun'
      Password    = '******************'
    }
    @{
      Name        = 'Giulia Romano'
      GivenName   = 'Giulia'
      SurName     = 'Romano'
      DisplayName = 'Giulia Romano'
      Description = 'Giulia Romano User'
      Username    = 'CONTOSO\giuliaromano'
      Password    = '******************'
    }
    @{
      Name        = 'Dylan Lambert'
      GivenName   = 'Dylan'
      SurName     = 'Lambert'
      DisplayName = 'Dylan Lambert'
      Description = 'Dylan Lambert User'
      Username    = 'CONTOSO\dynalambert'
      Password    = '******************'
    }
  )
}
