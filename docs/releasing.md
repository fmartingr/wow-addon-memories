# Releasing

`.github/workflows/release.yml` builds the addon zip and the WoW Journey app for Windows, macOS and Linux. A tag
`v*` publishes them as a GitHub Release. A manual run builds the same files and publishes nothing.

## Cut a release

1. Check that CI passes on `main`.
2. Tag the commit and push the tag:

   ```sh
   git tag -a v1.2.3 -m "v1.2.3"
   git push origin v1.2.3
   ```

3. The workflow builds the 4 files, then the `publish` job creates the release with notes generated from the commits.

- **Version:** the tag without `v` (`v1.2.3` gives `1.2.3`). The tag must be `v` + semver: `vMAJOR.MINOR.PATCH`,
  with an optional pre-release part (`v1.2.3-rc.1`). Build metadata (`v1.2.3+build.5`) is refused, because Flutter
  reads `+` in `--build-name` as the build number. Another tag fails in the `version` job and nothing is built.
- **Pre-release:** a tag with a pre-release part (`v1.0.0-rc.1`) makes a GitHub pre-release.
- **App version:** the app gets `--build-name=<version>`, `--build-number=<run number>` and
  `--dart-define=APP_VERSION=<version>`; the settings page shows `APP_VERSION`. The `version` in `app/pubspec.yaml`
  is not used for a release.
- **Addon version:** each TOC in the zip gets `## Version: <version>`. The TOCs in `addons/` keep their version.
- **Re-run:** re-run the failed jobs in the Actions tab. When the release exists, the `publish` job replaces its files
  and does not fail.

## Release files

| File | What it is |
|---|---|
| `Memories-addons-<version>.zip` | The 6 addon folders (`Memories/`, `Memories_Character/`, `Memories_Combat/`, `Memories_Economy/`, `Memories_Gathering/`, `Memories_Social/`) at the zip root. Unpack it into `Interface/AddOns` of the flavor folder. Built by `scripts/package-addons.sh`. |
| `WoW-Journey-<version>-windows-x64.zip` | The folder `WoW-Journey/` with `wow_journey.exe` and its DLLs and `data/`. Not signed. |
| `WoW-Journey-<version>-macos.zip` | `wow_journey.app`, a universal app (arm64 and x86_64), signed with the Developer ID certificate and the Hardened Runtime, notarized and stapled. |
| `WoW-Journey-<version>-linux-x64.tar.gz` | The folder `WoW-Journey/` with the `wow_journey` binary, `lib/` and `data/`. It needs the shared libraries listed in the README. |

## Dry run

In the Actions tab, open **Release** and click **Run workflow** on a branch. The run builds the 4 files with the
version `0.0.0-dev.<run number>` and keeps them as the workflow artifacts `release-addons`, `release-windows`,
`release-macos` and `release-linux`. It creates no tag and no release. A manual run on a tag uses the tag version and
also publishes nothing.

The macOS job signs and notarizes in a dry run too, so it needs the secrets below.

## macOS signing secrets

The macOS job needs these 7 repository secrets (Settings > Secrets and variables > Actions). When one is empty, the
job fails with a message that names it. The job never uploads an app that is not signed, notarized and accepted by
Gatekeeper. The secrets reach only the steps that use them. The certificate goes into a temporary keychain that an
`always()` step deletes, with the key files, at the end of the job.

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE` | The Developer ID Application certificate and its private key, as a `.p12` file in base64. |
| `MACOS_CERTIFICATE_PASSWORD` | The password of the `.p12` file. |
| `MACOS_KEYCHAIN_PASSWORD` | Any random password for the temporary keychain on the runner. |
| `MACOS_SIGNING_IDENTITY` | The identity name, for example `Developer ID Application: Your Name (TEAMID1234)`. |
| `APPLE_API_KEY_ID` | The key ID of the App Store Connect API key. |
| `APPLE_API_ISSUER_ID` | The issuer ID of the App Store Connect API keys. |
| `APPLE_API_KEY` | The `AuthKey_<key id>.p8` file of the API key, in base64. |

Create them on a Mac, with a paid Apple Developer Program membership:

1. **Certificate.** In Keychain Access, choose Certificate Assistant > Request a Certificate From a Certificate
   Authority and save the request to disk. In the Apple Developer site, Certificates, Identifiers & Profiles, add a
   **Developer ID Application** certificate (only the Account Holder can) with that request. Download it and open it,
   so it joins your login keychain with its private key.
2. **Identity.** `security find-identity -v -p codesigning` lists it. Copy the quoted name, `Developer ID Application:
   ... (TEAMID)`, into `MACOS_SIGNING_IDENTITY`.
3. **`.p12`.** In Keychain Access, under My Certificates, right-click the certificate, Export, as a `.p12` file with a
   strong password. The password goes into `MACOS_CERTIFICATE_PASSWORD`.
4. **API key.** In App Store Connect, Users and Access > Integrations > App Store Connect API > Team Keys, generate a
   key with the **Developer** role. Note the issuer ID and the key ID, and download the `.p8` file (it downloads only
   once).
5. **Store the secrets** with the GitHub CLI, so no value lands in the shell history:

   ```sh
   base64 -i Certificates.p12 | gh secret set MACOS_CERTIFICATE
   gh secret set MACOS_CERTIFICATE_PASSWORD     # paste the .p12 password
   openssl rand -base64 32 | gh secret set MACOS_KEYCHAIN_PASSWORD
   gh secret set MACOS_SIGNING_IDENTITY         # paste "Developer ID Application: ... (TEAMID)"
   gh secret set APPLE_API_KEY_ID               # paste the key ID
   gh secret set APPLE_API_ISSUER_ID            # paste the issuer ID
   base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set APPLE_API_KEY
   ```

6. Delete the `.p12` and `.p8` files from the disk, or keep them in a password manager.

The macOS app has no app sandbox (`app/macos/Runner/Release.entitlements`), because the sandbox blocks the read of the
WoW folder. A Developer ID app outside the Mac App Store may run without it. The Hardened Runtime is on, through
`codesign --options runtime`. A debug build (`make companion`) uses `DebugProfile.entitlements`, which keeps the
sandbox.

## After a release

Run the manual checks 12 to 14 of [`app-manual-checklist.md`](app-manual-checklist.md) on the downloaded files.
