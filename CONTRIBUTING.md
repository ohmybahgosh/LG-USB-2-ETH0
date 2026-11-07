# Contributing to LG-USB-2-ETH0

Thanks for helping.  Reports from real TVs, fixes, docs and code are all welcome.

## Reporting how it went on your TV

Compatibility reports are what help most, whether it worked or not.  The easiest way: open the TV app, choose **Report for GitHub**, and scan the QR code with your phone.  It opens the form with your TV, adapter, result and the full report already filled in, MAC addresses hidden.

Without the app, run `sh LG-USB-2-ETH0.sh report` and paste the output into the [compatibility report form](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=compatibility-report.yml).  Something broken?  Use the [bug report form](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=bug-report.yml).  Security problems go privately, see [SECURITY.md](SECURITY.md).  Questions and ideas go to [Discussions](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions) (Q&A and Ideas), not issues.

Please follow the [code of conduct](CODE_OF_CONDUCT.md).

## Working on the code

The script is one POSIX `sh` file that runs as root under busybox on the TV.  The TV app is plain HTML, CSS and ES5 JavaScript in `webos-app/`.  Start with the [README](README.md) and the [guide for contributors and their AI assistants](docs/ai/GUIDE.md).

```sh
tests/run.sh busybox     # the test suite, closest to the TV (also dash and bash)
shellcheck -s sh LG-USB-2-ETH0.sh && shellcheck tests/run.sh
python3 tests/check-issue-forms.py
node tests/check-i18n.js # every text in the TV app translated
webos-app/build.sh       # the TV app's IPK (needs ares-package from @webos-tools/cli)
```

The tests run the script against a fake `/sys`, so they need no TV and no root, and change nothing on your machine.

**Working with an AI assistant?**  Give it the knowledge base first: [lg-usb-2-eth0-for-ai.md](https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest/download/lg-usb-2-eth0-for-ai.md) (download it and attach it to Claude, ChatGPT or Gemini, or run `sh scripts/ai-context.sh` in your clone).  It has the rules, every function in the script with what it does, the commands, the tests and the latest changes, so the assistant writes changes that fit.  Coding agents read [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md) by themselves.  [docs/ai/GUIDE.md](docs/ai/GUIDE.md) explains how to use it.

AI-assisted pull requests are welcome, held to the same standard as the rest of this project (v2.0 on was built with AI coding agents too): say in the pull request that AI was used, make sure you understand and have reviewed every change, and test it on a real TV.

Ground rules:

- **It runs as root on someone's TV.**  Never write to system partitions or change webOS network settings, give every change a way back, and make sure a reboot without the hook starts clean.
- **POSIX `sh` for busybox.**  No bashisms.  ShellCheck must pass, including CI's older version.
- **Pinned and checked downloads.**  Anything downloaded comes from a fixed release or commit and is kept only if its SHA-256 matches.
- **Leave Wi-Fi, tethering and other USB devices alone.**
- **A test for every change in behavior,** in `tests/run.sh`.
- **Translations.**  The TV app speaks English, Russian and Spanish.  New text in the app needs a translation in each, or `node tests/check-i18n.js` fails.  If you can't translate it, say so in the pull request and the maintainer will.  New languages are welcome: see [Translating the app](README.md#translating-the-app).
- **Write for TV owners.**  Plain words in output, the app and docs, two spaces between sentences, no em dashes, and a line in `CHANGELOG.md` for anything they'd notice.

Open a pull request against `main`; the template lists what to check.

## Releases

The maintainer cuts releases by pushing a `v*` tag.  GitHub Actions runs the tests, builds the TV app, publishes the script, `SHA256SUMS`, the IPK, its Homebrew Channel manifest and the AI knowledge base, and tells ohmybahgosh.dev to refresh its Homebrew Channel repository.
