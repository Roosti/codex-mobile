#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly ROOT_DIR
readonly ADD_KEY="$ROOT_DIR/bin/codex-mobile-add-key"
TEST_TMP="$(mktemp -d)"
readonly TEST_TMP
trap 'rm -rf -- "$TEST_TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if ! command -v ssh-keygen >/dev/null 2>&1; then
  printf 'SKIP: authorized_keys tests require ssh-keygen\n'
  exit 0
fi

ssh-keygen -q -t ed25519 -N '' -C 'original comment' -f "$TEST_TMP/phone-key"
ssh-keygen -q -t ed25519 -N '' -C 'unrelated comment' -f "$TEST_TMP/other-key"
read -r key_type key_blob _ <"$TEST_TMP/phone-key.pub"
read -r other_type other_blob _ <"$TEST_TMP/other-key.pub"

# A plain key without a comment is accepted and installed unchanged.
plain_home="$TEST_TMP/plain-home"
mkdir -p -- "$plain_home"
printf '%s %s\n' "$key_type" "$key_blob" >"$TEST_TMP/plain.pub"
HOME="$plain_home" "$ADD_KEY" "$TEST_TMP/plain.pub" >/dev/null
[[ "$(<"$plain_home/.ssh/authorized_keys")" == "$key_type $key_blob" ]] ||
  fail "plain key was not installed unchanged"

# Reinstalling the same blob with another comment does not append or rewrite it.
comment_home="$TEST_TMP/comment-home"
mkdir -p -- "$comment_home"
HOME="$comment_home" "$ADD_KEY" "$TEST_TMP/phone-key.pub" >/dev/null
cp -- "$comment_home/.ssh/authorized_keys" "$TEST_TMP/comment-before"
printf '%s %s %s\n' "$key_type" "$key_blob" 'different comment' >"$TEST_TMP/different-comment.pub"
HOME="$comment_home" "$ADD_KEY" "$TEST_TMP/different-comment.pub" >/dev/null
cmp -s "$TEST_TMP/comment-before" "$comment_home/.ssh/authorized_keys" ||
  fail "duplicate key with a different comment changed authorized_keys"

# A restricted authorized_keys entry counts as the same key and remains intact.
restricted_home="$TEST_TMP/restricted-home"
mkdir -p -- "$restricted_home/.ssh"
printf 'restrict,command="printf hello world" %s %s existing restrictions\n' \
  "$key_type" "$key_blob" >"$restricted_home/.ssh/authorized_keys"
cp -- "$restricted_home/.ssh/authorized_keys" "$TEST_TMP/restricted-before"
HOME="$restricted_home" "$ADD_KEY" "$TEST_TMP/phone-key.pub" >/dev/null
cmp -s "$TEST_TMP/restricted-before" "$restricted_home/.ssh/authorized_keys" ||
  fail "restricted duplicate key was appended or rewritten"

# Commented-out key text is inactive and must not suppress installation.
commented_home="$TEST_TMP/commented-home"
mkdir -p -- "$commented_home/.ssh"
printf '# disabled %s %s old comment\n' "$key_type" "$key_blob" \
  >"$commented_home/.ssh/authorized_keys"
HOME="$commented_home" "$ADD_KEY" "$TEST_TMP/phone-key.pub" >/dev/null
commented_lines="$(awk 'END { print NR }' "$commented_home/.ssh/authorized_keys")"
[[ "$commented_lines" == 2 ]] || fail "commented-out key was treated as authorized"

# Key-like words inside a quoted option are not an active key field.
quoted_option_home="$TEST_TMP/quoted-option-home"
mkdir -p -- "$quoted_option_home/.ssh"
printf 'restrict,command="echo %s %s " %s %s active unrelated key\n' \
  "$key_type" "$key_blob" "$other_type" "$other_blob" \
  >"$quoted_option_home/.ssh/authorized_keys"
HOME="$quoted_option_home" "$ADD_KEY" "$TEST_TMP/phone-key.pub" >/dev/null
quoted_lines="$(awk 'END { print NR }' "$quoted_option_home/.ssh/authorized_keys")"
[[ "$quoted_lines" == 2 ]] || fail "key-like text inside an option caused a false duplicate"

# Key-like text in an active key's trailing comment is not another active key.
trailing_comment_home="$TEST_TMP/trailing-comment-home"
mkdir -p -- "$trailing_comment_home/.ssh"
printf '%s %s comment mentions %s %s\n' \
  "$other_type" "$other_blob" "$key_type" "$key_blob" \
  >"$trailing_comment_home/.ssh/authorized_keys"
HOME="$trailing_comment_home" "$ADD_KEY" "$TEST_TMP/phone-key.pub" >/dev/null
trailing_lines="$(awk 'END { print NR }' "$trailing_comment_home/.ssh/authorized_keys")"
[[ "$trailing_lines" == 2 ]] || fail "key-like text in a comment caused a false duplicate"

# An unrelated key does not prevent the requested key from being appended.
unrelated_home="$TEST_TMP/unrelated-home"
mkdir -p -- "$unrelated_home/.ssh"
printf '%s %s unrelated comment\n' "$other_type" "$other_blob" \
  >"$unrelated_home/.ssh/authorized_keys"
HOME="$unrelated_home" "$ADD_KEY" "$TEST_TMP/phone-key.pub" >/dev/null
line_count="$(awk 'END { print NR }' "$unrelated_home/.ssh/authorized_keys")"
[[ "$line_count" == 2 ]] || fail "requested key was not appended after an unrelated key"
awk -v blob="$key_blob" '
  { for (i = 1; i < NF; i++) if ($i == blob) found = 1 }
  END { exit !found }
' "$unrelated_home/.ssh/authorized_keys" || fail "requested key blob is missing"

printf 'PASS: public key validation and authorized_keys deduplication\n'
