# Securing Credentials

> [!IMPORTANT]
> SPSConfigKit compiles real credentials — SharePoint service accounts, the farm
> passphrase, and every PFX password — into the MOF for each node. **Encrypting
> them with a DSC document-encryption certificate is mandatory.** Compiling in
> clear text (`PSDscAllowPlainTextPassword = $true` with no certificate) is not a
> supported configuration and must never leave an authoring host.

## Why this matters

A DSC v1/v2 MOF is a plain-text file until you encrypt it. Without a
document-encryption certificate, every `MSFT_Credential` block looks like this:

```
instance of MSFT_Credential as $c1ref
{
    Password = "SuperSecret123!";
    UserName = "CONTOSO\\svcspssetup";
};
```

That is a domain service-account password in clear text. Anyone who can read the
MOF — on the authoring host, on the pull server's `Configuration` folder, or on
the SMB share — has the farm's credentials. Encryption turns each password into a
CMS blob that only the target node (holder of the certificate's private key) can
decrypt:

```
instance of MSFT_Credential as $c1ref
{
    Password = "-----BEGIN CMS-----\nMIIBsQYJKoZI...\n-----END CMS-----";
    UserName = "CONTOSO\\svcspssetup";
};
```

and the configuration document is marked accordingly:

```
instance of OMI_ConfigurationDocument
{
    Version="2.0.0";
    ContentType="PasswordEncrypted";
    Name="CfgAppSps";
};
```

## How it works in SPSConfigKit

Encryption is driven by a single self-signed **Document Encryption** certificate
(EKU `1.3.6.1.4.1.311.80.1`). The public `.cer` encrypts credentials at
compile time; the private `.pfx`, imported on each node, decrypts them at apply
time. The kit wires this up for you.

### 1. Generate the certificate (once, on the authoring / cert host)

```powershell
$pfxPwd = Read-Host 'PFX password' -AsSecureString
.\scripts\init\Initialize-DscEncryption.ps1 -PfxPassword $pfxPwd
```

`Initialize-DscEncryption.ps1`:

- creates (or reuses) a `CN=DSC Encryption` certificate valid for 10 years;
- exports the public `DscEncryption.cer` **and** the password-protected
  `DscEncryption.pfx` to the share (default `\\PDC1\Softwarepackages`);
- **patches every `Cfg*.psd1`** in the repo: the wildcard `'*'` AllNodes block gets
  `PSDscAllowPlainTextPassword = $false`, `CertificateFile = '<share>\DscEncryption.cer'`,
  and `Thumbprint = '<thumbprint>'`. Because these live on the wildcard block,
  every named node inherits them — no per-node duplication. A `.bak` of each
  `.psd1` is created the first time it is patched.

> [!NOTE]
> After this step, `PSDscAllowPlainTextPassword` is `$false` farm-wide, so
> **compilation will fail until every target node has imported the `.pfx`**
> (next step). That failure is the safety net working as intended.

### 2. Import the private key on every node

`scripts/init/Initialize-DscNode.ps1` imports the `.pfx` automatically during node
bootstrap. To do it (or re-do it) by hand on a node:

```powershell
Import-PfxCertificate -FilePath '\\PDC1\Softwarepackages\DscEncryption.pfx' `
    -CertStoreLocation Cert:\LocalMachine\My `
    -Password (Read-Host 'PFX password' -AsSecureString)
```

Do this on **every** SharePoint and Office Online Server node. A node that is
missing the certificate cannot compile (authoring) or decrypt (apply).

### 3. Compile

```powershell
.\scripts\sps\CfgAppSps.ps1
```

The generated MOFs now hold CMS-encrypted credential blobs and the
`ContentType="PasswordEncrypted"` marker.

### 4. Verify (post-compile guard-rail)

```powershell
.\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\scripts\sps\MOF
```

The Pester guard-rail scans every `*.mof` and **fails with exit code 1** if any
credential is still clear text, or if a MOF carrying credentials is not marked
`PasswordEncrypted`. Wire it into CI or a release script right after compilation
so a mis-configured encryption certificate can never ship. A healthy run prints:

```
All N check(s) passed. Every credential in the MOF(s) is encrypted.
```

## Rotating the certificate

To replace the encryption certificate (expiry, compromise, policy):

```powershell
$pfxPwd = Read-Host 'PFX password' -AsSecureString
.\scripts\init\Initialize-DscEncryption.ps1 -PfxPassword $pfxPwd -Force
```

`-Force` removes the existing `CN=DSC Encryption` cert, creates a fresh one, and
refreshes the `CertificateFile` / `Thumbprint` values in every `Cfg*.psd1`.
Re-import the new `.pfx` on every node, then recompile and re-apply.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Compilation error: *"the certificate ... could not be found"* / thumbprint not found | The authoring host cannot read the `.cer` at `CertificateFile`, or the node hasn't imported the `.pfx` | Confirm the share path in the patched `.psd1`; import the `.pfx` on the node |
| Guard-rail reports clear-text credentials | `PSDscAllowPlainTextPassword` is still `$true`, or the `.psd1` wasn't patched | Run `Initialize-DscEncryption.ps1`; confirm the wildcard block shows `$false` + `CertificateFile` + `Thumbprint` |
| Apply fails to decrypt on the node | The node is missing the certificate **private key** | Re-import the `.pfx` (not just the `.cer`) into `Cert:\LocalMachine\My` |
| MOF has `ContentType="PasswordEncrypted"` but no credentials encrypted | Mixed state after a partial edit | Delete the MOF, recompile from a clean patched `.psd1` |

## See also

- [Getting Started](./Getting-Started) — where certificate generation sits in the
  overall workflow.
- [Usage](./Usage) — compiling and applying the MOFs.
- `scripts/init/Initialize-DscEncryption.ps1` — the generator (full comment-based help).
- `scripts/test/Invoke-MofEncryptionTest.ps1` — the post-compile guard-rail.
