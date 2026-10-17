# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's private reporting instead:
*Security* tab → *Report a vulnerability*. Include what you did, what happened and what you expected.
You will get an answer as soon as possible; there is no bounty.

Only the latest release is supported.

## What this widget has access to

The widget runs as your user. It reads the Claude Code logs and the Claude Code login
(`~/.claude/.credentials.json`), talks to two fixed Anthropic https endpoints and, when you allow it and your
access token has expired, rewrites the credentials file with the renewed tokens. The full list is in the
README under "How it works and what it touches".

Because it handles an OAuth login, these properties are treated as security-relevant and covered by tests
(`tests/test_backend.py`, `tests/test_install.sh`):

- the token is sent only to the two fixed URLs, over https, and redirects are refused;
- credentials are written atomically, owner-only, under a lock, never over a newer login, symlinks preserved;
- logs, server replies and the cache are untrusted input: validated, size-capped, no symlink following;
- tokens never appear in output, logs or error messages;
- `install.sh` never leaves you without a working widget (backup and rollback).

## Known limitations (not vulnerabilities)

- The usage endpoint (`/api/oauth/usage`) is not publicly documented and can change without notice.
- The widget needs read access to your Claude Code login to do its job. If you do not want that, do not install it, or switch
  off *Login renewal* in the settings (it then never writes the credentials file; it still reads the token to ask for the limits).
- Anyone who can already read your home directory can read your Claude Code login with or without this widget.
