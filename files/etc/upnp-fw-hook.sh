#!/bin/sh
# ============================================================
# ZN-M2 - UPnP port-mapping protection on firewall reload
# ============================================================
#
# Problem:
#   miniupnpd (nftables backend) writes its DNAT / forward rules into the
#   upnp_forward / upnp_prerouting / upnp_postrouting chains of the fw4
#   table 'inet fw4'. A firewall reload (fw4 reload) rebuilds that entire
#   table, so all of those rules disappear - while the miniupnpd process
#   keeps running, still believing the mappings are active. Every port
#   forward silently stops working until the daemon is restarted.
#   PassWall reloads the firewall on node switch, so this happens in
#   normal day-to-day use, not just on manual firewall changes.
#
# Fix:
#   This script is registered as a firewall 'include' (type 'script') so it
#   runs after the firewall has been (re)built. It waits a few seconds for
#   fw4 to finish, then restarts miniupnpd, which re-imports all mappings
#   from upnp_lease_file (/var/run/miniupnpd.leases).
#
# Contract:
#   - Invoked by fw4, so anything printed to stdout is parsed as nft rules;
#     this script prints nothing and always exits 0.
#   - Restart is skipped when the daemon is not running yet, so it cannot
#     interfere with the normal /etc/init.d boot ordering.
# ============================================================

[ -x /etc/init.d/miniupnpd ] || exit 0

(
	sleep 4
	if pgrep -f '/usr/sbin/miniupnpd' >/dev/null 2>&1; then
		/etc/init.d/miniupnpd restart >/dev/null 2>&1
		logger -t upnp-fw-hook "firewall reloaded, miniupnpd restarted to restore port mappings"
	fi
) >/dev/null 2>&1 &

exit 0
