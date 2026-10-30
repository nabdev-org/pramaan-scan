# Changelog

## 1.0.0

First public release of the Pramaan scan action.

- Downloads the Pramaan collector from your Pramaan at `{api_url}/downloads/collector/`, or from `collector_url`, over https only.
- Checks the collector against a pinned `collector_sha256`, or against the line for it in your Pramaan's `SHA256SUMS`, and refuses to run it on a mismatch. Then checks the version it reports.
- Makes a CycloneDX 1.6 SBOM of `path` with the collector's pinned Syft, signs it with your upload key and uploads it to the application and release you name.
- With `fail_on` set to P0, P1, P2 or P3, waits up to `wait` seconds for Pramaan to match the SBOM and fails the job on new findings at that priority or above.
- Passes every input to its script as an environment variable, so no input can run a command.
- Removes the upload key file when the step ends, pass or fail.
- Uses `ca_bundle` for the collector download as well as for the collector's calls to Pramaan.
- Default collector version 0.29.0, with no pinned sha256.
