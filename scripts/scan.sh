#!/usr/bin/env bash
# The Pramaan scan step. action.yml passes every input as a PRAMAAN_* environment
# variable. Nothing in this file is built from a ${{ }} expression, and no input is
# ever evaluated as shell.
set -euo pipefail
umask 077

: "${PRAMAAN_WORK:?PRAMAAN_WORK is not set}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$PRAMAAN_WORK"

# The upload key lives in one owner-only file for the length of this step.
export PRAMAAN_KEY_FILE="$PRAMAAN_WORK/upload-key.pem"
trap 'rm -f "$PRAMAAN_KEY_FILE"' EXIT
if [ -z "${PRAMAAN_KEY:-}" ]; then
  echo "The key input is empty. Set it from a secret, such as secrets.PRAMAAN_UPLOAD_KEY." >&2
  exit 2
fi
printf '%s\n' "$PRAMAAN_KEY" > "$PRAMAAN_KEY_FILE"
unset PRAMAAN_KEY

# Input values are not echoed back, so a crafted value cannot write a workflow command.
case "${PRAMAAN_FAIL_ON:-P1}" in
  P0 | P1 | P2 | P3 | none) ;;
  *)
    echo "fail_on must be P0, P1, P2, P3 or none." >&2
    exit 2
    ;;
esac
case "${PRAMAAN_WAIT:-900}" in
  "" | *[!0-9]*)
    echo "wait must be a whole number of seconds." >&2
    exit 2
    ;;
esac

# Download the collector, check its sha256 and write collector.toml.
python3 "$here/prepare.py"

python3 -m venv "$PRAMAAN_WORK/venv"
"$PRAMAAN_WORK/venv/bin/pip" install --quiet --disable-pip-version-check "cryptography>=42,<47"
py="$PRAMAAN_WORK/venv/bin/python"
pyz="$PRAMAAN_WORK/pramaan.pyz"

got="$("$py" "$pyz" --version)"
if [ "$got" != "pramaan-collector $PRAMAAN_COLLECTOR_VERSION" ]; then
  # collector_version passed the format check in prepare.py, so it is safe to print.
  echo "Expected pramaan-collector $PRAMAAN_COLLECTOR_VERSION, got $got. It was not run." >&2
  exit 2
fi

if [ "${PRAMAAN_FAIL_ON:-P1}" = "none" ]; then
  set --
else
  set -- --fail-on "${PRAMAAN_FAIL_ON:-P1}" --wait "${PRAMAAN_WAIT:-900}"
fi

# Set before the scan, so a later step can still pick up the SBOM when the gate fails.
echo "sbom=$PRAMAAN_WORK/sbom.cdx.json" >> "$GITHUB_OUTPUT"

"$py" "$pyz" --config "$PRAMAAN_WORK/collector.toml" \
  scan "${PRAMAAN_PATH:-.}" --upload --build --fetch-syft -o "$PRAMAAN_WORK/sbom.cdx.json" "$@"
