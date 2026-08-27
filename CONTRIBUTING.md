# Contributing

Small, reviewable pull requests are welcome.

## Local checks

```bash
bash tests/run.sh
shellcheck install.sh uninstall.sh bin/* tests/*.sh
```

Keep installer behavior idempotent and preserve user-owned shell, tmux, SSH,
firewall, desktop, and window-manager configuration. New privileged or network
actions need a clear reason, a dry-run path, and documentation.

Security changes should include a threat-model update or explain why none is
needed. Never include a real tailnet name, Tailscale IP, auth URL, token, or SSH
key in fixtures, screenshots, issues, or pull requests.

## Style

- Bash scripts use `set -Eeuo pipefail`.
- Quote expansions and avoid `eval`.
- Prefer explicit target paths over globs for removal.
- Test public behavior with temporary HOME and stub commands.
- Documentation examples use fake usernames, hosts, and paths.
