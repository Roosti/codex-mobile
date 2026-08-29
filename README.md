# codex-mobile

[![CI](https://github.com/Roosti/codex-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/Roosti/codex-mobile/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-111827.svg)](LICENSE)

This is a micro-project made out of spite; my University provides Codex and workspace but not remote access.
Glory to my workaround.

> Run a Codex CLI session on your Linux computer and reconnect to it from your phone.

codex-mobile combines Tailscale, SSH, and tmux. Your phone connects privately to
your computer; tmux keeps Codex running when the phone loses Wi-Fi, locks, or
switches apps.

This is a community project. It is not OpenAI Remote and is not affiliated with
OpenAI or Tailscale. If your computer supports the official experience, see
[Codex Remote connections](https://learn.chatgpt.com/docs/remote-connections).

## What you need

- A Linux computer with the [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
  installed and signed in.
- A Tailscale account shared by your computer and phone.
- An SSH app on your phone. Termius works well on iPhone; Termux works well on
  Android.

The installer supports Arch, Debian/Ubuntu, and Fedora/RHEL-family systems.

## Install on your Linux computer

```bash
git clone https://github.com/Roosti/codex-mobile.git
cd codex-mobile
./install.sh
```

The installer puts the launchers in `~/.local/bin`, adds a small tmux include,
installs missing host packages, starts Tailscale, and enables Tailscale SSH. It
may ask for `sudo` and open a Tailscale sign-in URL.

By default, authentication uses Tailscale SSH. No SSH password or private key
is needed. Your tailnet policy still controls who can connect; review the
[security guide](docs/security.md).

## Connect from your phone

1. Install Tailscale on your phone and sign in to the same tailnet.
2. Open your SSH app.
3. Connect to your computer's Tailscale hostname on port `22` using your Linux
   username. Leave password and key fields empty for Tailscale SSH mode.
4. Start or reconnect to Codex:

   ```bash
   codex-mobile ~/path/to/project
   ```

Read the platform guide for exact app settings:

- [iPhone and iPad setup](docs/ios.md)
- [Android setup](docs/android.md)

## Everyday use

```bash
codex-mobile                         # start or reconnect to the default session
codex-mobile ~/code/my-app           # start in a project directory
codex-mobile -s api ~/code/api       # use a named session
codex-mobile --list                  # list running sessions
codex-mobile --stop                  # stop the default session
codex-mobile -s api --stop           # stop a named session
```

Inside tmux, press `Ctrl-b`, then `d` to disconnect without stopping Codex.
Run the same command later to reconnect.

Each session records the project directory it was created for. Reusing that
session with an explicitly different directory is refused instead of opening
the wrong project; use `-s NAME` for another project. Omitting the directory
reconnects the selected session from any current directory. When run from
inside tmux, the launcher switches the current client to the requested session
rather than starting Codex in the current window or nesting tmux.

Pass Codex options after `--` when creating a session:

```bash
codex-mobile ~/code/my-app -- --search
```

## Authentication modes

| Mode | How it authenticates | Use it when |
| --- | --- | --- |
| `tailscale` (default) | Tailnet identity and policy | You want the simplest setup |
| `key` | Tailnet access plus an SSH public key | You want standard OpenSSH |

Key mode requires one valid OpenSSH public key file. It enables the system
OpenSSH service, which may listen on LAN or public interfaces depending on the
machine's sshd configuration. The installer does not change firewall rules,
disable password authentication, or rewrite global sshd configuration. Read
[SSH key mode](docs/ssh-key-mode.md) before running:

```bash
./install.sh --mode key --key-file phone.pub
```

The public key is validated before installation or SSH/Tailscale changes.

## Installer options

```text
--mode tailscale   use Tailscale SSH (recommended)
--mode key         use standard OpenSSH public-key authentication
--key-file FILE    required public key when using --mode key
--skip-deps        skip the system package manager
--skip-connect     install files without changing services or SSH mode
--dry-run          print privileged setup commands without running them
```

If you install Tailscale yourself, follow the [official Linux guide](https://tailscale.com/docs/install/linux),
then run `./install.sh --skip-deps`.

`VERSION` is the release version source. Installation stamps it into the
launcher, so `codex-mobile --version` does not depend on the source checkout.

## Uninstall

```bash
./uninstall.sh
```

This removes the launcher and tmux include. It keeps installed packages,
Tailscale membership, Codex data, and authorized SSH keys.

To also disable Tailscale SSH on the computer:

```bash
./uninstall.sh --disable-tailscale-ssh
```

## More documentation

- [Security and threat model](docs/security.md)
- [SSH key mode](docs/ssh-key-mode.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Contributing](CONTRIBUTING.md)

## License

MIT © 2026 Roosti
