#!/usr/bin/env bash

set -Eeuo pipefail

readonly TMUX_MARKER_START="# >>> codex-mobile >>>"
readonly TMUX_MARKER_END="# <<< codex-mobile <<<"

disable_tailscale_ssh=false
dry_run=false

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [OPTIONS]

Remove codex-mobile files for the current user.

Options:
      --disable-tailscale-ssh  Also run: sudo tailscale set --ssh=false
      --dry-run                Show what would be removed
  -h, --help                   Show this help

This does not uninstall packages, leave your tailnet, stop Tailscale, or remove
entries from ~/.ssh/authorized_keys.
EOF
}

die() {
  printf 'uninstall: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --disable-tailscale-ssh)
      disable_tailscale_ssh=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if ((EUID == 0)) && [[ -z "${CODEX_MOBILE_ALLOW_ROOT:-}" ]]; then
  die "run this uninstaller as your normal user, not root"
fi

readonly BIN_DIR="${CODEX_MOBILE_BIN_DIR:-$HOME/.local/bin}"
readonly CONFIG_DIR="${CODEX_MOBILE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/codex-mobile}"
readonly TMUX_FILE="${CODEX_MOBILE_TMUX_FILE:-$HOME/.tmux.conf}"

validate_tmux_markers() {
  [[ -f "$TMUX_FILE" ]] || return 0

  local end_count end_line reason start_count start_line
  read -r start_count end_count start_line end_line < <(
    awk -v start="$TMUX_MARKER_START" -v end="$TMUX_MARKER_END" '
      $0 == start { start_count++; if (!start_line) start_line = NR }
      $0 == end { end_count++; if (!end_line) end_line = NR }
      END { print start_count + 0, end_count + 0, start_line + 0, end_line + 0 }
    ' "$TMUX_FILE"
  )

  if [[ "$start_count" == 0 && "$end_count" == 0 ]]; then
    return 0
  elif [[ "$start_count" == 0 ]]; then
    reason="an end marker exists without a start marker"
  elif [[ "$end_count" == 0 ]]; then
    reason="a start marker exists without an end marker"
  elif [[ "$start_count" != 1 ]]; then
    reason="$start_count start markers exist; exactly one is required"
  elif [[ "$end_count" != 1 ]]; then
    reason="$end_count end markers exist; exactly one is required"
  elif ((start_line >= end_line)); then
    reason="the end marker appears before the start marker"
  else
    return 0
  fi

  die "the codex-mobile block in $TMUX_FILE is malformed: $reason. Repair the marker block manually, then rerun the uninstaller"
}

validate_tmux_markers

remove_file() {
  if [[ -e "$1" || -L "$1" ]]; then
    if [[ "$dry_run" == true ]]; then
      printf 'Would remove %s\n' "$1"
    else
      rm -f -- "$1"
      printf 'Removed %s\n' "$1"
    fi
  fi
}

remove_tmux_source() {
  [[ -f "$TMUX_FILE" ]] || return 0
  grep -Fqx "$TMUX_MARKER_START" "$TMUX_FILE" || return 0

  if [[ "$dry_run" == true ]]; then
    printf 'Would remove the codex-mobile block from %s\n' "$TMUX_FILE"
    return
  fi

  local temp_file
  temp_file="$(mktemp "${TMUX_FILE}.XXXXXX")"
  awk -v start="$TMUX_MARKER_START" -v end="$TMUX_MARKER_END" '
    $0 == start { skipping = 1; next }
    $0 == end && skipping { skipping = 0; next }
    !skipping { print }
  ' "$TMUX_FILE" >"$temp_file"
  chmod --reference="$TMUX_FILE" "$temp_file" 2>/dev/null || true
  mv -- "$temp_file" "$TMUX_FILE"
  printf 'Removed tmux include from %s\n' "$TMUX_FILE"
}

remove_file "$BIN_DIR/codex-mobile"
remove_file "$BIN_DIR/codex-mobile-add-key"
remove_file "$CONFIG_DIR/tmux.conf"
remove_tmux_source

if [[ -d "$CONFIG_DIR" ]]; then
  if [[ "$dry_run" == true ]]; then
    printf 'Would remove %s if empty\n' "$CONFIG_DIR"
  else
    rmdir -- "$CONFIG_DIR" 2>/dev/null || true
  fi
fi

if [[ "$disable_tailscale_ssh" == true ]]; then
  if [[ "$dry_run" == true ]]; then
    printf 'Would run: sudo tailscale set --ssh=false\n'
  elif command -v tailscale >/dev/null 2>&1; then
    sudo tailscale set --ssh=false
  else
    printf 'Tailscale is not installed; SSH mode was not changed.\n' >&2
  fi
fi

cat <<'EOF'

codex-mobile is uninstalled. Tailscale, tmux, Codex, and authorized SSH keys
were left alone so other workflows keep working.
EOF
