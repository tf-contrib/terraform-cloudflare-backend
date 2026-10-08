#!/usr/bin/env bash
# Tests terraform-cloudflare-sts against a fake cloudflare-sts. Pass the program
# to test, e.g. the Nix package's bin/terraform-cloudflare-sts; the default is
# the script in this repo.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
program="${1:-$root/terraform-cloudflare-sts}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A cloudflare-sts that records its arguments, then runs the command after --
# with the R2 credentials a bucket profile gets.
# Its shebang is this bash's: the Nix sandbox has no /usr/bin/env.
mkdir "$tmp/fake"
printf '#!%s\n' "$BASH" >"$tmp/fake/cloudflare-sts"
cat >>"$tmp/fake/cloudflare-sts" <<'EOF'
printf '%s\n' "$*" >"$FAKE_ARGS"
while [[ "$1" != "--" ]]; do shift; done
shift
CLOUDFLARE_R2_ACCESS_KEY_ID=minted-id \
  CLOUDFLARE_R2_SECRET_ACCESS_KEY=minted-secret \
  CLOUDFLARE_R2_SESSION_TOKEN=minted-session \
  exec "$@"
EOF
chmod +x "$tmp/fake/cloudflare-sts"

# Without cloudflare-sts: only what the script itself needs.
mkdir "$tmp/bare"
for tool in jq dirname cat; do
  ln -s "$(command -v "$tool")" "$tmp/bare/$tool"
done

export FAKE_ARGS="$tmp/args"
failures=0

# Runs the program with a clean environment plus the given variables, and
# saves its stdout, stderr and exit code.
run() {
  local status=0
  env -i HOME="$tmp" FAKE_ARGS="$FAKE_ARGS" "$@" \
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

# The action's credentials: printed as they are, with the session token.
ARGS=(--profile ignored)
rm -f "$FAKE_ARGS"
run PATH="$tmp/fake:$PATH" \
  CLOUDFLARE_R2_ACCESS_KEY_ID=ci-id \
  CLOUDFLARE_R2_SECRET_ACCESS_KEY=ci-secret \
  CLOUDFLARE_R2_SESSION_TOKEN=ci-session
check "env: exit code" 0 "$(cat "$tmp/status")"
check "env: credentials" \
  '{"Version":1,"AccessKeyId":"ci-id","SecretAccessKey":"ci-secret","SessionToken":"ci-session"}' \
  "$(jq -c . "$tmp/stdout")"
check "env: cloudflare-sts not run" "no" "$([[ -e "$FAKE_ARGS" ]] && echo yes || echo no)"

# Static keys, like an R2 API token's: no session token.
ARGS=()
run PATH="$tmp/bare" \
  CLOUDFLARE_R2_ACCESS_KEY_ID=static-id \
  CLOUDFLARE_R2_SECRET_ACCESS_KEY=static-secret
check "static: credentials" \
  '{"Version":1,"AccessKeyId":"static-id","SecretAccessKey":"static-secret"}' \
  "$(jq -c . "$tmp/stdout")"

# A key ID without its secret is an error, not credentials.
ARGS=()
run PATH="$tmp/bare" CLOUDFLARE_R2_ACCESS_KEY_ID=half-id
check "half: exit code" 5 "$(cat "$tmp/status")"
check "half: no stdout" "" "$(cat "$tmp/stdout")"
check "half: says what's missing" yes \
  "$(grep -q 'CLOUDFLARE_R2_SECRET_ACCESS_KEY is not set' "$tmp/stderr" && echo yes || echo no)"

# No credentials: cloudflare-sts exec gets them, with the options passed on.
ARGS=(--profile example-org/app:tofu --ttl 30m)
run PATH="$tmp/fake:$tmp/bare"
check "exec: exit code" 0 "$(cat "$tmp/status")"
check "exec: credentials" \
  '{"Version":1,"AccessKeyId":"minted-id","SecretAccessKey":"minted-secret","SessionToken":"minted-session"}' \
  "$(jq -c . "$tmp/stdout")"
check "exec: arguments" \
  "exec --quiet --profile example-org/app:tofu --ttl 30m -- jq -n -f" \
  "$(sed 's| /[^ ]*/backend.jq$||' "$FAKE_ARGS")"

# An empty key ID counts as none.
ARGS=()
run PATH="$tmp/fake:$tmp/bare" CLOUDFLARE_R2_ACCESS_KEY_ID=
check "empty: credentials from exec" minted-id "$(jq -r .AccessKeyId "$tmp/stdout")"

# No credentials and no cloudflare-sts: says so.
ARGS=()
run PATH="$tmp/bare"
check "missing cli: exit code" 1 "$(cat "$tmp/status")"
check "missing cli: no stdout" "" "$(cat "$tmp/stdout")"
check "missing cli: says so" yes \
  "$(grep -q 'cloudflare-sts is not installed' "$tmp/stderr" && echo yes || echo no)"

# --help needs neither credentials nor cloudflare-sts.
ARGS=(--help)
run PATH="$tmp/bare"
check "help: exit code" 0 "$(cat "$tmp/status")"
check "help: usage" yes "$(grep -q '^Usage: terraform-cloudflare-sts' "$tmp/stdout" && echo yes || echo no)"

if ((failures > 0)); then
  echo "$failures failed"
  exit 1
fi
