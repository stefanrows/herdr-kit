# shellcheck shell=bash
# SSH: OpenSSH server reachable over the tailnet. Tailscale SSH must stay off.
#
# Module contract (lib/tailscale.sh, lib/ssh.sh, lib/herdr.sh):
#   check_<x>    print ok/warn/fail lines; return 0 when ready, 1 when install_<x> should run.
#   install_<x>  make it ready; run every system change through hk_run (honours --dry-run).

check_ssh() { not_implemented ssh; }

install_ssh() { not_implemented ssh; }
