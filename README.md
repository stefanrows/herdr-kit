# herdr-kit

A community kit for [Herdr](https://herdr.dev). v0.1 gets a machine ready for a
multi-machine Herdr setup: Tailscale up, OpenSSH reachable over the tailnet, and
Herdr with its Claude Code integration installed.

> herdr-kit is a community project. It is not affiliated with Herdr or Tailscale.

**Status:** v0.1 is under construction.

## Usage

```sh
./herdr-kit setup            # get this machine ready
./herdr-kit setup --dry-run  # show what setup would change
./herdr-kit doctor           # check this machine, change nothing
```

Targets: macOS (Apple Silicon), Arch Linux, Ubuntu/Debian inside WSL2.

## Development

Needs [ShellCheck](https://www.shellcheck.net) and [bats-core](https://github.com/bats-core/bats-core).

```sh
make lint
make test
```

## License

MIT
