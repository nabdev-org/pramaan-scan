# Pramaan scan

This action makes a CycloneDX SBOM of your repository in a GitHub Actions job and uploads it to your Pramaan, signed with your upload key. Pramaan matches the SBOM against advisories. With `fail_on` set, the job waits for that match and fails when the SBOM has new findings at or above the priority you choose.

It is a composite action. It runs no container and calls no other action. It downloads the Pramaan collector from your own Pramaan, checks its sha256 and version, and runs it.

Pramaan is made by NeauraBuild. Product site: https://pramaan.neaurabuild.com. Questions: contactus@neaurabuild.com.

## Before you start

You need:

- A Pramaan tenant, and an application in it to upload to. Settings, Collectors in Pramaan shows your tenant id.
- An Ed25519 upload key pair. Make it on your own machine with OpenSSL 1.1.1 or later:

  ```
  openssl genpkey -algorithm ed25519 -out upload-key.pem
  openssl pkey -in upload-key.pem -pubout -out upload-key.pub.pem
  ```

  The OpenSSL that ships with macOS (LibreSSL) cannot make Ed25519 keys. Use the one from Homebrew.

- The public half registered in Pramaan. Open Settings, then Collectors, add a collector for the application and paste the contents of `upload-key.pub.pem`. Never paste `upload-key.pem`. Pramaan refuses a private key.
- The private half stored as an Actions secret, for example `PRAMAAN_UPLOAD_KEY`. Paste the whole file, including the `BEGIN` and `END` lines. Then delete `upload-key.pem` from your machine, or keep it somewhere only you can read.
- A runner with Python 3.11 or later and `venv`, on Linux or macOS. GitHub-hosted `ubuntu-latest` and `macos-latest` runners have both. On a self-hosted Debian or Ubuntu runner, install `python3-venv`. Windows runners are not supported.
- Network access from the runner to your Pramaan, to PyPI (the action installs `cryptography`) and to GitHub releases (the collector downloads Syft).

## Quick start

Add the tenant and application ids as repository variables (Settings, Secrets and variables, Actions, Variables), and the upload key as a secret. Then add this workflow as `.github/workflows/pramaan.yml`:

```yaml
name: SBOM
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  pramaan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: nabdev-org/pramaan-scan@v1
        with:
          api_url: https://pramaan.example.in
          tenant: ${{ vars.PRAMAAN_TENANT }}
          application: ${{ vars.PRAMAAN_APPLICATION }}
          release: ${{ github.ref_name }}-${{ github.run_number }}
          key: ${{ secrets.PRAMAAN_UPLOAD_KEY }}
          fail_on: P1
```

Replace `https://pramaan.example.in` with the address your Pramaan is served on.

`@v1` follows the latest 1.x release. To fix the exact code you run, pin the action to a full commit sha instead, as you would any action: `uses: nabdev-org/pramaan-scan@<commit-sha> # v1.0.0`.

Pull requests from forks do not receive your secrets, so the upload fails on them. Run the job on branches in your own repository, as above. Do not switch to `pull_request_target` to get the secret into a fork's job. That runs the fork's code with your upload key.

To keep the SBOM as a build artefact even when the job fails on findings, add a step after the scan:

```yaml
      - uses: nabdev-org/pramaan-scan@v1
        id: pramaan
        with:
          # as above
      - uses: actions/upload-artifact@<commit-sha> # pin as you would any action
        if: always() && steps.pramaan.outputs.sbom != ''
        with:
          name: sbom
          path: ${{ steps.pramaan.outputs.sbom }}
```

## Inputs

| Input | Required | Default | What it is |
|---|---|---|---|
| `api_url` | yes | | The address your Pramaan is served on, such as `https://pramaan.example.in`. |
| `tenant` | yes | | Your tenant id. Settings, Collectors shows it. |
| `application` | yes | | The id of the application to upload to. |
| `release` | yes | | The release label the SBOM is filed under, such as the tag, or the branch and run number. |
| `key` | yes | | The Ed25519 upload key in PEM form, from a secret. |
| `path` | no | `.` | The directory or lock file to scan, relative to the workspace. |
| `fail_on` | no | `P1` | `P0`, `P1`, `P2`, `P3` or `none`. See Failing the job on findings. |
| `wait` | no | `900` | Seconds to wait for Pramaan to match the SBOM. Used only when `fail_on` is not `none`. |
| `collector_version` | no | `0.29.0` | The collector version to download. |
| `collector_sha256` | no | empty | The sha256 of `pramaan-<collector_version>.pyz`. Empty means the action reads it from your Pramaan's `SHA256SUMS`. |
| `collector_url` | no | empty | Only if you host the collector yourself. Must be https. Empty means `{api_url}/downloads/collector/pramaan-<collector_version>.pyz`. |
| `ca_bundle` | no | empty | Path on the runner to a PEM CA bundle, only if your Pramaan uses a certificate from a private CA. |

## Outputs

| Output | What it is |
|---|---|
| `sbom` | The path of the CycloneDX 1.6 SBOM file the collector wrote, under `runner.temp`. The action sets it before the scan runs, so check that the file exists before you use it. |

## What the action does

1. Writes the upload key from the `key` input to a file only the job's user can read, under `runner.temp`. The file is removed when the step ends, whether it passed or failed.
2. Downloads `pramaan-<collector_version>.pyz` from your Pramaan, or from `collector_url`, over https only.
3. Checks its sha256 (see How the collector is checked). On a mismatch it stops, and nothing it downloaded is run.
4. Installs `cryptography`, the collector's one native dependency, into a throwaway virtualenv.
5. Checks that the collector reports the version you asked for.
6. Runs `pramaan scan PATH --upload --build --fetch-syft`. The collector downloads its pinned Syft from GitHub releases and checks it against the sha256 built into the collector. Syft reads your lock files and the collector writes a CycloneDX 1.6 SBOM. The collector signs the upload with your key and sends it. `--build` marks the SBOM as made in a build. When Syft read a lock file, Pramaan rates the signed SBOM evidence tier A.
7. With `fail_on` set, the collector waits for Pramaan to match the SBOM and then sets the exit code.

## Failing the job on findings

Pramaan gives each finding a priority from P0 to P3. P0 is the most urgent.

`fail_on` is the lowest priority that fails the job:

| `fail_on` | The job fails on new findings at |
|---|---|
| `P0` | P0 |
| `P1` | P0 or P1 |
| `P2` | P0, P1 or P2 |
| `P3` | any priority |
| `none` | never. The SBOM is uploaded and the job does not wait for the match. |

New means the application had the issue on no earlier SBOM. A finding the application already had on an earlier SBOM does not fail the job.

The gate is on findings only. Pramaan has no licence policy yet, so licences never fail the job.

## Exit codes

The step fails with the collector's exit code:

| Code | Meaning |
|---|---|
| 0 | Uploaded, and no new findings at or above `fail_on`. |
| 1 | The collector download failed or did not match its sha256, or the runner's Python is older than 3.11. The log says which. |
| 2 | An input is wrong, such as `fail_on`, `wait` or an empty key, or the collector reported a different version from `collector_version`. |
| 4 | Pramaan refused the upload, or could not process the SBOM. The log names the reason. |
| 5 | Pramaan could not be reached, or kept answering 429 or 5xx, after 5 attempts. |
| 8 | Syft could not be downloaded, did not match its pinned sha256, or could not scan the path. |
| 9 | The SBOM has new findings at or above `fail_on`. |
| 10 | Pramaan did not finish matching the SBOM within `wait` seconds. |

## How the collector is checked

The action never runs a collector it has not checked.

- With `collector_sha256` empty, the action downloads `{api_url}/downloads/collector/SHA256SUMS` and uses the line for `pramaan-<collector_version>.pyz`, as `sha256sum -c --ignore-missing` would. This proves the file arrived intact from your Pramaan. It does not prove more than your Pramaan does, because the file and its checksum come from the same server.
- With `collector_sha256` set, the action compares the download with that value. This is stronger: a changed file on the server fails the job. Settings, Collectors in Pramaan lists each collector file with its sha256.
- In both cases the action then checks that the collector reports `pramaan-collector <collector_version>`.

Each signed collector release also has a `SHA256SUMS.sig` under `{api_url}/downloads/collector/<version>/`, signed with the Pramaan code-signing key. The action does not check that signature. To check it yourself before you pin a sha256:

1. Get the code-signing keyring from your Pramaan at `/verify/code-signing-keyring.json`, apart from the download.
2. Download `SHA256SUMS`, `SHA256SUMS.sig` and `release.json` from `{api_url}/downloads/collector/<version>/`.
3. Take the public key that `release.json` names under `signer.key_id` from the keyring. It must have the purpose `code_signing`.
4. Run `openssl dgst -sha256 -verify code-signing.pub -signature SHA256SUMS.sig SHA256SUMS`. It should print `Verified OK`.
5. Copy the sha256 for `pramaan-<version>.pyz` from that `SHA256SUMS` into `collector_sha256`.

A Pramaan that has not received a signed collector release yet serves only the collector built into it, with no signed `SHA256SUMS`. Use the unpinned check until it has one.

When you upgrade Pramaan, set `collector_version` and `collector_sha256` together to the new collector.

## Self-hosted Pramaan and private CAs

Set `api_url` to the address your Pramaan is served on. The collector signs its sign-in request for that exact address, so use the same one Pramaan is configured with.

If the Pramaan certificate comes from a private CA, give the action the CA certificate in PEM form. Commit the CA certificate (it is public) and point `ca_bundle` at it:

```yaml
      - uses: nabdev-org/pramaan-scan@v1
        with:
          api_url: https://pramaan.internal.example.in
          ca_bundle: .github/pramaan-ca.pem
          # other inputs as in the quick start
```

The action uses it for the collector download and the collector uses it for every call to Pramaan. PyPI and GitHub are still checked against the runner's normal CA store.

To host the collector file yourself, set `collector_url` to an https address and pin `collector_sha256`.

## Troubleshooting

| What the log says | What to do |
|---|---|
| `The key input is empty` | The secret is missing or not available to this job. Check its name, and that the job does not run for a pull request from a fork. |
| `fail_on must be P0, P1, P2, P3 or none` | Fix the `fail_on` value. It is case-sensitive. |
| `wait must be a whole number of seconds` | Set `wait` to digits only, such as `"1200"`. |
| `collector_version should look like 0.29.0` | Set `collector_version` to a version number. |
| `The collector is only downloaded over https` | Use an https `api_url` or `collector_url`. |
| `Could not download ...` with `CERTIFICATE_VERIFY_FAILED` | Your Pramaan uses a private CA. Set `ca_bundle`. |
| `Could not download ...` with `404` | Your Pramaan does not serve that collector version. Settings, Collectors lists what it serves. |
| `... is not in SHA256SUMS, so it was not run` | Your Pramaan does not list that version. Set `collector_version` to one it lists. |
| `... does not match its sha256, so it was not run` | The file differs from the pinned sha256. Check the value against Settings, Collectors. If they match and the job still fails, tell us. |
| `Expected pramaan-collector X, got Y` | `collector_version` does not match the file at `collector_url`. |
| `needs Python 3.11 or later` | Add `actions/setup-python` with Python 3.11 or later before this step. |
| Exit code 4 | Check that the public key is registered on this application in Settings, Collectors, and that `tenant` and `application` are right. |
| Exit code 8 | The runner could not reach GitHub releases for Syft, or `path` does not exist. |
| Exit code 10 | Pramaan is still matching. Raise `wait`, or check the upload in Pramaan. |

## Security notes

- Keep the upload key in an Actions secret. Never write it into the workflow file or the repository. The key can upload SBOMs only, and only to the applications ticked for it. To stop a key, revoke it in Settings, Collectors.
- The action passes every input to its script as an environment variable. No `${{ }}` expression is written into a shell command, so a branch name, tag or other input cannot run a command. The test workflow in this repository checks this with inputs full of shell metacharacters.
- The key file is created with owner-only permissions under `runner.temp` and removed when the step ends, pass or fail.
- The action needs no GitHub token. `permissions: contents: read` is enough for the job.
- `cryptography` is installed from PyPI within a version range, not pinned by hash.
- To report a security issue in this action, see [SECURITY.md](SECURITY.md).

## Licence

See the LICENSE file.
