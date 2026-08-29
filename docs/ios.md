# iPhone and iPad setup

## Recommended apps

- [Tailscale for iOS](https://tailscale.com/docs/install/ios) creates the
  private connection to your Linux PC.
- [Termius for iOS](https://termius.com/download/ios) is an easy general SSH
  client for this setup.

Blink Shell is also solid if you already own it. The SSH app does not need to
match Kitty; tmux handles the terminal session on the PC.

## Connect with Tailscale SSH

1. Open Tailscale on the iPhone, sign in with the same identity used on the PC,
   approve the VPN profile, and switch Tailscale on.
2. In the Tailscale device list, find the Linux PC. Copy its MagicDNS name or
   `100.x.y.z` Tailscale address.
3. In Termius, create a host with:

   - Address: the MagicDNS name or Tailscale IP
   - Port: `22`
   - Username: your Linux username
   - Password: empty
   - Key: none

4. Connect. Tailscale may open a browser check the first time or after the
   policy's check period expires.
5. Start or reconnect to Codex:

```bash
codex-mobile ~/code/your-project
```

No SSH password is expected in this mode. Tailscale already authenticated the
phone's node identity and the tailnet policy authorizes the Linux username.

## tmux controls on a phone

- Detach: `Ctrl-b`, release, then `d`
- Scroll: swipe or use the terminal's mouse/scroll mode
- Reconnect: run `codex-mobile` again
- Stop the session: `codex-mobile --stop`

Use `codex-mobile -s NAME /path/to/project` for multiple projects. Each name
remains associated with the directory where its session was created.

If Termius has a modifier-key row, use its `Ctrl` key. `Ctrl-b` is two keys at
once, followed by a separate `d`.

## Optional SSH-key mode

Generate an Ed25519 key inside your SSH app and export **only the public key**.
Move that `.pub` file to the PC through a trusted channel, then run:

```bash
codex-mobile-add-key ~/Downloads/iphone_ed25519.pub
```

Assign the matching private key to the Termius host. Never send, paste, or
commit the private key. See [SSH key mode](ssh-key-mode.md) for host hardening.

## Mobile reality check

iOS can suspend background apps. That may drop SSH, but tmux is the point: the
Codex process remains on the PC. Reopen Termius and reconnect.
