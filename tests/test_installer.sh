#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly ROOT_DIR
TEST_TMP="$(mktemp -d)"
readonly TEST_TMP
trap 'rm -rf -- "$TEST_TMP"' EXIT

readonly TEST_HOME="$TEST_TMP/home"
readonly FAKE_BIN="$TEST_TMP/fake-bin"
mkdir -p -- "$TEST_HOME" "$FAKE_BIN"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for command_name in codex tmux tailscale; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$FAKE_BIN/$command_name"
  chmod 0755 "$FAKE_BIN/$command_name"
done

printf 'set -g status off\n' >"$TEST_HOME/.tmux.conf"

export HOME="$TEST_HOME"
export PATH="$FAKE_BIN:/usr/bin:/bin"
unset XDG_CONFIG_HOME

bash "$ROOT_DIR/install.sh" --skip-deps --skip-connect >/dev/null

[[ -x "$TEST_HOME/.local/bin/codex-mobile" ]] || fail "launcher was not installed"
[[ -x "$TEST_HOME/.local/bin/codex-mobile-add-key" ]] || fail "key helper was not installed"
[[ -f "$TEST_HOME/.config/codex-mobile/tmux.conf" ]] || fail "tmux config was not installed"
cmp -s "$ROOT_DIR/bin/codex-mobile" "$TEST_HOME/.local/bin/codex-mobile" ||
  fail "installed launcher differs from source"

bash "$ROOT_DIR/install.sh" --skip-deps --skip-connect >/dev/null
marker_count="$(grep -Fc '# >>> codex-mobile >>>' "$TEST_HOME/.tmux.conf")"
[[ "$marker_count" == 1 ]] || fail "installer is not idempotent"

if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -q -t ed25519 -N '' -f "$TEST_TMP/phone-key"
  "$TEST_HOME/.local/bin/codex-mobile-add-key" "$TEST_TMP/phone-key.pub" >/dev/null
  "$TEST_HOME/.local/bin/codex-mobile-add-key" "$TEST_TMP/phone-key.pub" >/dev/null
  key_blob="$(awk '{ print $2 }' "$TEST_TMP/phone-key.pub")"
  key_count="$(awk -v blob="$key_blob" '$2 == blob { count++ } END { print count + 0 }' "$TEST_HOME/.ssh/authorized_keys")"
  [[ "$key_count" == 1 ]] || fail "public key helper added a duplicate"
fi

bash "$ROOT_DIR/uninstall.sh" >/dev/null

[[ ! -e "$TEST_HOME/.local/bin/codex-mobile" ]] || fail "launcher was not removed"
[[ ! -e "$TEST_HOME/.config/codex-mobile/tmux.conf" ]] || fail "tmux config was not removed"
grep -Fq 'set -g status off' "$TEST_HOME/.tmux.conf" || fail "user tmux config was damaged"
if grep -Fq '# >>> codex-mobile >>>' "$TEST_HOME/.tmux.conf"; then
  fail "tmux include marker remains after uninstall"
fi
[[ -f "$TEST_HOME/.ssh/authorized_keys" ]] || fail "uninstall removed authorized_keys"

printf '# >>> codex-mobile >>>\nkeep this line\n' >"$TEST_HOME/.tmux.conf"
bash "$ROOT_DIR/install.sh" --skip-deps --skip-connect >/dev/null 2>&1 &&
  fail "installer accepted a malformed marker block"
grep -Fq 'keep this line' "$TEST_HOME/.tmux.conf" || fail "malformed tmux config was damaged"
bash "$ROOT_DIR/uninstall.sh" >/dev/null 2>&1
grep -Fq 'keep this line' "$TEST_HOME/.tmux.conf" || fail "uninstaller damaged a malformed tmux config"

printf 'PASS: install, idempotency, key helper, and uninstall\n'
