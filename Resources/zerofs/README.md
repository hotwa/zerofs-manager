# External ZeroFS Dependency

ZeroFS Manager does not embed or redistribute the ZeroFS binary.

Upstream ZeroFS is https://github.com/Barre/ZeroFS and GitHub reports its license as AGPL-3.0. Keep this resource as installer guidance only; do not vendor ZeroFS source or binaries into the app bundle or release artifacts unless the project has a reviewed AGPL/commercial-license compliance plan.

Users install ZeroFS separately:

```sh
curl -sSfL https://sh.zerofs.net | sh
```

The app detects `zerofs` on `PATH` and common locations such as `/opt/homebrew/bin/zerofs`, `/usr/local/bin/zerofs`, and `$HOME/.local/bin/zerofs`.
