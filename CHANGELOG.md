# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.0] – 2026-10-17 – first public release

Earlier 1.0 and 1.1 were internal; this is the first version published here.

### Added
- Plan limits (5-hour and weekly) in percent with reset times, and token usage from the Claude Code logs
  (current 5-hour block, today, this week, by model).
- State-coloured bars with the whole scale faintly visible behind the fill; a text label and dot accompany the colour.
- 10 colour profiles (Traffic light, Ice → Fire, Neon, Amber, Iceberg, Bold, Sunset, Inferno, Colour-blind safe, Mono)
  with a preview in the settings.
- Comments every 10 % (optional) and language packs: English, German and a Jamaican-patois edition (contributed by [Recoil](https://github.com/Rec0iL)).
  *Automatic* chooses German on a German system and English otherwise. The language is independent of the comments switch.
- Compact card view, adjustable background opacity, panel support.
- `install.sh` with package checks, backup and automatic rollback; `uninstall.sh`.
- Tests for the backend (with a local mock server), for the language packs and for install/update/rollback.

### Security
- Input from logs, the network and the cache is validated and size-capped; timestamps without a time zone, non-numeric token
  counts, huge lines and symlinks can no longer break or abuse the scan; 15 s time limit for the log scan.
- The OAuth token is only sent to two fixed https URLs; redirects are refused.
- Login renewal is serialised with a lock, validated before writing, written atomically with owner-only permissions, keeps
  symlinks, and never overwrites a newer login written by Claude Code in the meantime.
- Cache directory `0700`, files `0600`; backend started with `python3 -I`; shell quoting for the script path;
  untrusted strings are shown as plain text; tokens never appear in output.
