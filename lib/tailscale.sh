# shellcheck shell=bash
# Tailscale: installed, logged in, MagicDNS name known.
#
# Module contract (lib/tailscale.sh, lib/ssh.sh, lib/herdr.sh):
#   check_<x>    print ok/warn/fail lines; return 0 when ready, 1 when install_<x> should run.
#   install_<x>  make it ready; run every system change through hk_run (honours --dry-run).

check_tailscale() { not_implemented tailscale; }

install_tailscale() { not_implemented tailscale; }
