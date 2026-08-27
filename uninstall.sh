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
  [[ -f "$TMUX_FILE" ]] || return
  grep -Fqx "$TMUX_MARKER_START" "$TMUX_FILE" || return

  local start_count end_count
  start_count="$(grep -Fxc "$TMUX_MARKER_START" "$TMUX_FILE")"
  end_count="$(grep -Fxc "$TMUX_MARKER_END" "$TMUX_FILE" || true)"
  if [[ "$start_count" != 1 || "$end_count" != 1 ]]; then
    printf 'Preserved %s: the codex-mobile marker block is malformed.\n' "$TMUX_FILE" >&2
    return
  fi

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
