#!/usr/bin/env bash

set -Eeuo pipefail

readonly TAILSCALE_INSTALL_URL="https://tailscale.com/install.sh"
readonly TMUX_MARKER_START="# >>> codex-mobile >>>"
readonly TMUX_MARKER_END="# <<< codex-mobile <<<"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly VERSION_FILE="$SCRIPT_DIR/VERSION"

if ! IFS= read -r VERSION <"$VERSION_FILE" || [[ -z "$VERSION" ]]; then
  printf 'install: cannot read project version from %s\n' "$VERSION_FILE" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.+-]+)?$ ]]; then
  printf 'install: invalid version in %s: %s\n' "$VERSION_FILE" "$VERSION" >&2
  exit 1
fi
readonly VERSION
readonly LAUNCHER_VERSION_TEMPLATE='CODEX_MOBILE_VERSION="__CODEX_MOBILE_VERSION__"'

mode="tailscale"
key_file=""
skip_deps=false
skip_connect=false
dry_run=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Install codex-mobile for the current Linux user.

Options:
      --mode tailscale  Use Tailscale SSH identity (default, recommended)
      --mode key        Use OpenSSH over Tailscale with a public key
      --key-file FILE   Required public key when using --mode key
      --skip-deps       Do not install tmux, Tailscale, or OpenSSH packages
      --skip-connect    Do not start services, log in, or change SSH mode
      --dry-run         Print privileged setup commands without running them
  -h, --help            Show this help

Supported package families: Arch, Debian/Ubuntu, Fedora/RHEL.
Run this script as your normal user; it asks for sudo only when needed.
Key mode may expose OpenSSH on non-Tailscale interfaces; review sshd first.
EOF
}

die() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '\n==> %s\n' "$*"
}

print_command() {
  printf '  +'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  if [[ "$dry_run" == true ]]; then
    print_command "$@"
  else
    "$@"
  fi
}

run_root() {
  if [[ "$dry_run" == true ]]; then
    if ((EUID == 0)); then
      print_command "$@"
    else
      print_command sudo "$@"
    fi
    return
  fi

  if ((EUID == 0)); then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required for system setup"
    sudo "$@"
  fi
}

launcher_template_count="$(
  awk -v template="$LAUNCHER_VERSION_TEMPLATE" '
    $0 == template { count++ }
    END { print count + 0 }
  ' "$SCRIPT_DIR/bin/codex-mobile"
)"
[[ "$launcher_template_count" == 1 ]] ||
  die "launcher template must contain exactly one version placeholder; found $launcher_template_count"
readonly launcher_template_count

while (($# > 0)); do
  case "$1" in
    --mode)
      (($# >= 2)) || die "--mode needs tailscale or key"
      mode="$2"
      shift 2
      ;;
    --key-file)
      (($# >= 2)) || die "--key-file needs a path"
      key_file="$2"
      shift 2
      ;;
    --skip-deps)
      skip_deps=true
      shift
      ;;
    --skip-connect)
      skip_connect=true
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

[[ "$mode" == "tailscale" || "$mode" == "key" ]] || die "--mode must be tailscale or key"
[[ "$mode" == "key" || -z "$key_file" ]] || die "--key-file only works with --mode key"

if [[ "$mode" == "key" ]]; then
  [[ -n "$key_file" ]] || die "--mode key requires --key-file PUBLIC_KEY_FILE"
  [[ -f "$key_file" ]] || die "public key file does not exist: $key_file"
  "$SCRIPT_DIR/bin/codex-mobile-add-key" --check "$key_file"
  cat >&2 <<'EOF'

WARNING: OpenSSH key mode changes SSH exposure.
The OpenSSH server may listen on non-Tailscale interfaces, depending on this
machine's sshd configuration. codex-mobile does not change firewall rules,
disable password authentication, or rewrite global sshd configuration.

EOF
fi

[[ "$(uname -s)" == "Linux" ]] || die "the host installer currently supports Linux only"

if ((EUID == 0)) && [[ -z "${CODEX_MOBILE_ALLOW_ROOT:-}" ]]; then
  die "run this installer as your normal user, not root"
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

  die "the codex-mobile block in $TMUX_FILE is malformed: $reason. Repair the marker block manually, then rerun the installer"
}

validate_tmux_markers

distro_family=""
distro_tokens=""

if [[ -r /etc/os-release ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      ID|ID_LIKE)
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        distro_tokens+=" $value "
        ;;
    esac
  done </etc/os-release

  case "$distro_tokens" in
    *" arch "*)
      distro_family="arch"
      ;;
    *" debian "*|*" ubuntu "*)
      distro_family="debian"
      ;;
    *" fedora "*|*" rhel "*|*" centos "*)
      distro_family="fedora"
      ;;
  esac
fi
install_tailscale_official() {
  if command -v tailscale >/dev/null 2>&1; then
    return
  fi

  note "Installing Tailscale from its official Linux installer"
  if [[ "$dry_run" == true ]]; then
    print_command curl --proto =https --tlsv1.2 -fsSL "$TAILSCALE_INSTALL_URL" -o /tmp/tailscale-install.sh
    print_command sudo sh /tmp/tailscale-install.sh
    return
  fi

  local download_dir installer
  download_dir="$(mktemp -d)"
  installer="$download_dir/install.sh"
  curl --proto '=https' --tlsv1.2 -fsSL "$TAILSCALE_INSTALL_URL" -o "$installer"
  run_root sh "$installer"
  rm -rf -- "$download_dir"
}

install_dependencies() {
  local -a packages

  [[ -n "$distro_family" ]] ||
    die "unsupported distro; install Codex, tmux, and Tailscale manually, then rerun with --skip-deps"

  note "Installing host dependencies ($distro_family)"
  case "$distro_family" in
    arch)
      packages=(tmux tailscale)
      [[ "$mode" == "key" ]] && packages+=(openssh)
      run_root pacman -S --needed --noconfirm "${packages[@]}"
      ;;
    debian)
      packages=(tmux curl ca-certificates)
      [[ "$mode" == "key" ]] && packages+=(openssh-server)
      run_root apt-get update
      run_root apt-get install -y "${packages[@]}"
      install_tailscale_official
      ;;
    fedora)
      packages=(tmux curl ca-certificates)
      [[ "$mode" == "key" ]] && packages+=(openssh-server)
      run_root dnf install -y "${packages[@]}"
      install_tailscale_official
      ;;
  esac
}

append_tmux_source() {
  local tmux_source

  if [[ "$dry_run" == true ]]; then
    printf '  + add codex-mobile source block to %s\n' "$TMUX_FILE"
    return
  fi

  mkdir -p -- "$(dirname -- "$TMUX_FILE")"
  touch -- "$TMUX_FILE"

  if grep -Fqx "$TMUX_MARKER_START" "$TMUX_FILE"; then
    return
  fi

  tmux_source="$CONFIG_DIR/tmux.conf"
  tmux_source="${tmux_source//\\/\\\\}"
  tmux_source="${tmux_source//\"/\\\"}"
  if [[ -s "$TMUX_FILE" ]]; then
    printf '\n' >>"$TMUX_FILE"
  fi
  printf '%s\nsource-file "%s"\n%s\n' \
    "$TMUX_MARKER_START" "$tmux_source" "$TMUX_MARKER_END" >>"$TMUX_FILE"
}

install_launcher() {
  if [[ "$dry_run" == true ]]; then
    printf '  + install version %q in %s\n' "$VERSION" "$BIN_DIR/codex-mobile"
    return
  fi

  local temp_launcher
  temp_launcher="$(mktemp "$BIN_DIR/.codex-mobile.XXXXXX")"
  awk -v template="$LAUNCHER_VERSION_TEMPLATE" -v version="$VERSION" '
    $0 == template {
      print "CODEX_MOBILE_VERSION=\"" version "\""
      next
    }
    { print }
  ' "$SCRIPT_DIR/bin/codex-mobile" >"$temp_launcher"
  chmod 0755 -- "$temp_launcher"
  mv -- "$temp_launcher" "$BIN_DIR/codex-mobile"
}

tailscale_is_running() {
  command -v tailscale >/dev/null 2>&1 &&
    tailscale status --json 2>/dev/null |
      grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'
}

enable_tailscaled() {
  if command -v systemctl >/dev/null 2>&1; then
    run_root systemctl enable --now tailscaled.service
  else
    run_root service tailscaled start
  fi
}

enable_openssh() {
  if ! command -v systemctl >/dev/null 2>&1; then
    run_root service ssh start
    return
  fi

  case "$distro_family" in
    debian)
      run_root systemctl enable --now ssh.service
      ;;
    *)
      run_root systemctl enable --now sshd.service
      ;;
  esac
}

configure_connection() {
  note "Connecting the host to Tailscale"
  enable_tailscaled

  if [[ "$dry_run" == true ]] || ! tailscale_is_running; then
    run_root tailscale up
  fi

  if [[ "$mode" == "tailscale" ]]; then
    run_root tailscale set --ssh
  else
    # Tailscale SSH intercepts port 22 on the Tailscale address, so standard
    # public-key auth needs it disabled on this host.
    run_root tailscale set --ssh=false
    enable_openssh
  fi
}

if [[ "$skip_deps" == false ]]; then
  install_dependencies
fi

note "Installing codex-mobile $VERSION"
run install -d -m 0755 "$BIN_DIR" "$CONFIG_DIR"
install_launcher
run install -m 0755 "$SCRIPT_DIR/bin/codex-mobile-add-key" "$BIN_DIR/codex-mobile-add-key"
run install -m 0644 "$SCRIPT_DIR/config/tmux.conf" "$CONFIG_DIR/tmux.conf"
append_tmux_source

if [[ -n "$key_file" ]]; then
  if [[ "$dry_run" == true ]]; then
    print_command "$BIN_DIR/codex-mobile-add-key" "$key_file"
  else
    "$BIN_DIR/codex-mobile-add-key" "$key_file"
  fi
fi

if [[ "$skip_connect" == false ]]; then
  configure_connection
fi

if ! command -v codex >/dev/null 2>&1; then
  printf '\nWarning: Codex CLI is not on PATH yet. Install and sign in on the host first.\n' >&2
fi

login_user="${USER:-$(id -un)}"

cat <<EOF

Done. Open your mobile SSH terminal and connect with:

  ssh $login_user@<Tailscale-hostname-or-IP>
  codex-mobile /path/to/project

Detach with Ctrl-b, then d. Reconnect by running codex-mobile again.
EOF

if [[ "$mode" == "tailscale" ]]; then
  printf '\nAuth mode: Tailscale SSH. Your tailnet policy decides who can connect.\n'
else
  cat <<'EOF'

Auth mode: OpenSSH key over Tailscale.
OpenSSH may also listen on non-Tailscale interfaces; review your firewall and
sshd settings. Password login is not disabled automatically.
EOF
  if [[ -z "$key_file" ]]; then
    printf '\nAdd your phone\x27s public key next: codex-mobile-add-key key.pub\n'
  fi
fi

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  printf '\nAdd %s to PATH in your shell config.\n' "$BIN_DIR"
fi
