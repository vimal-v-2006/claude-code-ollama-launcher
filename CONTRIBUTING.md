# Contributing

Contributions are welcome through issues and pull requests.

## Development setup

Install the runtime prerequisites listed in the README, then run:

```bash
make lint
make test
```

## Guidelines

- Keep the launcher dependency-light and Linux-focused.
- Preserve argument-array process launching; do not introduce `shell=True` for user-controlled values.
- Add or update tests with every behavior change.
- Keep privileged behavior in the fixed, root-owned context helper.
- Do not add telemetry, cloud model fallback, or automatic model downloads.
- Run isolated install/uninstall verification before submitting changes.

## Commit style

Use a concise imperative subject, for example:

```text
fix: preserve model selection after refresh
```

## Pull requests

Describe the user-visible behavior, tests run, and security implications. Do not include secrets or personal filesystem paths.
