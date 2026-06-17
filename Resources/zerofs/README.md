# External ZeroFS Dependency

ZeroFS Manager does not embed or redistribute the ZeroFS binary.

Users install ZeroFS separately:

```sh
curl -sSfL https://sh.zerofs.net | sh
```

The app detects `zerofs` on `PATH` and common locations such as `/opt/homebrew/bin/zerofs`, `/usr/local/bin/zerofs`, and `$HOME/.local/bin/zerofs`.
