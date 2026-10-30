"""Download the Pramaan collector, check its sha256, and write collector.toml.

Reads the PRAMAAN_* environment variables that action.yml sets. Exits non-zero, and
writes nothing it would run, when the download does not match its sha256.
"""

import hashlib
import json
import os
import re
import ssl
import sys
import urllib.request

if sys.version_info < (3, 11):
    sys.exit("The Pramaan collector needs Python 3.11 or later. Add actions/setup-python before this step.")

e = os.environ
version = e.get("PRAMAAN_COLLECTOR_VERSION", "").strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    sys.exit("collector_version should look like 0.29.0.")

name = f"pramaan-{version}.pyz"
base = e["PRAMAAN_API_URL"].rstrip("/") + "/downloads/collector/"
url = e.get("PRAMAAN_COLLECTOR_URL") or base + name
if not url.startswith("https://"):
    sys.exit("The collector is only downloaded over https. Check api_url or collector_url.")

ca_bundle = e.get("PRAMAAN_CA_BUNDLE", "")
if ca_bundle:
    ca_bundle = os.path.abspath(ca_bundle)
    if not os.path.isfile(ca_bundle):
        sys.exit("ca_bundle names a file that does not exist on the runner.")
tls = ssl.create_default_context(cafile=ca_bundle or None)


def fetch(u: str) -> bytes:
    try:
        with urllib.request.urlopen(u, timeout=60, context=tls) as r:
            return r.read()
    except OSError as err:  # URLError, HTTPError and TLS errors are all OSError
        sys.exit(f"Could not download {u}: {getattr(err, 'reason', err)}")


want = e.get("PRAMAAN_COLLECTOR_SHA256", "").strip().lower()
if not want:
    # No pinned sha256: use the line for this file in SHA256SUMS, as
    # `sha256sum -c --ignore-missing` would read it.
    if not base.startswith("https://"):
        sys.exit("SHA256SUMS is only read over https. Check api_url.")
    sums = fetch(base + "SHA256SUMS").decode()
    want = next((p[0].lower() for p in map(str.split, sums.splitlines()) if p[1:] == [name]), "")
    if not want:
        sys.exit(f"{name} is not in SHA256SUMS, so it was not run.")

data = fetch(url)
if hashlib.sha256(data).hexdigest() != want:
    sys.exit(f"{name} does not match its sha256, so it was not run.")

work = e["PRAMAAN_WORK"]
with open(os.path.join(work, "pramaan.pyz"), "wb") as f:
    f.write(data)

# json.dumps gives a valid TOML basic string, so no input can add a key or a table.
lines = [
    f"api_url = {json.dumps(e['PRAMAAN_API_URL'])}",
    f"tenant_id = {json.dumps(e['PRAMAAN_TENANT'])}",
    f"signing_key = {json.dumps(e['PRAMAAN_KEY_FILE'])}",
    'default_application = "ci"',
]
if ca_bundle:
    lines.append(f"ca_bundle = {json.dumps(ca_bundle)}")
lines += [
    "[applications.ci]",
    f"application_id = {json.dumps(e['PRAMAAN_APPLICATION'])}",
    f"release = {json.dumps(e['PRAMAAN_RELEASE'])}",
]
with open(os.path.join(work, "collector.toml"), "w") as f:
    f.write("\n".join(lines) + "\n")
