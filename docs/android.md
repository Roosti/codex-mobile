# Android setup

## Recommended apps

1. Install [Tailscale for Android](https://tailscale.com/docs/install/android)
   and sign in with the same identity as the Linux PC.
2. Use either:

   - **Termux**, for a real local terminal and OpenSSH client. The upstream
     project recommends its stable F-Droid/GitHub builds; its Play Store branch
     has different limitations.
   - **Termius**, for a simpler graphical host list.

For Termux installation details, use the
[official Termux repository](https://github.com/termux/termux-app#installation).

## Connect from Termux

```bash
pkg update
pkg install openssh
ssh your-linux-user@your-pc-hostname
```

The hostname is the PC's MagicDNS name shown in Tailscale. Its `100.x.y.z`
Tailscale IP also works.

In Tailscale SSH mode, the connection does not need a password or private key.
If a browser check appears, approve it using the same tailnet identity.

Then start Codex:

```bash
codex-mobile ~/code/your-project
```

Detach with `Ctrl-b`, then `d`. Android may suspend the SSH app, but tmux keeps
the host-side session alive.

## Connect from Termius

Create a host with the PC's MagicDNS name, port `22`, and your Linux username.
Leave password and key blank for Tailscale SSH. For standard key mode, attach
the matching private key and follow [SSH key mode](ssh-key-mode.md).
