# Troubleshooting

## The phone cannot reach the PC

On both devices, verify Tailscale is on and shows the other device. On Linux:

```bash
tailscale status
tailscale ip -4
systemctl status tailscaled
```

Try the `100.x.y.z` address if MagicDNS is not resolving. Never port-forward
22 on your router for this project.

## SSH says permission denied

For Tailscale SSH, check all three:

```bash
sudo tailscale set --ssh
tailscale status
```

- The phone and PC are authorized in the intended tailnet.
- Network access policy allows TCP 22 between them.
- An SSH policy permits the source, destination, and requested Linux username.

The [Tailscale SSH guide](https://tailscale.com/docs/features/tailscale-ssh)
explains both required policy layers. A blank SSH password is normal in this
mode; adding a random password will not fix policy.

In key mode, confirm the matching public key is present and permissions are:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

## `codex-mobile: Codex is not available on PATH`

Log in on the PC directly and verify:

```bash
command -v codex
codex --version
```

Make sure the same PATH setup is loaded by an interactive SSH shell. A common
user install location is `~/.local/bin`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that to the startup file used by your login shell, then reconnect. Follow
the [official Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli) if the
CLI is not installed or signed in yet.

## It opens the wrong project

The default named session persists, including its original working directory.
Stop it or choose another name:

```bash
codex-mobile --stop
codex-mobile -s other ~/code/other
```

Options passed after `--` only apply while a new session is created.

## Colors look wrong

Check that the host has the tmux terminfo entry:

```bash
infocmp tmux-256color
tmux show -g default-terminal
```

The included config advertises RGB for `xterm-kitty` and `xterm-256color`.
Kitty and Hyprland do not need any changes. On a very old distro without
`tmux-256color`, change the first config line to `screen-256color`.

## `sessions should be nested with care`

The launcher avoids nesting when it detects `$TMUX`. If you manually run
`tmux attach` inside tmux, use `tmux switch-client -t SESSION` instead, or
detach the outer client first.

## My phone disconnected and Codex vanished

List sessions on the host:

```bash
codex-mobile --list
tmux list-sessions
```

If no session exists, Codex likely exited rather than merely losing SSH. Start
again and inspect the last terminal output before detaching.
