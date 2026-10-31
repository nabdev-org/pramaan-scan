#!/usr/bin/env bash
# Self-test for the action's scripts. Needs bash, openssl, Python 3.11 or later as
# python3, and network access to PyPI (the script installs cryptography). It does not
# need a Pramaan server: it serves a fake collector over local https with a throwaway CA
# and runs scripts/scan.sh against it. The fake collector records what it was given.
#
# It checks that:
#   - no run: line in action.yml contains a ${{ }} expression
#   - inputs full of shell metacharacters reach the collector literally and run nothing
#   - the upload key exists while the collector runs and is gone afterwards
#   - a sha256 mismatch stops the step before anything is run
#   - a bad fail_on or wait is refused
#   - fail_on none drops --fail-on and --wait
#   - the download trusts the private CA only when ca_bundle names it
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

fails=0
pass() { echo "ok   $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
# expect DESCRIPTION COMMAND...: passes when COMMAND succeeds.
expect() {
  local desc="$1"
  shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}
absent() { [ ! -e "$1" ]; }

# 1. Structural guard: no expression inside a run: line, and every run: is one line.
if grep -nE '^[[:space:]]*run:' "$root/action.yml" | grep -qE '\$\{\{|run:[[:space:]]*[|>]'; then
  fail "action.yml has a run: block with an expression or a multi-line script"
else
  pass "action.yml run: lines carry no expressions"
fi

# 2. A throwaway CA, a server certificate for 127.0.0.1 and an upload key. Never real keys.
cd "$tmp"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=pramaan-test-ca" \
  -keyout ca.key -out ca.pem \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=127.0.0.1" -keyout srv.key -out srv.csr 2>/dev/null
printf 'subjectAltName=IP:127.0.0.1\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nauthorityKeyIdentifier=keyid\n' > srv.ext
openssl x509 -req -in srv.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 1 \
  -extfile srv.ext -out srv.pem 2>/dev/null
# The fake collector never uses the key, so where openssl has no Ed25519 (LibreSSL on
# macOS) any throwaway private key will do.
openssl genpkey -algorithm ed25519 -out upload-key.pem 2>/dev/null ||
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out upload-key.pem 2>/dev/null

# 3. The fake collector: prints its version, and on scan records argv, config and key.
mkdir -p fake www/downloads/collector
cat > fake/__main__.py <<'PY'
import json, os, sys, tomllib
args = sys.argv[1:]
if args == ["--version"]:
    print("pramaan-collector 0.29.0")
    sys.exit(0)
with open(args[args.index("--config") + 1], "rb") as f:
    config = tomllib.load(f)
record = {"argv": args, "config": config, "key_present": os.path.isfile(config["signing_key"])}
with open(os.environ["FAKE_RECORD"], "w") as f:
    json.dump(record, f)
PY
python3 -m zipapp fake -o www/downloads/collector/pramaan-0.29.0.pyz
sha="$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' www/downloads/collector/pramaan-0.29.0.pyz)"
printf '%s  pramaan-0.29.0.pyz\n' "$sha" > www/downloads/collector/SHA256SUMS

# 4. Serve it over https on a free port.
python3 - "$tmp" > server.log 2>&1 <<'PY' &
import functools, http.server, ssl, sys
d = sys.argv[1]
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(f"{d}/srv.pem", f"{d}/srv.key")
h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=f"{d}/www")
s = http.server.HTTPServer(("127.0.0.1", 0), h)
s.socket = ctx.wrap_socket(s.socket, server_side=True)
with open(f"{d}/port", "w") as f:
    f.write(str(s.server_address[1]))
s.serve_forever()
PY
server_pid=$!
# A cold macOS runner can take several seconds to start Python with TLS: wait up to 30 s,
# and stop early with the server's log if the process has died.
for _ in $(seq 300); do
  [ -s port ] && break
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.1
done
[ -s port ] || { cat server.log; echo "the test server did not start"; exit 1; }
api="https://127.0.0.1:$(cat port)"

# Hostile values. If any of them were evaluated as shell, $tmp/pwned would appear.
mark="$tmp/pwned"
evil_tenant="\$(touch $mark)"
evil_app="x' && touch $mark #"
evil_release="\`touch $mark\`; touch $mark"
evil_path="\"; touch $mark; echo \""
evil_tenant_toml=$'t"\n[applications.evil]\nx = "1'
export EVIL_TENANT="$evil_tenant" EVIL_APP="$evil_app" EVIL_RELEASE="$evil_release" EVIL_PATH="$evil_path"

# run_action NAME [VAR=VALUE ...]: runs scan.sh with the defaults below plus overrides.
run_action() {
  local name="$1"
  shift
  rm -rf "$tmp/work-$name"
  env -i PATH="$PATH" HOME="$HOME" \
    GITHUB_OUTPUT="$tmp/out-$name" \
    FAKE_RECORD="$tmp/record-$name.json" \
    PRAMAAN_API_URL="$api" \
    PRAMAAN_TENANT="$evil_tenant" \
    PRAMAAN_APPLICATION="$evil_app" \
    PRAMAAN_RELEASE="$evil_release" \
    PRAMAAN_KEY="$(cat "$tmp/upload-key.pem")" \
    PRAMAAN_PATH="$evil_path" \
    PRAMAAN_FAIL_ON=P1 \
    PRAMAAN_WAIT=5 \
    PRAMAAN_COLLECTOR_URL="" \
    PRAMAAN_COLLECTOR_VERSION=0.29.0 \
    PRAMAAN_COLLECTOR_SHA256="" \
    PRAMAAN_CA_BUNDLE="$tmp/ca.pem" \
    PRAMAAN_WORK="$tmp/work-$name" \
    "$@" \
    bash "$root/scripts/scan.sh" > "$tmp/log-$name" 2>&1
}

check() { # check NAME PYTHON-EXPRESSION-ON-r
  python3 - "$tmp/record-$1.json" "$2" <<'PY'
import json, os, sys
r = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2], {"r": r, "env": os.environ}) else 1)
PY
}

# 5. Hostile inputs, SHA256SUMS lookup, private CA.
if run_action hostile; then
  pass "scan.sh ran with hostile inputs"
  expect "no input was run as a command" absent "$mark"
  expect "tenant, application and release reached collector.toml unchanged" check hostile \
    "r['config']['tenant_id'] == env['EVIL_TENANT'] and r['config']['applications']['ci']['application_id'] == env['EVIL_APP'] and r['config']['applications']['ci']['release'] == env['EVIL_RELEASE']"
  expect "path reached the collector as one literal argument" check hostile \
    "r['argv'][r['argv'].index('scan') + 1] == env['EVIL_PATH']"
  expect "fail_on and wait passed to the collector" check hostile \
    "r['argv'][-4:] == ['--fail-on', 'P1', '--wait', '5'] and '--build' in r['argv'] and '--fetch-syft' in r['argv']"
  expect "upload key present while the collector ran" check hostile "r['key_present']"
  expect "upload key removed after the step" absent "$tmp/work-hostile/upload-key.pem"
  expect "sbom output set" grep -qx "sbom=$tmp/work-hostile/sbom.cdx.json" "$tmp/out-hostile"
else
  fail "scan.sh failed with hostile inputs"
  cat "$tmp/log-hostile"
fi

# 6. A TOML injection attempt in tenant stays one string, and fail_on none drops the gate.
if run_action toml PRAMAAN_TENANT="$evil_tenant_toml" PRAMAAN_FAIL_ON=none; then
  expect "a tenant with quotes and newlines cannot add a TOML table" check toml \
    "'evil' not in r['config']['applications'] and r['config']['tenant_id'].startswith('t\"')"
  expect "fail_on none drops --fail-on and --wait" check toml \
    "'--fail-on' not in r['argv'] and '--wait' not in r['argv']"
else
  fail "scan.sh failed with fail_on none"
  cat "$tmp/log-toml"
fi

# 7. A wrong pinned sha256 stops the step, runs nothing and removes the key.
if run_action badsha PRAMAAN_COLLECTOR_SHA256="$(printf '0%.0s' $(seq 64))"; then
  fail "a sha256 mismatch did not fail the step"
else
  expect "a sha256 mismatch is reported" grep -q "does not match its sha256" "$tmp/log-badsha"
  expect "the collector did not run after a sha256 mismatch" absent "$tmp/record-badsha.json"
  expect "upload key removed after a failed step" absent "$tmp/work-badsha/upload-key.pem"
fi

# 8. Refusals that happen before anything is downloaded or run.
refused() { # refused NAME MESSAGE VAR=VALUE...
  local name="$1" msg="$2"
  shift 2
  if run_action "$name" "$@"; then
    fail "$name was accepted"
  else
    expect "$name refused" grep -q "$msg" "$tmp/log-$name"
  fi
}
refused bad_fail_on "fail_on must be" PRAMAAN_FAIL_ON="P1; touch $mark"
refused bad_wait "wait must be" PRAMAAN_WAIT="5 --help"
refused bad_version "collector_version should look like" PRAMAAN_COLLECTOR_VERSION="0.29.0/../x"
refused plain_http "only downloaded over https" PRAMAAN_API_URL="http://127.0.0.1:1"
refused empty_key "key input is empty" PRAMAAN_KEY=""
refused no_private_ca "CERTIFICATE_VERIFY_FAILED" PRAMAAN_CA_BUNDLE=""
expect "no refused input was run as a command" absent "$mark"

if [ "$fails" -gt 0 ]; then
  echo "$fails check(s) failed"
  exit 1
fi
echo "All checks passed"
