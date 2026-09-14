#!/bin/sh
# ============================================================
# gd-iptv-playlist  —  广东电信 IPTV 定时鉴权 + 直播/回看播放列表生成
# 适用：OpenWrt (busybox ash)，无 python 依赖，纯 curl/sed/grep/awk
#
# 鉴权流程完全参照酷9 (Ku9) 的 iptv.js：
#   1) 访问 eds.iptv.gd.cn 拿 302 Location，动态发现本账号真实的 EPG 服务器 baseUrl
#      （每个用户/地区的 EPG 地址不同，绝不可写死！）
#   2) POST <baseUrl>/EPG/jsp/ValidAuthenticationHWCTC.jsp  ->  拿到 Set-Cookie
#   3) GET  <baseUrl>/EPG/jsp/getchannellistHWCTC.jsp (带 Cookie)  ->  频道列表 HTML
#   4) 解析 ChannelURL("rtsp://...|igmp://...")  ->  直播走 rtp2httpd 组播, 回看用 &playseek=
#   5) 分类(广东/央视/卫视/儿童/其他) + 过滤(广告/测试/非汉英) -> 生成 m3u
#   6) 写入 /www/iptv/playlist.m3u （uhttpd 直接可订阅 http://<路由IP>/iptv/playlist.m3u）
#
# 用法：
#   gd-iptv-playlist generate      # 鉴权+拉列表+生成播放列表（定时任务调这个）
#   gd-iptv-playlist discover       # 只打印 EDS 发现的 EPG baseUrl（排错用）
#   gd-iptv-playlist capture        # 只抓取原始 HTML 到 $HTML（排错用）
#   gd-iptv-playlist diagnose       # 抓取并统计格式特征，打印样本（排错用，不会生成 m3u）
#   gd-iptv-playlist parse FILE     # 仅解析本地 HTML 文件（离线测试用）
#   gd-iptv-playlist install        # 安装为每日定时任务 + 创建目录
#
# 解析器对引号类型健壮：ChannelName="..." 与 ChannelName='...' 均能识别。
#
# 注意：所有 EPG 请求都通过 IPTV 专线（--interface 绑定 IPTV 口），否则 EPG 不认源 IP。
# ============================================================

# ---------- 0. 载入本地密钥（若存在则覆盖下面的默认值） ----------
AUTH_CONF="/etc/iptv/auth.conf"
[ -f "$AUTH_CONF" ] && . "$AUTH_CONF"

# ---------- 1. 鉴权参数（来自酷9 iptv.js，账号专属） ----------
USER_ID="${USER_ID:-07504655037}"
NETUSER="${NETUSER:-jmITV6406533@iptv.gd}"
DHCPUSER="${DHCPUSER:-jmITV6406533@iptv.gd}"
AUTH="${AUTH:-D42E86917A78E8D99A02AD4659276E6B1C05CFF9B870330012526E20E54E9EAD7535C7C10334946ECFC6B93295B6D05F0895E517D07925C42BBAAC509102D15106615BCFCE21226D69C22B3C224E72A9A889ED181BEA6A3B4566B4CBA487CA81E771D3F871B0D9836950B89E245236874A8D0105D6FE082029A10BE4E653772B}"
STBTYPE="${STBTYPE:-JIUZHOU_PTV8098_toEPG}"
STBVERSION="${STBVERSION:-4.4.2-D-20210719.1052.2020v1}"
# 注意：酷9 里是完整 STBID，之前写 990108 会鉴权失败
STBID="${STBID:-001002990108480015180023B84FD4BB}"
USERTOKEN="${USERTOKEN:-2F1E53E43402799275D116E24CEBF992}"
MAC="${MAC:-00:23:b8:4f:d4:bb}"

# ---------- 2. 服务器 / 运行参数 ----------
# EDS 发现入口（可通过 EDS_URL 覆盖，便于本地测试）
EDS_URL="${EDS_URL:-http://eds.iptv.gd.cn:8082/EDS/jsp/AuthenticationURL?UserID=$USER_ID&Action=Login}"
EPG_URL="${EPG_URL:-https://raw.githubusercontent.com/litiande03/epg/refs/heads/master/pl.xml.gz}"
OUT_DIR="${OUT_DIR:-/www/iptv}"
OUT_FILE="${OUT_FILE:-$OUT_DIR/playlist.m3u}"
COOKIE="${COOKIE:-/tmp/iptv_cookie.txt}"
HTML="${HTML:-/tmp/iptv_list.html}"
RTP2HTTPD_PORT="${RTP2HTTPD_PORT:-5140}"
FCC_SERVER="${FCC_SERVER:-125.88.52.199:8027}"

# ---------- 3. IPTV 接口绑定（保证走 IPTV 专线） ----------
# 默认自动探测 IPTV 口的 l3 设备；可用 IPTV_IFACE 强制指定；设 NO_BIND=1 关闭绑定
BIND=""
if [ -z "${NO_BIND:-}" ]; then
  iface="${IPTV_IFACE:-}"
  if [ -z "$iface" ] && command -v ifstatus >/dev/null 2>&1; then
    iface=$(ifstatus IPTV 2>/dev/null | jsonfilter -q -e '@.l3_device' 2>/dev/null)
  fi
  if [ -z "$iface" ]; then
    iface=$(uci -q get network.IPTV.ifname 2>/dev/null)
  fi
  if [ -z "$iface" ]; then
    iface="pppoe-IPTV"
  fi
  if [ -d "/sys/class/net/$iface" ]; then
    BIND="--interface $iface"
    echo "[iptv] 绑定 IPTV 接口: $iface"
  else
    echo "[iptv] 警告: 未找到接口 $iface，将依赖系统策略路由（table 100）"
  fi
fi

UA="Mozilla/5.0"
CT="Content-Type: application/x-www-form-urlencoded"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ---------- EDS 发现 EPG baseUrl ----------
do_discover() {
  log "步骤0  EDS 发现 EPG 地址: $EDS_URL"
  local loc
  loc=$(curl -s -D - -o /dev/null --max-redirs 0 $BIND "$EDS_URL" 2>/dev/null \
        | tr -d '\r' | awk 'BEGIN{IGNORECASE=1} tolower($1)=="location:"{print $2; exit}')
  if [ -z "$loc" ]; then
    log "错误：EDS 未返回 Location（网络不通 / 未走 IPTV 线路 / EDS 地址变化）"
    return 1
  fi
  log "  EDS Location: $loc"
  BASEURL=$(printf '%s' "$loc" | sed -nE 's#^(https?://[^/]+).*#\1#p')
  if [ -z "$BASEURL" ]; then
    log "错误：无法从 Location 提取 baseUrl: $loc"
    return 1
  fi
  log "  EPG baseUrl: $BASEURL"
  return 0
}

# ---------- 鉴权 + 拉取列表 ----------
# 酷9 的方式：直接从 ValidAuthenticationHWCTC.jsp 的响应头抓 Set-Cookie，
# 拼成 Cookie 字符串用于后续 getchannellist（不依赖 curl -c 的 jar 落盘）。
do_fetch() {
  do_discover || return 1

  log "步骤1  鉴权 $BASEURL/EPG/jsp/ValidAuthenticationHWCTC.jsp ..."
  local hdr
  hdr=$(curl -s -L -D - -o /dev/null \
    -X POST "$BASEURL/EPG/jsp/ValidAuthenticationHWCTC.jsp" \
    -H "$CT" -H "User-Agent: $UA" \
    -d "UserID=$USER_ID&Lang=&SupportHD=1&NetUserID=${NETUSER%@*}%40iptv.gd&DHCPUserID=${DHCPUSER%@*}%40iptv.gd&Authenticator=$AUTH&STBType=$STBTYPE&STBVersion=$STBVERSION&conntype=2&STBID=$STBID&templateName=&areaId=&userToken=$USERTOKEN&userGroupId=8888&productPackageId=&mac=$(printf '%s' "$MAC" | sed 's/:/%3A/g')&UserField=&SoftwareVersion=&IsSmartStb=0&desktopId=1&stbmaker=&VIP=" \
    $BIND 2>/dev/null | tr -d '\r')

  # 提取所有 Set-Cookie（取 ; 之前部分，拼成 Cookie 字符串）
  COOKIES=$(printf '%s\n' "$hdr" | awk '
    BEGIN{IGNORECASE=1}
    tolower($1)=="set-cookie:"{
      line=$0; c=index(line,":"); if(c>0) line=substr(line,c+2);
      n=index(line,";"); if(n>0) line=substr(line,1,n-1);
      printf "%s; ", line
    }')
  COOKIES=$(printf '%s' "$COOKIES" | sed 's/; $//')

  if [ -z "$COOKIES" ]; then
    log "错误：鉴权响应未返回 Set-Cookie（账号/鉴权BODY可能失效，或没走 IPTV 专线）"
    return 1
  fi
  echo "$COOKIES" > "$COOKIE"
  log "  已获取 Cookie: $COOKIES"

  log "步骤2  GET 频道列表 $BASEURL/EPG/jsp/getchannellistHWCTC.jsp ..."
  curl -s -H "Cookie: $COOKIES" -X GET "$BASEURL/EPG/jsp/getchannellistHWCTC.jsp" \
    -H "User-Agent: $UA" \
    $BIND -o "$HTML" -w "  list HTTP %{http_code} size=%{size_download}\n"

  if [ ! -s "$HTML" ]; then
    log "错误：频道列表为空，鉴权可能过期或网络不通（须走 IPTV 专线条）。"
    return 1
  fi
  return 0
}

# 注：频道分类(is_junk/classify)与 tvg-name 清洗规则已统一实现在下方 generate_m3u 的 awk 脚本内。
#     原因：每频道 fork 6 次 sed 在 184 频道 × 2KB 属性串的场景下极慢（Windows 下可达数分钟），
#           收进单进程 awk 后从 ~1100 次 fork 降至 1 次，路由器上可毫秒级完成。

# ---------- 取本机 LAN IP（组播直播地址用） ----------
lan_ip() {
  uci -q get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1"
}

# ---------- 解析并生成 m3u ----------
# 解析策略（引号无关、稳健）：
#   1) 先把整文件压成单行（去换行），避免频道块跨行导致正则截断
#   2) 以 ChannelID= 为锚点，向后取一段，截到下一个频道块起始标记 Authentication[ 之前
#      —— 这样无论外层用 ' 还是 " 包裹、无论属性顺序如何，都能完整拿到一个频道的属性串
#   3) 每个属性用 ChannelName[ =]*["']([^"']*)["'] 提取，单/双引号皆可
generate_m3u() {
  local src="$1"
  mkdir -p "$OUT_DIR"
  local tmp="$OUT_DIR/.playlist.$$.m3u"
  : > "$tmp"

  # 提取每个频道块：真实电信列表用  CTCSetConfig('Channel', '属性串');  包裹，
  # 外层单引号、内部属性双引号且内部不含单引号 —— 两个 ' 之间即一个频道的完整属性串。
  # 用 grep 直接截取每个 ('Channel', '...')，天然避开 UserChannelID 等干扰子串
  # （旧逻辑按 ChannelID= 切分，会被 UserChannelID= 再切一刀，导致一个频道裂成两半 -> 0 保留）。
  # 提取每个频道块：用 sed 以 'CTCSetConfig('Channel', ' 为起点、以 ');' 为终点切分成独立行，
  # 再 grep 过滤出含 ChannelID 的行。比 grep -oE '[^']*' 稳健，不会因边界贪婪而隔块错配。
  tr -d '\r\n' < "$src" 2>/dev/null \
    | sed -E "s/CTCSetConfig\('Channel',[ ]*'/\n/g; s/'\);/\n/g" \
    | grep -i 'ChannelID=' > "$tmp.blocks"

  local LANIP
  LANIP=$(lan_ip)
  local statf="$OUT_DIR/.stat.$$"
  : > "$statf"

  # 单进程 awk 完成：属性提取 -> 去重 -> 过滤 -> 分类 -> 输出 m3u
  # （原先每频道 fork 6 次 sed，184 频道约 1100 次 fork，在 Windows/低端设备上极慢）
  tr -d '\r\n' < "$src" 2>/dev/null \
    | sed -E "s/CTCSetConfig\('Channel',[ ]*'/\n/g; s/'\);/\n/g" \
    | grep -i 'ChannelID=' \
    | awk -v lan="$LANIP" -v port="$RTP2HTTPD_PORT" -v fcc="$FCC_SERVER" \
          -v epg="$EPG_URL" -v dbg="${DEBUG:-}" '
      # 取 key="value" / key = "value" 中的 value（单双引号皆可）
      function getattr(s, key,   p, rest, q, e) {
        p = index(s, key)
        if (p == 0) return ""
        rest = substr(s, p + length(key))
        sub(/^[ \t]*=[ \t]*/, "", rest)
        if (rest == "") return ""
        q = substr(rest, 1, 1)
        if (q != "\"" && q != "\047") return ""
        e = index(substr(rest, 2), q)
        if (e == 0) return ""
        return substr(rest, 2, e - 1)
      }
      function has(s, k) { return index(s, k) > 0 }

      # 过滤：依据真实电信 184 频道清单校准
      function isjunk(n) {
        if (has(n,"广告") || has(n,"购物") || has(n,"商城") || has(n,"促销")) return 1
        if (has(n,"推广") || has(n,"直销") || has(n,"优选") || has(n,"精选")) return 1
        if (has(n,"测试") || has(n,"Test")  || has(n,"TEST")  || has(n,"test"))  return 1
        if (has(n,"调试") || has(n,"临时")  || has(n,"DEMO")  || has(n,"demo"))  return 1
        if (has(n,"演示") || has(n,"导视")  || has(n,"试用")) return 1
        # 与正式频道组播地址完全重复的"时移专用"副本
        if (has(n,"时移专用")) return 1
        # 非汉语非英语：频道名是中文写的语种名，字节法抓不到，须按关键词
        if (has(n,"西班牙语") || has(n,"法语")    || has(n,"阿拉伯语") || has(n,"俄语"))    return 1
        if (has(n,"韩语")     || has(n,"日语")    || has(n,"德语")    || has(n,"葡萄牙语")) return 1
        if (has(n,"意大利语") || has(n,"越南语")  || has(n,"泰语"))   return 1
        # 技术测试 / 低码率 / 特殊流
        if (has(n,"同播") || has(n,"窄色域") || has(n,"开机标清") || has(n,"校正")) return 1
        if (has(n,"4M")   || has(n,"-1M"))   return 1
        return 0
      }

      # 分类：顺序敏感 —— 儿童优先于央视；卫视在广东判断之后；广东只用精确本地词
      function cls(n) {
        if (has(n,"少儿") || has(n,"卡通") || has(n,"动画") || has(n,"早期教育")) return "儿童"
        if (has(n,"育儿") || has(n,"幼儿") || has(n,"儿童")) return "儿童"
        if (has(n,"KIDS") || has(n,"Kids") || has(n,"CARTOON") || has(n,"Cartoon")) return "儿童"
        if (has(n,"广东")) return "广东"
        if (has(n,"珠江") || has(n,"岭南") || has(n,"大湾区")) return "广东"
        if (has(n,"经济科教") || has(n,"江门") || has(n,"嘉佳")) return "广东"
        if (has(n,"CCTV") || has(n,"CGTN") || has(n,"CETV")) return "央视"
        if (has(n,"央视") || has(n,"中央")) return "央视"
        if (has(n,"卫视")) return "卫视"
        return "其他"
      }

      BEGIN { total = 0; kept = 0; print "#EXTM3U x-tvg-url=\"" epg "\"" }
      {
        total++
        name = getattr($0, "ChannelName")
        urlf = getattr($0, "ChannelURL")
        ts   = getattr($0, "TimeShift")
        tsu  = getattr($0, "TimeShiftURL")
        if (name == "" || urlf == "") next

        # ChannelURL 形如  igmp://239.77.x.x:5146|rtsp://125.88.x.x/PLTV/...smil?...
        n = split(urlf, parts, "|")
        rtsp = ""; igmp = ""
        for (i = 1; i <= n; i++) {
          if (substr(parts[i], 1, 7) == "igmp://") igmp = parts[i]
          if (substr(parts[i], 1, 7) == "rtsp://") rtsp = parts[i]
        }

        # 直播：组播经 rtp2httpd；无组播则回退 rtsp 单播
        mcast = ""; live = ""
        if (igmp != "") {
          mcast = substr(igmp, 8)
          live  = "http://" lan ":" port "/rtp/" mcast "?fcc=" fcc
        } else if (rtsp != "") {
          live = rtsp
        }
        if (live == "") next

        # 去重：优先按组播地址（"高清/超清/4k/时移专用"等副本大量复用同一组播）
        dkey = (mcast != "") ? mcast : name
        if (dkey in seen) next
        seen[dkey] = 1

        if (isjunk(name)) {
          if (dbg != "") { print ("DBG JUNK: " name) > "/dev/stderr" }
          next
        }
        g = cls(name)
        if (dbg != "") { print ("DBG KEEP: name=" name " group=" g " mcast=" mcast " ts=" ts) > "/dev/stderr" }
        kept++

        # tvg-name 清洗：真实列表存在 "CCTV -1综合高清"（负号前多空格），会导致 EPG 匹配失败
        tvg = name
        sub(/^CCTV[ \t]+-/, "CCTV-", tvg)

        # 回看：仅当 TimeShift="1" 且有时移地址；TimeShiftURL 才是合法 PLTV 时移源
        catchup = ""
        if (ts == "1" && tsu != "") {
          sub(/&playseek=.*$/, "", tsu)
          if (substr(tsu, 1, 7) == "rtsp://")
            catchup = tsu "&playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}"
        }

        if (catchup != "")
          print "#EXTINF:-1 tvg-name=\"" tvg "\" group-title=\"" g "\" catchup=\"default\" catchup-source=\"" catchup "\"," name
        else
          print "#EXTINF:-1 tvg-name=\"" tvg "\" group-title=\"" g "\"," name
        print live
      }
      END { print ("__STAT__ " total " " kept) > "/dev/stderr" }
    ' > "$tmp" 2> "$statf"

  local stat total kept
  stat=$(grep '^__STAT__' "$statf" 2>/dev/null | head -1)
  total=$(echo "$stat" | awk '{print $2}')
  kept=$(echo "$stat"  | awk '{print $3}')
  [ -n "${DEBUG:-}" ] && grep '^DBG' "$statf" >&2
  rm -f "$statf" "$tmp.blocks"

  mv "$tmp" "$OUT_FILE"
  log "完成：共解析 ${total:-0} 个频道条目，保留 ${kept:-0} 个 -> $OUT_FILE"
}

# ============================================================
# 子命令
# ============================================================
case "${1:-generate}" in
  generate)
    do_fetch || exit 1
    generate_m3u "$HTML"
    ;;
  discover)
    do_discover && echo "BASEURL=$BASEURL"
    ;;
  capture)
    do_fetch && log "已保存到 $HTML"
    ;;
  diagnose)
    do_fetch || exit 1
    echo "=== RAW SIZE ==="; wc -c "$HTML"
    echo "=== MARKER COUNTS ==="
    for m in "CTCSetConfig" "ChannelID" "ChannelName" "ChannelURL" "ChannelSDP" "Authentication" "'Channel'" '"Channel"'; do
      printf "%-14s %s\n" "$m" "$(grep -oF "$m" "$HTML" 2>/dev/null | wc -l)"
    done
    echo "=== FIRST 400 CHARS ==="
    head -c 400 "$HTML"; echo
    echo "=== SAMPLE CHANNEL BLOCK (首个频道，完整属性，URL 未截断) ==="
    tr -d '\r\n' < "$HTML" 2>/dev/null \
      | sed -E "s/CTCSetConfig\('Channel',[ ]*'/\n/g; s/'\);/\n/g" \
      | grep -i 'ChannelID=' | head -1
    echo
    ;;
  parse)
    [ -z "${2:-}" ] && { log "用法: $0 parse <html文件>"; exit 1; }
    [ -f "$2" ] || { log "文件不存在: $2"; exit 1; }
    generate_m3u "$2"
    ;;
  install)
    SCRIPT="$(readlink -f "$0")"
    mkdir -p /etc/iptv "$OUT_DIR"
    CRON="/etc/crontabs/root"
    mkdir -p "$(dirname "$CRON")"
    grep -q "$SCRIPT" "$CRON" 2>/dev/null || echo "17 4 * * * $SCRIPT generate >>/tmp/gd-iptv.log 2>&1" >> "$CRON"
    /etc/init.d/cron enable 2>/dev/null
    /etc/init.d/cron start 2>/dev/null
    log "已安装定时任务（每日 04:17 重新鉴权生成列表）"
    log "立即执行一次 ..."
    sh "$SCRIPT" generate
    ;;
  *)
    echo "用法: $0 {generate|discover|capture|diagnose|parse FILE|install}"
    exit 1
    ;;
esac
