# SPSConfigKit - Release Notes

## [1.2.0] - 2026-07-01

### Added

- `scripts/test/MofEncryption.Tests.ps1` / `scripts/test/Invoke-MofEncryptionTest.ps1`
  - New post-compile Pester v5 guard-rail that scans compiled MOF files and fails
    (exit code 1) if any credential `Password` value is not a CMS-encrypted blob,
    or if a credential-bearing MOF is missing the `ContentType="PasswordEncrypted"`
    marker. Catches the most dangerous DSC mistake — shipping a MOF whose
    credentials were compiled in clear text — and is wired for CI / release gates.
- `wiki/Securing-Credentials.md`
  - New dedicated page documenting why MOF credential encryption is mandatory, the
    end-to-end flow (`Initialize-DscEncryption` → import `.pfx` per node → compile →
    verify), the clear-text-vs-CMS before/after, certificate rotation with `-Force`,
    and a troubleshooting table.
- `.editorconfig`
  - Locks repository encoding and formatting: `*.ps1` / `*.psd1` / `*.psm1` are
    `utf-8-bom` (Windows PowerShell 5.1 reads a BOM-less file as ANSI, corrupting
    non-ASCII characters at runtime); `*.md` / `*.yml` / `*.yaml` / `*.json` stay
    BOM-less (YAML linters and `dsc.exe` reject a BOM).

### Changed

- `scripts/test/ConfigData.Tests.ps1`
  - The wildcard AllNodes baseline check no longer requires
    `PSDscAllowPlainTextPassword = $true` — which wrongly failed a *secured*
    configuration (the state left by `Initialize-DscEncryption.ps1`). It now
    validates the encrypted branch instead: when
    `PSDscAllowPlainTextPassword = $false`, the wildcard must carry a
    `CertificateFile` and a 40-hex-char `Thumbprint`; when the config isn't yet
    encrypted it is skipped with a reminder (the post-compile MofEncryption
    guard-rail is the hard gate).
- **Encoding** — every `*.ps1` / `*.psd1` under `scripts/` is now UTF-8 **with BOM**
  (13 previously BOM-less files converted; the 4 already-BOM files unchanged), so
  Windows PowerShell 5.1 always reads them as UTF-8. No functional content change.
- `README.md`
  - New **Security** section stating that credentials are encrypted and that
    compiling them in clear text is not a supported configuration, with the
    four-step mandatory flow and a link to the new wiki page.
- `wiki/Getting-Started.md`
  - Certificate generation (step 3) is now flagged **mandatory** with a security
    call-out; a new post-compile step runs `Invoke-MofEncryptionTest.ps1` as a gate.
- `wiki/Usage.md`
  - New "Verify the MOFs are encrypted" gate documented right after compilation.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
