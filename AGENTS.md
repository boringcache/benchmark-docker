# Docker Cache Proofs Agent Notes

- The Docker cache product path is `boringcache docker` publishing `type=boringcache` from the managed BuildKit daemon. Do not treat historical registry/OCI cache runs as managed-backend evidence.
- The managed path lets the CLI create its BuildKit builder by default, including when Docker tool cache is enabled. Do not pass backend selectors or a user-selected builder into the managed lifecycle.
- Keep local cache scopes disposable, never print tokens, and leave unrelated Docker or Colima containers alone.
- Public artifacts must stand on their own. Never mention private repository
  names, private paths, internal authoring layout, sync mechanics, or automation
  provenance in docs, workflow comments, commits, pull requests, comments, or
  release notes.
- The CLI and `.boringcache.toml` own cache identity. Do not use the Action as a
  CLI-only installer or reintroduce retired inputs, modes, or tokens.
