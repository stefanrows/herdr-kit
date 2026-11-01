# herdr-kit

A community kit for [Herdr](https://herdr.dev). v0.1 gets a machine ready for a
multi-machine Herdr setup: Tailscale up, OpenSSH reachable over the tailnet, and
Herdr with its Claude Code integration installed.

More Herdr tools will land here.

> herdr-kit is a community project. It is not affiliated with Herdr or Tailscale.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/stefanrows/herdr-kit/v0.1.0/install.sh | bash
herdr-kit setup
```

The installer fetches the tagged tree (default `v0.1.0`, override with `HK_REF`)
into `~/.local/share/herdr-kit` and symlinks `herdr-kit` into `~/.local/bin`.
Do not pipe `herdr-kit` itself to bash: it needs the rest of the repo.

Or clone and run setup from the tree:

```sh
git clone https://github.com/stefanrows/herdr-kit.git
cd herdr-kit && ./herdr-kit setup
```

## Supported systems

- macOS (Apple Silicon)
- Arch Linux
- Ubuntu/Debian inside WSL2

## Usage

```sh
herdr-kit setup            # get this machine ready
herdr-kit setup --dry-run  # show what setup would change
herdr-kit doctor           # check this machine, change nothing
```

### Sample `doctor` output

```
$ ./herdr-kit doctor
✓ OS: macos
✓ Tailscale: up
✓ MagicDNS name: mbp
✓ SSH server: listening on port 22
✓ Tailscale SSH: off
✓ Herdr: 0.9.5
✓ Claude Code integration: current (v11)

On your hub, run:
  ssh-copy-id mbp
  herdr machine add mbp

ssh-copy-id asks to trust this machine: accept only SHA256:<your-host-key-fingerprint>
If ssh says the host key changed (Tailscale SSH was on before), run the ssh-keygen -R line it prints, then retry.
```

## Security

Herdr reaches other machines with plain OpenSSH over the Tailscale tailnet.
herdr-kit leaves Tailscale SSH **off** (and turns it off on Linux if it was
on). Tailscale SSH would answer port 22 instead of OpenSSH, so Herdr would
not be talking to the sshd it expects. The tailnet is the trust boundary:
only nodes on it can reach that sshd.

## Video and guide

<!-- TODO(STEFAN): replace both placeholders after the 15:00 Europe/Berlin launch. -->

- Video: TODO(STEFAN): YouTube launch video URL
- Guide: TODO(STEFAN): ceos3c.com guide URL

## Development

Needs [ShellCheck](https://www.shellcheck.net) and [bats-core](https://github.com/bats-core/bats-core).

```sh
make lint
make test
```

## License

MIT
