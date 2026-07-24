# Security Policy

## Supported versions

The latest tagged release receives security fixes.

## Security model

- The graphical application runs as the desktop user.
- Model discovery is limited to the loopback Ollama API.
- Custom endpoint URLs may be local or remote; use HTTPS for non-loopback endpoints. Credentials embedded in URLs are rejected.
- Claude Code is launched with web search, web fetch, and Chrome integration disabled.
- Claude Code retains its native file and shell permission prompts.
- Context changes require a root-owned helper installed under `/usr/local/libexec`.
- The helper accepts only these exact values: 4096, 8192, 16384, 32768, 65536, and 131072.
- The helper writes one fixed systemd drop-in and restarts only `ollama.service`.
- Commands are constructed as argument arrays; user inputs are not interpolated into a shell command.
- Preferences are stored with mode `0600`.

## Important boundary

"Local model" does not mean every command Claude Code can run is offline. Claude Code's Bash tool can execute network-capable programs when the user approves them. Review permission prompts and run untrusted repositories inside an appropriate sandbox or container.

## Reporting a vulnerability

Please use GitHub's private security advisory feature for this repository rather than opening a public issue. Include reproduction steps, affected version, and expected impact.

Do not include API keys, tokens, private source code, or personal data in reports.
