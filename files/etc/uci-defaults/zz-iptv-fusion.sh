#!/bin/sh
# ============================================================
# IPTV Fusion Setup - First-boot initialization
# This script runs once on first boot after firmware flash
# ============================================================

echo "============================================"
echo " ZN-M2 IPTV Fusion Initialization"
echo "============================================"

# 1. Set timezone
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].hostname='ZN-M2'
uci commit system

# 2. Enable services
/etc/init.d/igmpproxy enable 2>/dev/null && echo "[OK] igmpproxy enabled"
/etc/init.d/rtp2httpd enable 2>/dev/null && echo "[OK] rtp2httpd enabled"

# 3. Configure rtp2httpd if UCI config exists
if [ -f /etc/config/rtp2httpd ]; then
    uci set rtp2httpd.@rtp2httpd[0].disabled='0' 2>/dev/null
    uci set rtp2httpd.@rtp2httpd[0].bind_addr='0.0.0.0' 2>/dev/null
    uci set rtp2httpd.@rtp2httpd[0].bind_port='5555' 2>/dev/null
    # Set multicast interface to IPTV VLAN
    uci set rtp2httpd.@rtp2httpd[0].multicast_iface='wan.43' 2>/dev/null
    uci commit rtp2httpd 2>/dev/null
    echo "[OK] rtp2httpd configured"
elif [ -f /etc/rtp2httpd.conf ]; then
    # Non-UCI config format (older versions)
    # Configuration will need to be done manually via LuCI or SSH
    echo "[INFO] rtp2httpd uses /etc/rtp2httpd.conf format"
    echo "[INFO] Please configure multicast interface via LuCI"
fi

# 4. Enable multicast forwarding in kernel
echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter 2>/dev/null
echo 0 > /proc/sys/net/ipv4/conf/wan.43/rp_filter 2>/dev/null
echo 1 > /proc/sys/net/ipv4/igmp_max_memberships 2>/dev/null

# 5. Print configuration reminder
echo ""
echo "============================================"
echo " IPTV Configuration Reminder"
echo "============================================"
echo ""
echo " 1. Edit PPPoE credentials:"
echo "    uci set network.wan.username='YOUR_ACCOUNT'"
echo "    uci set network.wan.password='YOUR_PASSWORD'"
echo "    uci commit network && /etc/init.d/network restart"
echo ""
echo " 2. Verify IPTV VLAN ID (default: 43):"
echo "    uci get network.wan.vid  (should be 43 or your local VLAN)"
echo ""
echo " 3. Check IPTV interface status:"
echo "    ifconfig wan.43"
echo ""
echo " 4. Access rtp2httpd web interface:"
echo "    http://192.168.1.1:5555"
echo ""
echo " 5. Access LuCI management:"
echo "    http://192.168.1.1"
echo ""
echo "============================================"

# 6. Remove this script (runs only once)
rm -f "$0"
