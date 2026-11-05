# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, Copilot and others) working in this repository.

**Read [docs/ai/GUIDE.md](docs/ai/GUIDE.md) before changing anything.**  It has the rules, where each kind of change goes, and how to test.  For the whole picture in one file (the guide, every function in the script with its comment, the commands, the tests and the latest changes), run `sh scripts/ai-context.sh` and read `lg-usb-2-eth0-for-ai.md`, or download the newest copy from <https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest/download/lg-usb-2-eth0-for-ai.md>.

The short version:

- `LG-USB-2-ETH0.sh` is plain POSIX `sh` that runs as root under busybox on the TV.  No bashisms (`[[ ]]`, arrays, `local` outside the tests, `$(< file)`, `echo -e`), and no `A && B || C` (CI's ShellCheck 0.9.0 flags it): use `if`.
- Functions the boot hook or a detached job needs go inside the `CORE` heredoc.  The hook runs the script itself, but `run_detached` only gets what's in `CORE`.
- Never write to system partitions, never change webOS network settings (the exceptions are the opt-in `--wifi-fallback`, which only flips the Wi-Fi switch and undoes it, and `--block-updates`, which only adds tagged hosts lines, one firewall rule and webOS's update switch, and undoes exactly those), and give every change a way back.  A reboot without the hook must always start clean.
- Anything downloaded is pinned (a fixed release or commit) and kept only if its SHA-256 matches.  Driver modules load only on the exact kernel they were built for, and only for adapters whose USB IDs they list.
- The background check runs every few seconds on the TV: keep it free of subprocesses until something actually changed.
- The TV app (`webos-app/src/`) is plain ES5 for old webOS browsers: no `let`, `const`, arrow functions, template literals, `async`, `?.` or `??`.
- Text people read: plain words, two spaces between sentences, no em dashes.
- Before you finish: `tests/run.sh busybox` (and `dash`, `bash`) passes, ShellCheck passes, a test covers the change, and `CHANGELOG.md` and `README.md` cover anything a user would notice.
- Don't bump `VERSION`, tag, or publish releases.  The maintainer does that.
- Say in the pull request that AI was used, and test on a real TV (model and webOS version).
