# Release Process

This page documents how to ship a new version of SPSConfigKit. SPSConfigKit is a
script kit with **no in-repo version field** — a release is defined entirely by a
`v*` git tag, the `CHANGELOG.md` entry and `RELEASE-NOTES.md`. Pushing the tag
triggers the GitHub release workflow (`.github/workflows/release.yml`).

## Versioning policy

SPSConfigKit follows [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html).

| Bump | When |
|---|---|
| MAJOR (X.0.0) | Breaking change to the `.psd1` ConfigurationData / `Secrets` schema, or a change that forces existing farms to be rebuilt. |
| MINOR (X.Y.0) | New backward-compatible capability (new optional setting, new brick/resource, provider or DSC-module bump that adds features). |
| PATCH (X.Y.Z) | Bug fix or documentation-only change. |

## Release checklist

### 1. Promote `[Unreleased]` in `CHANGELOG.md`

Move the accumulated `[Unreleased]` block to a dated section for the version
being released, and add a fresh empty `[Unreleased]` heading on top so future
PRs have somewhere to write to:

```markdown
## [Unreleased]

## [1.8.0] - 2026-MM-DD

### Added
...
### Changed
...
### Fixed
...
```

### 2. Replace `RELEASE-NOTES.md`

`RELEASE-NOTES.md` is used **verbatim** as the body of the GitHub Release. It
must contain **only the section of the version being released** (no
`[Unreleased]` header, no stacked history) plus the trailing `## Changelog`
pointer.

### 3. Validate

Validate the sample ConfigurationData and the credential encryption guard-rail:

```powershell
# Structural validation of a Cfg*.psd1 against Secrets.psd1
.\scripts\test\Invoke-ConfigDataTest.ps1 -ConfigPath .\scripts\sps\CfgAppSps.psd1

# After compiling MOFs: fail if any credential is in clear text
.\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\scripts\sps\MOF
```

> [!IMPORTANT]
> These checks validate structure and encryption, not a live deployment. Before
> tagging a release, **compile and apply the kit end to end on a real (lab)
> farm** — AD/PDC, SQL, the SharePoint farm and OOS — so the tagged version is
> known to build a working farm, not just to parse.

### 4. Commit on a release branch

```bash
git checkout -b release/1.8.0
git add -A
git commit -m "release: v1.8.0"
git push -u origin release/1.8.0
```

Open a Pull Request, review, and merge to `main`.

### 5. Tag from `main`

After the PR is merged:

```bash
git checkout main
git pull
git tag v1.8.0
git push origin v1.8.0
```

The `release.yml` workflow runs automatically. It:

1. Packages `scripts/` into `SPSConfigKit-v1.8.0.zip`.
2. Publishes a GitHub Release using `RELEASE-NOTES.md` as the body.
3. Attaches the ZIP and `LICENSE` to the release.

### 6. Verify

- **Releases**: <https://github.com/luigilink/SPSConfigKit/releases> — the new release is listed with the expected body and ZIP.
- **Actions**: <https://github.com/luigilink/SPSConfigKit/actions> — `release.yml` ran green.
- **Wiki**: <https://github.com/luigilink/SPSConfigKit/wiki> — `wiki.yml` synced any `wiki/` changes pushed in the same release.

## Undoing a release

If you tagged too early:

```bash
git tag -d v1.8.0
git push origin --delete v1.8.0
```

Then delete the auto-created Release on GitHub, fix what needs fixing, commit,
and re-tag from the new HEAD.

> ⚠️ **Don't move a published tag** that has been live for more than a few
> minutes. Prefer publishing a `vX.Y.(Z+1)` patch release instead of rewriting
> `vX.Y.Z`.

## See also

- [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
- [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html)
- [Getting Started](Getting-Started)
- [Configuration](Configuration)
- [Securing Credentials](Securing-Credentials)
