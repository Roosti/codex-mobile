#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly ROOT_DIR
readonly LAUNCHER="$ROOT_DIR/bin/codex-mobile"
TEST_TMP="$(mktemp -d)"
readonly TEST_TMP
trap 'rm -rf -- "$TEST_TMP"' EXIT

readonly FAKE_BIN="$TEST_TMP/bin"
readonly FAKE_LOG="$TEST_TMP/calls.log"
readonly PROJECT_DIR="$TEST_TMP/project with spaces"
mkdir -p -- "$FAKE_BIN" "$PROJECT_DIR"
touch -- "$FAKE_LOG"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$file" || fail "expected $file to contain: $expected"
}

cat >"$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -u
{
  printf 'tmux'
  printf '[%s]' "$@"
  printf '\n'
} >>"$FAKE_LOG"

case "${1:-}" in
  has-session)
    [[ "${FAKE_SESSION_EXISTS:-false}" == true ]]
    ;;
  list-sessions)
    if [[ "${FAKE_SESSION_EXISTS:-false}" == true ]]; then
      printf 'demo  1 window(s)  now\n'
    else
      exit 1
    fi
    ;;
esac
EOF

cat >"$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -u
{
  printf 'codex'
  printf '[%s]' "$@"
  printf '\n'
} >>"$FAKE_LOG"
EOF

chmod 0755 "$FAKE_BIN/tmux" "$FAKE_BIN/codex"
export PATH="$FAKE_BIN:$PATH"
export FAKE_LOG

help_output="$("$LAUNCHER" --help)"
[[ "$help_output" == *"persistent tmux session"* ]] || fail "help output is incomplete"
[[ "$("$LAUNCHER" --version)" == "codex-mobile 0.1.0" ]] || fail "wrong version output"

if "$LAUNCHER" --session 'bad/name' "$PROJECT_DIR" >/dev/null 2>&1; then
  fail "invalid session name was accepted"
fi

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=false "$LAUNCHER" --detach --session demo "$PROJECT_DIR" -- --full-auto >/dev/null
assert_contains "$FAKE_LOG" "tmux[has-session][-t][demo]"
assert_contains "$FAKE_LOG" "tmux[new-session][-d][-s][demo][-c][$PROJECT_DIR][--][$FAKE_BIN/codex][-C][$PROJECT_DIR][--full-auto]"

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=true "$LAUNCHER" --session demo "$PROJECT_DIR" >/dev/null
assert_contains "$FAKE_LOG" "tmux[attach-session][-t][demo]"

: >"$FAKE_LOG"
TMUX=fake FAKE_SESSION_EXISTS=false "$LAUNCHER" "$PROJECT_DIR" -- --search >/dev/null
assert_contains "$FAKE_LOG" "codex[-C][$PROJECT_DIR][--search]"
if grep -Fq 'new-session' "$FAKE_LOG"; then
  fail "launcher nested tmux from inside tmux"
fi

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=true "$LAUNCHER" --session demo --stop >/dev/null
assert_contains "$FAKE_LOG" "tmux[kill-session][-t][demo]"

list_output="$(FAKE_SESSION_EXISTS=false "$LAUNCHER" --list)"
[[ "$list_output" == "No tmux sessions are running." ]] || fail "empty session list was unclear"

printf 'PASS: launcher behavior\n'
