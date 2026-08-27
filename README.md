# codex-mobile

[![CI](https://github.com/Rooosti/codex-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/Rooosti/codex-mobile/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-111827.svg)](LICENSE)

Your Codex terminal, from your phone.

`codex-mobile` combines a private Tailscale connection, SSH, and tmux so a Codex
CLI session on your Linux PC survives flaky Wi-Fi, app switching, and a locked
phone.

```text
iPhone / Android            private tailnet             Linux PC
Tailscale + SSH app  ─────────────────────────▶  SSH → tmux → Codex CLI
```

This is a small community project—not OpenAI Remote, and not affiliated with
OpenAI or Tailscale. If your computer supports the official experience, see
[Codex Remote connections](https://learn.chatgpt.com/docs/remote-connections).

## Why

- Persistent sessions: disconnect whenever; Codex keeps running in tmux.
- No public SSH port or router setup in the recommended mode.
- Tailscale SSH identity by default; no static SSH password or private key.
- Optional standard OpenSSH + Ed25519 key mode.
- Friendly defaults for Kitty, 256-color mobile terminals, and scrollback.
- Arch, Debian/Ubuntu, and Fedora/RHEL-family installers.
- Leaves Kitty and Hyprland configuration completely alone.

## Quick start

First, install and sign in to the
[Codex CLI](https://learn.chatgpt.com/docs/codex/cli) on the Linux host. Then:

```bash
git clone https://github.com/Rooosti/codex-mobile.git
cd codex-mobile
./install.sh
```

The installer adds `codex-mobile` to `~/.local/bin`, installs a small tmux
include, installs missing host packages, starts Tailscale, and enables
Tailscale SSH. It may ask for sudo and open a Tailscale sign-in URL.

On your phone:

1. Install Tailscale and sign in with the same identity as the PC.
2. Install an SSH client. **Termius** is the easiest iOS option; Termux is great
   on Android.
3. Connect to your PC's Tailscale hostname on port `22` with your Linux
   username. Leave password and key empty in Tailscale SSH mode.
4. Run:

```bash
codex-mobile ~/path/to/project
```

Read the exact [iPhone/iPad setup](docs/ios.md) or
[Android setup](docs/android.md).

## Everyday commands

```bash
codex-mobile                         # start here or reconnect
codex-mobile ~/code/my-app           # start inside a project
codex-mobile -s api ~/code/api       # use another named session
codex-mobile --list                  # see sessions
codex-mobile --stop                  # stop the default session
codex-mobile -s api --stop           # stop a named session
```

Inside tmux, press `Ctrl-b`, then `d` to detach without stopping Codex. Run the
same `codex-mobile` command later to reconnect.

Codex options can follow `--` when creating a new session:

```bash
codex-mobile ~/code/my-app -- --full-auto
```

## Authentication modes

| Mode | Authentication | Best for | Setup |
| --- | --- | --- | --- |
| `tailscale` | Tailnet identity + policy | Most people | `./install.sh` |
| `key` | Tailnet access + SSH public key | People who want a normal sshd | `./install.sh --mode key --key-file phone.pub` |

Tailscale SSH does not mean everyone with Tailscale can log in. Your tailnet
policy decides which identity, source device, destination, and Linux user are
allowed. New personal tailnets commonly use a conservative self-device rule,
but you should still review the [security guide](docs/security.md).

Key mode disables Tailscale SSH on the host because Tailscale otherwise
intercepts port 22 on its own address. It then enables the OS OpenSSH service.
Read [SSH key mode](docs/ssh-key-mode.md) before using it.

## Installer options

```text
--mode tailscale   recommended Tailscale SSH mode
--mode key         standard OpenSSH public-key mode
--key-file FILE    add one phone public key
--skip-deps        do not use the system package manager
--skip-connect     install files only; do not touch services or SSH mode
--dry-run          show privileged setup commands
```

The Debian and Fedora paths use Tailscale's official Linux install script when
Tailscale is missing. If you prefer to install packages yourself, follow the
[official Tailscale Linux guide](https://tailscale.com/docs/install/linux) and
run `./install.sh --skip-deps`.

## Uninstall

```bash
./uninstall.sh
```

This removes the launcher and tmux include. It deliberately keeps packages,
your tailnet membership, Codex data, and authorized SSH keys. To also turn off
Tailscale SSH on the host:

```bash
./uninstall.sh --disable-tailscale-ssh
```

## Docs

- [iOS setup](docs/ios.md)
- [Android setup](docs/android.md)
- [Threat model and security](docs/security.md)
- [Optional SSH key mode](docs/ssh-key-mode.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Contributing](CONTRIBUTING.md)

## License

MIT © 2026 Rooosti
