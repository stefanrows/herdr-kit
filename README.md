# herdr-kit

A community kit for [Herdr](https://herdr.dev). v0.1 gets a machine ready for a
multi-machine Herdr setup in one command:

- **Tailscale** installed and logged in, so the machine has a MagicDNS name.
- **OpenSSH** reachable over the tailnet. Herdr connects over plain SSH.
- **Herdr** installed, with its Claude Code integration when `claude` is present.

Then `doctor` checks everything and prints the exact `herdr machine add` line.

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
git clone https://github.com/stefanrows/herdr-kit && cd herdr-kit && ./herdr-kit setup
```

Targets: macOS (Apple Silicon), Arch Linux (Omarchy), Ubuntu/Debian inside WSL2.

## Usage

```sh
herdr-kit setup            # get this machine ready
herdr-kit setup --dry-run  # show what setup would change, change nothing
herdr-kit setup --yes      # answer yes to every prompt
herdr-kit doctor           # check this machine, change nothing
herdr-kit doctor --json    # the same checks as JSON
```

`setup` is idempotent: every step checks first and skips what is already there.
On a machine that is already set up it prints only green checks.

`herdr machine add` is not automated. `doctor` prints the lines, you run them on
your hub. Herdr checks host keys strictly and logs in by key, so `ssh-copy-id`
runs first: it trusts this machine (accept only the fingerprint `doctor` shows)
and installs your key. If the hub reached this machine before through Tailscale
SSH, `ssh` reports a changed host key: run the `ssh-keygen -R` line it prints,
then retry.

## Example

`herdr-kit doctor` on a Mac that is already set up:

```
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

ssh-copy-id asks to trust this machine: accept only SHA256:…
If ssh says the host key changed (Tailscale SSH was on before), run the ssh-keygen -R line it prints, then retry.
```

## Security

- Remote access is plain OpenSSH over the tailnet. herdr-kit **never enables
  Tailscale SSH**, and `doctor` flags it if it is on.
- Output shows machines by MagicDNS short name only: no IPs, no account data.
- Official install sources only: `herdr.dev/install.sh`, `tailscale.com/install.sh`,
  Homebrew and pacman. Use `--dry-run` to see exactly what would run.

## Video and guide

- Video: [Herdr: Run Claude Code Agents on Every Machine You Own](https://youtu.be/plb8d-DR4I8)
- Guide, with every command: [ceos3c.com](https://stefanrows.com/go/herdr-guide)

## More Herdr tools

v0.1 holds only the machine setup. Later Herdr tools will land here as new
subcommands of the same `herdr-kit` entrypoint.

## Development

Needs [ShellCheck](https://www.shellcheck.net) and [bats-core](https://github.com/bats-core/bats-core).

```sh
make lint
make test
```

## License

MIT
