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
readonly OTHER_PROJECT_DIR="$TEST_TMP/other project"
mkdir -p -- "$FAKE_BIN" "$PROJECT_DIR" "$OTHER_PROJECT_DIR"
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
  show-options)
    [[ -n "${FAKE_SESSION_PROJECT:-}" ]] || exit 1
    printf '%s\n' "$FAKE_SESSION_PROJECT"
    ;;
  list-sessions)
    if [[ "${FAKE_SESSION_EXISTS:-false}" == true ]]; then
      if [[ "${3:-}" == '#{session_name}' ]]; then
        printf '%s\n' "${FAKE_EXISTING_SESSION_NAME:-demo}"
      else
        printf 'demo  1 window(s)  now\n'
      fi
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
expected_version="$(<"$ROOT_DIR/VERSION")"
[[ "$("$LAUNCHER" --version)" == "codex-mobile $expected_version" ]] ||
  fail "launcher version does not match VERSION"

if "$LAUNCHER" --session 'bad/name' "$PROJECT_DIR" >/dev/null 2>&1; then
  fail "invalid session name was accepted"
fi

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=true FAKE_EXISTING_SESSION_NAME=demo-old \
  "$LAUNCHER" --detach --session demo "$PROJECT_DIR" >/dev/null
assert_contains "$FAKE_LOG" "tmux[new-session][-d][-s][demo][-c][$PROJECT_DIR]"

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=false "$LAUNCHER" --session demo "$PROJECT_DIR" -- --search >/dev/null
assert_contains "$FAKE_LOG" "tmux[list-sessions][-F][#{session_name}]"
assert_contains "$FAKE_LOG" "tmux[new-session][-d][-s][demo][-c][$PROJECT_DIR][--][$FAKE_BIN/codex][-C][$PROJECT_DIR][--search]"
assert_contains "$FAKE_LOG" "tmux[set-option][-t][demo][@codex-mobile-project][$PROJECT_DIR]"
assert_contains "$FAKE_LOG" "tmux[attach-session][-t][demo]"

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=true FAKE_SESSION_PROJECT="$PROJECT_DIR" \
  "$LAUNCHER" --session demo "$PROJECT_DIR" >/dev/null
assert_contains "$FAKE_LOG" "tmux[show-options][-v][-t][demo][@codex-mobile-project]"
assert_contains "$FAKE_LOG" "tmux[attach-session][-t][demo]"

: >"$FAKE_LOG"
(
  cd -- "$OTHER_PROJECT_DIR"
  FAKE_SESSION_EXISTS=true FAKE_SESSION_PROJECT="$PROJECT_DIR" \
    "$LAUNCHER" --session demo >/dev/null
)
assert_contains "$FAKE_LOG" "tmux[attach-session][-t][demo]"

: >"$FAKE_LOG"
(
  cd -- "$OTHER_PROJECT_DIR"
  TMUX=fake FAKE_SESSION_EXISTS=true FAKE_SESSION_PROJECT="$PROJECT_DIR" \
    "$LAUNCHER" --session demo >/dev/null
)
assert_contains "$FAKE_LOG" "tmux[switch-client][-t][demo]"

: >"$FAKE_LOG"
if FAKE_SESSION_EXISTS=true FAKE_SESSION_PROJECT="$PROJECT_DIR" \
  "$LAUNCHER" --session demo "$OTHER_PROJECT_DIR" >/dev/null 2>"$TEST_TMP/mismatch.err"; then
  fail "launcher attached to a session for a different project"
fi
assert_contains "$TEST_TMP/mismatch.err" "session \"demo\" is already running in:"
assert_contains "$TEST_TMP/mismatch.err" "$PROJECT_DIR"
assert_contains "$TEST_TMP/mismatch.err" "Requested:"
assert_contains "$TEST_TMP/mismatch.err" "$OTHER_PROJECT_DIR"
assert_contains "$TEST_TMP/mismatch.err" "Use -s NAME to create another session."
if grep -Fq 'attach-session' "$FAKE_LOG"; then
  fail "launcher attached after detecting a project mismatch"
fi

: >"$FAKE_LOG"
if FAKE_SESSION_EXISTS=true FAKE_EXISTING_SESSION_NAME=legacy \
  "$LAUNCHER" --session legacy "$PROJECT_DIR" \
  >/dev/null 2>"$TEST_TMP/missing-metadata.err"; then
  fail "launcher attached to a session without project metadata"
fi
assert_contains "$TEST_TMP/missing-metadata.err" "has no project-directory metadata"

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=false "$LAUNCHER" --detach --session api "$PROJECT_DIR" >/dev/null
assert_contains "$FAKE_LOG" "tmux[new-session][-d][-s][api][-c][$PROJECT_DIR]"
assert_contains "$FAKE_LOG" "tmux[set-option][-t][api][@codex-mobile-project][$PROJECT_DIR]"

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=false "$LAUNCHER" --detach --session web "$OTHER_PROJECT_DIR" >/dev/null
assert_contains "$FAKE_LOG" "tmux[new-session][-d][-s][web][-c][$OTHER_PROJECT_DIR]"
assert_contains "$FAKE_LOG" "tmux[set-option][-t][web][@codex-mobile-project][$OTHER_PROJECT_DIR]"

: >"$FAKE_LOG"
TMUX=fake FAKE_SESSION_EXISTS=true FAKE_SESSION_PROJECT="$PROJECT_DIR" \
  "$LAUNCHER" --session demo "$PROJECT_DIR" >/dev/null
assert_contains "$FAKE_LOG" "tmux[switch-client][-t][demo]"
if grep -Fq 'attach-session' "$FAKE_LOG"; then
  fail "launcher tried to attach a nested tmux client"
fi

: >"$FAKE_LOG"
TMUX=fake FAKE_SESSION_EXISTS=false \
  "$LAUNCHER" --session fresh "$OTHER_PROJECT_DIR" -- --search >/dev/null
assert_contains "$FAKE_LOG" "tmux[new-session][-d][-s][fresh][-c][$OTHER_PROJECT_DIR][--][$FAKE_BIN/codex][-C][$OTHER_PROJECT_DIR][--search]"
assert_contains "$FAKE_LOG" "tmux[set-option][-t][fresh][@codex-mobile-project][$OTHER_PROJECT_DIR]"
assert_contains "$FAKE_LOG" "tmux[switch-client][-t][fresh]"
if grep -Fq '^codex' "$FAKE_LOG"; then
  fail "launcher ran Codex directly instead of honoring the requested session"
fi

: >"$FAKE_LOG"
FAKE_SESSION_EXISTS=true "$LAUNCHER" --session demo --stop >/dev/null
assert_contains "$FAKE_LOG" "tmux[kill-session][-t][demo]"

list_output="$(FAKE_SESSION_EXISTS=false "$LAUNCHER" --list)"
[[ "$list_output" == "No tmux sessions are running." ]] || fail "empty session list was unclear"

printf 'PASS: launcher behavior\n'
