# Threat model and security

`codex-mobile` gives a phone an interactive shell on your Linux account. Treat
that as seriously as physical access to an unlocked terminal.

## Recommended trust path

```text
phone node identity
  → Tailscale access policy
  → Tailscale SSH policy
  → allowed Linux username
  → tmux session
  → Codex and your project files
```

Tailscale encrypts node-to-node traffic with WireGuard. Tailscale SSH then uses
node identity and tailnet policy for SSH authentication, so no reusable SSH
password or user-managed private key is needed. See the
[official Tailscale SSH documentation](https://tailscale.com/docs/features/tailscale-ssh).

## What this protects against

- Random internet scans: the recommended mode does not publish SSH to the
  public internet.
- People outside your tailnet: they do not receive the node keys needed to
  reach the host.
- A tailnet device without an allowed SSH rule: network and SSH policy must
  both authorize the connection.
- Brief mobile disconnects: tmux keeps the process running on the host.

## What this does not protect against

- A compromised or unlocked phone that is still authorized in the tailnet.
- A compromised Tailscale identity, Linux account, PC, or Codex account.
- Overly broad custom tailnet policies.
- Commands that you approve inside Codex.
- Other services already exposed by your PC, router, firewall, or sshd.
- A malicious installer or dependency update. Review scripts before running
  them, especially any network-fetched install script.

## Who can SSH?

Not "anyone using Tailscale." The effective answer comes from two policy
layers:

1. A network grant/ACL must let the source reach TCP port 22 on the host.
2. An `ssh` rule must allow that source, destination, and Linux username.

For a personal, untagged host, a tight SSH rule looks like this fragment:

```jsonc
"ssh": [
  {
    "action": "check",
    "src": ["autogroup:member"],
    "dst": ["autogroup:self"],
    "users": ["autogroup:nonroot"]
  }
]
```

`autogroup:self` limits each member to devices they own, and this version does
not permit root. This fragment does not replace the rest of your policy; merge
and test it in the Tailscale admin console. Tagged/shared devices behave
differently, and editing SSH policy replaces the default SSH rules. Read the
[policy syntax reference](https://tailscale.com/docs/reference/syntax/policy-file)
before changing a shared tailnet.

Use `check` when you want periodic browser reauthentication. Review the admin
console's Devices and Access controls pages after adding users or sharing a
machine.

## Tailscale SSH vs key mode

| Property | Tailscale SSH | OpenSSH key mode |
| --- | --- | --- |
| User authentication | Tailnet node identity | Private key on phone |
| Authorization | Tailnet SSH policy | `authorized_keys` + sshd rules |
| Tailscale port 22 | Intercepted only on tailnet address | Standard sshd |
| Public/LAN sshd exposure | Unchanged; not required here | Depends on host sshd/firewall |
| Revocation | Disable phone/user/rule | Remove key and/or disable phone |

Key mode still benefits from Tailscale network policy, but OpenSSH may listen
on LAN or public interfaces depending on sshd configuration. The installer
requires and validates a public key before changing files, packages, services,
or Tailscale SSH mode. It does not silently disable password authentication,
rewrite global sshd configuration, or change firewall rules. Harden OpenSSH
explicitly using [SSH key mode](ssh-key-mode.md).

## Secrets that must never enter this repository

- Tailscale login/auth URLs
- Tailnet DNS names or personal Tailscale IPs in examples/screenshots
- Private SSH keys
- `~/.codex`, tokens, cookies, or account exports
- Real usernames, host inventories, or policy files from a private tailnet

Public SSH keys are not secret, but publishing one creates unnecessary
cross-system identity linkage. Examples should stay fake.

## If your phone is lost

1. Disable or remove the phone from Tailscale's Devices page.
2. Revoke its app/account session with your identity provider if needed.
3. If using key mode, remove its line from `~/.ssh/authorized_keys`.
4. From the PC, stop active work with `codex-mobile --stop` and review shell,
   Git, and Codex activity.
5. Turn off Tailscale SSH temporarily with `sudo tailscale set --ssh=false` if
   you cannot verify policy quickly.

## Safe defaults used by the project

- No public port forwarding or router changes
- No root SSH recommendation
- No password stored in scripts
- No automatic edits to tailnet policy, global sshd config, firewall, Kitty, or
  Hyprland
- Uninstall leaves SSH keys and packages alone rather than guessing whether
  another workflow needs them
