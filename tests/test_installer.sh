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
expected_version="$(<"$ROOT_DIR/VERSION")"
[[ "$("$ROOT_DIR/bin/codex-mobile" --version)" == "codex-mobile $expected_version" ]] ||
  fail "source launcher version does not match VERSION"
[[ "$("$TEST_HOME/.local/bin/codex-mobile" --version)" == "codex-mobile $expected_version" ]] ||
  fail "installed launcher version does not match VERSION"

bash "$ROOT_DIR/install.sh" --skip-deps --skip-connect >/dev/null
marker_count="$(grep -Fc '# >>> codex-mobile >>>' "$TEST_HOME/.tmux.conf" || true)"
[[ "$marker_count" == 1 ]] || fail "installer is not idempotent; marker count: $marker_count"

bash "$ROOT_DIR/uninstall.sh" >/dev/null

[[ ! -e "$TEST_HOME/.local/bin/codex-mobile" ]] || fail "launcher was not removed"
[[ ! -e "$TEST_HOME/.config/codex-mobile/tmux.conf" ]] || fail "tmux config was not removed"
grep -Fq 'set -g status off' "$TEST_HOME/.tmux.conf" || fail "user tmux config was damaged"
if grep -Fq '# >>> codex-mobile >>>' "$TEST_HOME/.tmux.conf"; then
  fail "tmux include marker remains after uninstall"
fi
bash "$ROOT_DIR/uninstall.sh" >/dev/null || fail "uninstall is not idempotent"

version_source="$TEST_TMP/version-source"
version_home="$TEST_TMP/version-home"
mkdir -p -- "$version_source/bin" "$version_source/config" "$version_home"
cp -- "$ROOT_DIR/install.sh" "$ROOT_DIR/VERSION" "$version_source/"
cp -- "$ROOT_DIR/bin/codex-mobile" "$ROOT_DIR/bin/codex-mobile-add-key" "$version_source/bin/"
cp -- "$ROOT_DIR/config/tmux.conf" "$version_source/config/"
printf '9.8.7\n' >"$version_source/VERSION"
[[ "$("$version_source/bin/codex-mobile" --version)" == 'codex-mobile 9.8.7' ]] ||
  fail "source launcher did not read the canonical VERSION file"
HOME="$version_home" bash "$version_source/install.sh" --skip-deps --skip-connect >/dev/null
[[ "$("$version_home/.local/bin/codex-mobile" --version)" == 'codex-mobile 9.8.7' ]] ||
  fail "installer did not stamp VERSION into the installed launcher"

invalid_version_source="$TEST_TMP/invalid-version-source"
invalid_version_home="$TEST_TMP/invalid-version-home"
cp -R -- "$version_source" "$invalid_version_source"
mkdir -p -- "$invalid_version_home"
printf '9.8.7"broken\n' >"$invalid_version_source/VERSION"
if "$invalid_version_source/bin/codex-mobile" --version >/dev/null 2>&1; then
  fail "source launcher accepted an invalid VERSION value"
fi
if HOME="$invalid_version_home" bash "$invalid_version_source/install.sh" \
  --skip-deps --skip-connect >/dev/null 2>&1; then
  fail "installer accepted an invalid VERSION value"
fi
[[ ! -e "$invalid_version_home/.local/bin/codex-mobile" ]] ||
  fail "invalid VERSION was rejected after files were installed"

drift_source="$TEST_TMP/drift-source"
drift_home="$TEST_TMP/drift-home"
cp -R -- "$version_source" "$drift_source"
mkdir -p -- "$drift_home"
sed -i 's/CODEX_MOBILE_VERSION="__CODEX_MOBILE_VERSION__"/CODEX_MOBILE_VERSION="0.0.0"/' \
  "$drift_source/bin/codex-mobile"
if HOME="$drift_home" bash "$drift_source/install.sh" --skip-deps --skip-connect \
  >/dev/null 2>&1; then
  fail "installer accepted a launcher without exactly one version placeholder"
fi
[[ ! -e "$drift_home/.local/bin/codex-mobile" ]] ||
  fail "launcher template drift was detected after files were installed"

for invalid_key_case in missing nonexistent malformed; do
  validation_home="$TEST_TMP/key-$invalid_key_case-home"
  mkdir -p -- "$validation_home"
  printf 'user tmux setting\n' >"$validation_home/.tmux.conf"
  cp -- "$validation_home/.tmux.conf" "$TEST_TMP/key-$invalid_key_case-before"

  case "$invalid_key_case" in
    missing)
      key_args=(--mode key --skip-deps --skip-connect)
      ;;
    nonexistent)
      key_args=(--mode key --key-file "$TEST_TMP/does-not-exist.pub" --skip-deps --skip-connect)
      ;;
    malformed)
      printf 'ssh-ed25519 definitely-not-a-valid-key phone\n' >"$TEST_TMP/malformed.pub"
      key_args=(--mode key --key-file "$TEST_TMP/malformed.pub" --skip-deps --skip-connect)
      ;;
  esac

  if HOME="$validation_home" bash "$ROOT_DIR/install.sh" "${key_args[@]}" \
    >"$TEST_TMP/key-$invalid_key_case.out" 2>"$TEST_TMP/key-$invalid_key_case.err"; then
    fail "key mode accepted the $invalid_key_case key case"
  fi
  [[ ! -e "$validation_home/.local/bin/codex-mobile" ]] ||
    fail "$invalid_key_case key validation occurred after files were installed"
  cmp -s "$TEST_TMP/key-$invalid_key_case-before" "$validation_home/.tmux.conf" ||
    fail "$invalid_key_case key validation changed tmux configuration"
done

if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -q -t ed25519 -N '' -C 'installer test' -f "$TEST_TMP/phone-key"
  key_home="$TEST_TMP/key-valid-home"
  mkdir -p -- "$key_home"
  HOME="$key_home" bash "$ROOT_DIR/install.sh" --mode key \
    --key-file "$TEST_TMP/phone-key.pub" --skip-deps --skip-connect \
    >"$TEST_TMP/key-valid.out" 2>"$TEST_TMP/key-valid.err"
  [[ -f "$key_home/.ssh/authorized_keys" ]] || fail "valid key was not installed"
  grep -Fq 'WARNING: OpenSSH key mode changes SSH exposure.' "$TEST_TMP/key-valid.err" ||
    fail "key mode warning was not prominent"
  grep -Fq 'may listen on non-Tailscale interfaces' "$TEST_TMP/key-valid.err" ||
    fail "key mode warning omitted non-Tailscale exposure"

  cp -- "$key_home/.ssh/authorized_keys" "$TEST_TMP/authorized-before-uninstall"
  HOME="$key_home" bash "$ROOT_DIR/uninstall.sh" >/dev/null
  cmp -s "$TEST_TMP/authorized-before-uninstall" "$key_home/.ssh/authorized_keys" ||
    fail "uninstall changed authorized_keys"
else
  printf 'SKIP: valid installer key-mode test requires ssh-keygen\n'
fi

readonly MARKER_START='# >>> codex-mobile >>>'
readonly MARKER_END='# <<< codex-mobile <<<'
for marker_case in start-only end-only duplicate-start duplicate-end reversed; do
  marker_home="$TEST_TMP/marker-$marker_case-home"
  mkdir -p -- "$marker_home"
  case "$marker_case" in
    start-only)
      printf '%s\nkeep this line\n' "$MARKER_START" >"$marker_home/.tmux.conf"
      ;;
    end-only)
      printf 'keep this line\n%s\n' "$MARKER_END" >"$marker_home/.tmux.conf"
      ;;
    duplicate-start)
      printf '%s\n%s\nkeep this line\n%s\n' \
        "$MARKER_START" "$MARKER_START" "$MARKER_END" >"$marker_home/.tmux.conf"
      ;;
    duplicate-end)
      printf '%s\nkeep this line\n%s\n%s\n' \
        "$MARKER_START" "$MARKER_END" "$MARKER_END" >"$marker_home/.tmux.conf"
      ;;
    reversed)
      printf '%s\nkeep this line\n%s\n' "$MARKER_END" "$MARKER_START" >"$marker_home/.tmux.conf"
      ;;
  esac
  cp -- "$marker_home/.tmux.conf" "$TEST_TMP/marker-$marker_case-before"

  if HOME="$marker_home" bash "$ROOT_DIR/install.sh" --skip-deps --skip-connect \
    >"$TEST_TMP/marker-$marker_case-install.out" \
    2>"$TEST_TMP/marker-$marker_case-install.err"; then
    fail "installer accepted malformed markers: $marker_case"
  fi
  cmp -s "$TEST_TMP/marker-$marker_case-before" "$marker_home/.tmux.conf" ||
    fail "installer changed malformed tmux config: $marker_case"
  [[ ! -e "$marker_home/.local/bin/codex-mobile" ]] ||
    fail "installer detected malformed markers after installing files: $marker_case"
  grep -Fq 'Repair the marker block manually' "$TEST_TMP/marker-$marker_case-install.err" ||
    fail "installer did not explain marker repair: $marker_case"

  mkdir -p -- "$marker_home/.local/bin"
  printf 'keep launcher\n' >"$marker_home/.local/bin/codex-mobile"
  if HOME="$marker_home" bash "$ROOT_DIR/uninstall.sh" \
    >"$TEST_TMP/marker-$marker_case-uninstall.out" \
    2>"$TEST_TMP/marker-$marker_case-uninstall.err"; then
    fail "uninstaller accepted malformed markers: $marker_case"
  fi
  cmp -s "$TEST_TMP/marker-$marker_case-before" "$marker_home/.tmux.conf" ||
    fail "uninstaller changed malformed tmux config: $marker_case"
  [[ -e "$marker_home/.local/bin/codex-mobile" ]] ||
    fail "uninstaller removed files before validating markers: $marker_case"
  grep -Fq 'Repair the marker block manually' "$TEST_TMP/marker-$marker_case-uninstall.err" ||
    fail "uninstaller did not explain marker repair: $marker_case"
done

printf 'PASS: install, idempotency, validation, markers, version, and uninstall\n'
