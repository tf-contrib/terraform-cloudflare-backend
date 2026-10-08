#!/usr/bin/env bash
# Tests terraform-cloudflare-backend. Pass the program to test, e.g. the Nix
# package's bin/terraform-cloudflare-backend; the default is the script in this
# repo.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
program="${1:-$root/terraform-cloudflare-backend}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Only what the script itself needs: no cloudflare-sts, which it never runs.
mkdir "$tmp/bare"
for tool in jq dirname cat; do
  ln -s "$(command -v "$tool")" "$tmp/bare/$tool"
done

failures=0

# Runs the program with a clean environment plus the given variables, and
# saves its stdout, stderr and exit code.
run() {
  local status=0
  env -i HOME="$tmp" PATH="$tmp/bare" "$@" \
    "$BASH" "$program" "${ARGS[@]}" >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
  echo "$status" >"$tmp/status"
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    failures=$((failures + 1))
  fi
}

said() {
  grep -q -- "$1" "$tmp/stderr" && echo yes || echo no
}

# The action's or `cloudflare-sts exec`'s credentials: printed as they are,
# with the session token.
ARGS=()
run CLOUDFLARE_R2_ACCESS_KEY_ID=minted-id \
  CLOUDFLARE_R2_SECRET_ACCESS_KEY=minted-secret \
  CLOUDFLARE_R2_SESSION_TOKEN=minted-session
check "minted: exit code" 0 "$(cat "$tmp/status")"
check "minted: credentials" \
  '{"Version":1,"AccessKeyId":"minted-id","SecretAccessKey":"minted-secret","SessionToken":"minted-session"}' \
  "$(jq -c . "$tmp/stdout")"

# Static keys, like an R2 API token's: no session token.
ARGS=()
run CLOUDFLARE_R2_ACCESS_KEY_ID=static-id \
  CLOUDFLARE_R2_SECRET_ACCESS_KEY=static-secret
check "static: credentials" \
  '{"Version":1,"AccessKeyId":"static-id","SecretAccessKey":"static-secret"}' \
  "$(jq -c . "$tmp/stdout")"

# A key ID without its secret is an error, not credentials.
ARGS=()
run CLOUDFLARE_R2_ACCESS_KEY_ID=half-id
check "half: exit code" 5 "$(cat "$tmp/status")"
check "half: no stdout" "" "$(cat "$tmp/stdout")"
check "half: says what's missing" yes "$(said 'CLOUDFLARE_R2_SECRET_ACCESS_KEY is not set')"

# No credentials: says how to get them, and prints nothing.
for case in unset empty; do
  ARGS=()
  if [[ "$case" == empty ]]; then
    run CLOUDFLARE_R2_ACCESS_KEY_ID=
  else
    run
  fi
  check "$case: exit code" 1 "$(cat "$tmp/status")"
  check "$case: no stdout" "" "$(cat "$tmp/stdout")"
  check "$case: says to run under cloudflare-sts exec" yes "$(said "run tofu under 'cloudflare-sts exec --'")"
done

# Options are refused, such as an older backend.ini's --profile, even with
# credentials: they'd choose nothing.
ARGS=(--profile example-org/app:tofu)
run CLOUDFLARE_R2_ACCESS_KEY_ID=minted-id CLOUDFLARE_R2_SECRET_ACCESS_KEY=minted-secret
check "option: exit code" 2 "$(cat "$tmp/status")"
check "option: no stdout" "" "$(cat "$tmp/stdout")"
check "option: says so" yes "$(said 'takes no options, got --profile')"

# --help needs no credentials.
ARGS=(--help)
run
check "help: exit code" 0 "$(cat "$tmp/status")"
check "help: usage" yes "$(grep -q '^Usage: terraform-cloudflare-backend' "$tmp/stdout" && echo yes || echo no)"

if ((failures > 0)); then
  echo "$failures failed"
  exit 1
fi
