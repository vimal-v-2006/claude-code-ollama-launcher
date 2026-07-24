# Release process

1. Update `VERSION` in `core.py` and `CHANGELOG.md`.
2. Run `make test-all`.
3. Run an isolated install/uninstall test from the release archive.
4. Inspect the archive for private paths, credentials, caches, and VCS metadata.
5. Build deterministic assets:

   ```bash
   make release
   sha256sum -c dist/*.sha256
   ```

6. Stage the exact candidate and run `git diff --cached --check`.
7. Tag `v<VERSION>` only after CI passes on the committed candidate.
8. Publish both `.tar.gz` and `.tar.gz.sha256` assets.
9. Download public assets and verify the checksum independently.
