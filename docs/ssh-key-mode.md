# Standard SSH-key mode

Use this only if you specifically want OpenSSH public-key authentication.
Tailscale SSH is simpler and is the default.

## Set it up

Generate an Ed25519 key in the mobile SSH app. Move only its `.pub` public-key
file to the host, then run:

```bash
./install.sh --mode key --key-file ~/Downloads/phone_ed25519.pub
```

This installs/enables the system OpenSSH server, adds the public key to the
current user's `~/.ssh/authorized_keys`, joins Tailscale if needed, and disables
Tailscale SSH interception on the host. It never copies or reads the phone's
private key.

To add another phone later:

```bash
codex-mobile-add-key another-phone.pub
```

Connect to the Tailscale hostname or IP, not a public address:

```bash
ssh -i ~/.ssh/phone_ed25519 your-user@your-pc-hostname
```

## Harden OpenSSH

OpenSSH may listen on LAN/public interfaces in addition to Tailscale. Confirm
that your router does not forward port 22 and use host firewall rules if you
need tailnet-only reachability.

After verifying key login in a second terminal, consider this sshd drop-in:

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

Put it in `/etc/ssh/sshd_config.d/90-codex-mobile.conf`, validate before
restarting, and keep an existing recovery session open:

```bash
sudo sshd -t
sudo systemctl restart sshd  # Arch/Fedora
# sudo systemctl restart ssh # Debian/Ubuntu
```

Do not apply global sshd changes blindly on a shared machine. Existing Match
blocks, PAM, distro defaults, or automation may change the result.

## Remove a phone key

Open `~/.ssh/authorized_keys`, find the key by its comment or fingerprint, and
delete exactly that line. Check a public key's fingerprint with:

```bash
ssh-keygen -lf phone_ed25519.pub
```

The project uninstaller intentionally does not remove authorized keys because
the same key might support another SSH workflow.

## Switch back to Tailscale SSH

```bash
sudo tailscale set --ssh
```

Then confirm your tailnet SSH policy allows only the intended source,
destination, and non-root user. OpenSSH can stay installed; Tailscale intercepts
port 22 only on the Tailscale address while its SSH mode is enabled.
