#!/bin/sh
# ============================================================
# ZN-M2 First Boot IPTV Initialization
# Dual-line PPPoE dialing + policy routing
# ============================================================
#
# Physical setup:
#   wan  - Broadband PPPoE
#   lan1 - IPTV PPPoE (dedicated port, no VLAN)
#   lan2/3/4 - LAN devices
#
# ============================================================

# Disable reverse path filter for IPTV multicast
echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter 2>/dev/null
echo 0 > /proc/sys/net/ipv4/conf/lan1/rp_filter 2>/dev/null

# Disable ICMP redirects
for iface in /proc/sys/net/ipv4/conf/*/send_redirects; do
    echo 0 > "$iface" 2>/dev/null
done

# Increase network buffers for multicast
sysctl -w net.core.rmem_max=2097152 2>/dev/null
sysctl -w net.core.wmem_max=2097152 2>/dev/null

exit 0
