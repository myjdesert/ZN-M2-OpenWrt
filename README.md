# ZN-M2 OpenWrt 固件编译项目

为兆能讯通 ZN-M2 路由器（IPQ6000）定制的 ImmortalWrt 固件编译方案。

## 设备信息

| 项目 | 参数 |
|------|------|
| 设备型号 | 兆能讯通 ZN-M2 |
| 处理器 | Qualcomm IPQ6000 (ARM Cortex-A53, 1.2GHz) |
| 内存 | 1GB（已扩容） |
| 闪存 | 128MB NAND（可用约94MB） |
| WiFi | WiFi6 双频 (ath11k) — **本固件已禁用** |
| 编译目标 | qualcommax / ipq60xx / zn_m2 |

## 固件特性

- **ImmortalWrt v25.12.1** 稳定版基础系统（6.12内核）+ ZN-M2设备补丁
- **PASSWALL** 代理工具（含 Xray-core + sing-box 双核心）
- **rtp2httpd** IPTV组播转单播HTTP流
- **集客AC** 无线AP控制器（gecoosac，管理集客AP 7.6+）
- **广东电信IPTV内网融合** 预配置（双线独立拨号 + 策略路由）
- **TurboACC** 网络加速
- **NSS硬件加速** QCA NSS驱动全系列
- **VLAN支持** kmod-8021q（可用但非默认启用）
- **中文LuCI界面** 简体中文
- **精简固件** 无WiFi，针对128MB NAND优化空间

## 目录结构

```
ZN-M2-OpenWrt/
├── .github/workflows/
│   └── build-firmware.yml      # GitHub Actions 云编译工作流
├── configs/
│   └── zn-m2.config            # 编译配置文件
├── files/                      # 自定义文件（刷入固件）
│   └── etc/
│       ├── config/
│       │   ├── network         # 网络配置（双线PPPoE + 策略路由）
│       │   ├── firewall        # 防火墙配置（含IPTV区域规则）
│       │   ├── dhcp            # DHCP配置
│       │   └── system          # 系统配置（时区等）
│       └── uci-defaults/
│           └── zz-iptv-fusion.sh  # 首次启动IPTV初始化
├── scripts/
│   ├── feeds.conf.custom       # 自定义feeds源（passwall）
│   ├── diy-part1.sh            # DIY脚本1（feeds安装前）
│   └── diy-part2.sh            # DIY脚本2（feeds安装后）
├── build-local.sh              # 本地编译脚本（Linux）
└── README.md                   # 本文档
```

---

## 编译方法

### 方法一：GitHub Actions 云编译（推荐）

无需本地Linux环境，在GitHub上免费编译。

#### 步骤

1. **Fork 本项目**
   - 登录 GitHub 账号
   - 将本项目 Fork 到自己的仓库

2. **运行编译**
   - 进入你 Fork 后的仓库页面
   - 点击顶部 **Actions** 标签
   - 在左侧选择 **Build ZN-M2 OpenWrt Firmware**
   - 点击右侧 **Run workflow** 按钮
   - 选择参数：
     - 直接点击 "Run workflow" 即可（使用固定 v25.12.1 稳定版）
     - 无需额外参数
   - 点击绿色 **Run workflow** 按钮开始编译

3. **等待编译完成**
   - 编译约需 3~5 小时
   - 可在 Actions 页面查看实时日志
   - 编译状态变为绿色 ✓ 表示成功

4. **下载固件**
   - 编译完成后，在仓库主页 **Releases** 页面下载
   - 或在 Actions 运行详情页面的 **Artifacts** 区域下载

#### 编译产物说明

| 文件 | 用途 |
|------|------|
| `*-sysupgrade.bin` | 从已有 OpenWrt 系统升级（推荐） |
| `*-factory.ubi` | 通过 U-Boot 刷入（首次刷机） |
| `sha256sums.txt` | 文件校验和 |
| `zn-m2-build-config` | 编译配置记录 |

---

### 方法二：本地编译（需要Linux环境）

适用于有 Ubuntu/Debian 环境或 WSL2 的用户。

#### 前置条件

- Ubuntu 22.04+ 或 Debian 12+（或 WSL2）
- 至少 20GB 可用磁盘空间
- 至少 4GB 内存（推荐8GB+）

#### 编译步骤

```bash
# 1. 克隆本项目
git clone <your-fork-url> ZN-M2-OpenWrt
cd ZN-M2-OpenWrt

# 2. 运行编译脚本
chmod +x build-local.sh
./build-local.sh
```

脚本会自动完成：安装依赖 → 克隆源码 → 配置feeds → 应用配置 → 下载源码 → 编译

编译完成后，固件文件在 `openwrt/bin/targets/qualcommax/ipq60xx/` 目录下。

#### 手动编译（高级）

```bash
# 安装依赖
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
  python3-distutils python3-setuptools rsync unzip zlib1g-dev

# 克隆源码
git clone --depth 1 -b v25.12.1 https://github.com/immortalwrt/immortalwrt openwrt
cd openwrt

# 添加feeds
cat ../scripts/feeds.conf.custom | grep -v '^#' >> feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a

# 添加rtp2httpd
../scripts/diy-part2.sh

# 复制自定义文件和配置
cp -r ../files/* .
cp ../configs/zn-m2.config .config
make defconfig

# 下载并编译
make download -j$(nproc)
make -j$(nproc) V=s
```

---

## 刷机方法

### 前提条件

- 已刷入暗云U-Boot（支持网页刷机救砖）
- 已扩容内存至512MB以上（推荐1GB）

### 从已有OpenWrt升级

1. 登录 OpenWrt LuCI 后台
2. 进入 **系统** → **备份/升级**
3. 上传 `*-sysupgrade.bin` 文件
4. 勾选 **保留配置**（可选）
5. 点击 **执行升级**

或通过SSH：
```bash
scp *-sysupgrade.bin root@192.168.0.1:/tmp/
ssh root@192.168.0.1
sysupgrade -n /tmp/*-sysupgrade.bin
```

### 通过U-Boot刷入（首次刷机）

1. 断电，按住路由器Reset按钮
2. 接通电源，保持按住5秒后松开
3. 电脑设置IP为 `192.168.0.2`，网线连接路由器LAN口
4. 浏览器访问 `192.168.0.1`（U-Boot网页界面）
5. 上传 `*-factory.ubi` 文件刷入

---

## 广东电信IPTV内网融合配置

### 工作原理

```
光猫桥接 ──→ ZN-M2 WAN口 (PPPoE宽带拨号, metric 10)
光猫桥接 ──→ ZN-M2 LAN1口 (PPPoE IPTV拨号, table 100, metric 20)
                ├── 策略路由: IPTV网段走 table 100
                │   183.59/16, 125.88/16, 59.37/16, 202.105/16 (鉴权/回看)
                │   239.77/16 (组播直播), 10/8 (IPTV内网)
                └── rtp2httpd ──→ 组播转单播HTTP流
                      └── 内网设备 http://192.168.0.1:5555 观看
```

### 配置步骤

#### 1. 配置双线PPPoE拨号

首次启动后，通过SSH或LuCI配置两个PPPoE连接：

```bash
# 设置宽带账号密码（WAN口）
uci set network.wan.username='你的宽带账号'
uci set network.wan.password='你的宽带密码'

# 设置IPTV账号密码（LAN1口）
uci set network.iptv.username='jmITVxxxxx@iptv.gd'
uci set network.iptv.password='你的IPTV密码'

uci commit network
/etc/init.d/network restart
```

> **注意：** IPTV账号格式通常为 `jmITVxxxxx@iptv.gd`，密码为机顶盒底贴密码。
> WAN口和LAN1口需要分别连接到光猫的两个LAN口（或两根光纤桥接）。

#### 2. 验证策略路由

固件已预配置策略路由，IPTV网段走 table 100：

```bash
# 查看IPTV拨号状态
ifconfig iptv

# 查看策略路由规则
ip rule show | grep 100

# 查看路由表100
ip route show table 100

# 测试IPTV网段路由
ip route get 183.59.0.1
```

预期结果：IPTV网段（183.59/16, 125.88/16, 59.37/16, 202.105/16, 239.77/16, 10/8）应通过 IPTV PPPoE 接口路由。

#### 3. 配置rtp2httpd

rtp2httpd将IPTV组播RTP流转换为HTTP流，方便内网设备观看。

1. 登录 LuCI → **服务** → **rtp2httpd**
2. 确认以下设置：
   - 绑定地址: `0.0.0.0`
   - 绑定端口: `5555`
   - 组播接口: `iptv`（IPTV PPPoE接口）
3. 添加频道列表（组播地址）

**广东电信常见频道组播地址（239.77.x.x，仅供参考）：**

```
# 频道列表格式（rtp2httpd）
# 频道名, 组播地址:端口
CCTV-1, 239.77.0.1:5000
CCTV-2, 239.77.0.2:5000
CCTV-3, 239.77.0.3:5000
...
```

> **注意：** 组播地址因地区和时间可能变化，请通过抓包获取最新地址。
> 
> 抓包方法：在IPTV机顶盒观看频道时，在路由器SSH中运行：
> ```bash
> tcpdump -i iptv -nn host 239.77.0.0/16 and udp
> ```

#### 4. 观看IPTV

配置完成后，在内网设备上：

- **浏览器直接观看：** `http://192.168.0.1:5555`
- **VLC播放器：** 添加网络流 `http://192.168.0.1:5555/stream?id=频道ID`
- **播放列表：** `http://192.168.0.1:5555/playlist.m3u`

#### 5. 验证IPTV连接

```bash
# 查看IPTV拨号状态
ifconfig iptv

# 查看策略路由
ip rule show | grep 100
ip route show table 100

# 测试IPTV网段连通性
ping -c 3 -I iptv 183.59.0.1

# 查看组播组成员
cat /proc/net/igmp
```

---

## PASSWALL 配置

### 首次配置

1. 登录 LuCI → **服务** → **PassWall**
2. 在 **节点列表** 中添加你的代理节点
3. 在 **基本设置** 中：
   - TCP节点：选择你的节点
   - UDP节点：选择你的节点
4. 点击 **保存并应用**

### 注意事项

- 固件包含 **Xray-core** + **sing-box** 双核心
- Xray-core自2026年6月起要求自签证书配置pinnedPeerCertSha256参数

---

## 常见问题

### Q: 编译失败怎么办？

**A:** 常见原因及解决：
1. **下载失败：** 网络问题，重新运行编译
2. **空间不足：** GitHub Actions默认磁盘空间有限，已在工作流中清理
3. **包冲突：** 检查.config中的包依赖关系
4. **QCA组件编译失败：** 这是已知问题，重试即可

### Q: 固件刷入后无法启动？

**A:**
1. 确认已刷入正确的暗云U-Boot
2. 确认内存已扩容至512MB以上
3. 尝试使用factory.ubi而非sysupgrade.bin
4. 通过U-Boot救砖

### Q: WiFi无法使用？

**A:** 本固件已禁用WiFi以节省NAND空间。如需WiFi功能：
1. 需修改 `configs/zn-m2.config`，移除 WiFi 包的 `# ... is not set` 注释
2. 修改 `scripts/diy-part2.sh`，移除 WiFi patch 步骤
3. 重新编译固件

### Q: IPTV无法观看？

**A:** 按以下顺序排查：
1. **IPTV拨号是否成功：** `ifconfig iptv`（是否有IP地址）
2. **策略路由是否生效：** `ip rule show | grep 100`
3. **IPTV网段路由是否正确：** `ip route get 183.59.0.1`（应走iptv接口）
4. **能否收到组播流：** `tcpdump -i iptv -nn udp port 5000`
5. **rtp2httpd是否运行：** `/etc/init.d/rtp2httpd status`
6. **IPTV账号密码是否正确：** 检查 `/etc/config/network` 中的 IPTV PPPoE 配置

### Q: NAND空间不够？

**A:** 精简方案：
1. WiFi已禁用，节省约15MB
2. 在.config中注释掉不需要的包
3. 使用更激进的squashfs压缩
4. 考虑使用暗云扩容版U-Boot（增大rootfs分区）

### Q: 如何修改默认IP？

**A:** 在编译前修改 `files/etc/config/network`：
```
config interface 'lan'
    option ipaddr '192.168.X.1'  # 修改为你想要的IP
```

或在刷机后通过SSH修改：
```bash
uci set network.lan.ipaddr='192.168.X.1'
uci commit network
/etc/init.d/network restart
```

---

## 技术参考

- [ImmortalWrt 官方](https://github.com/immortalwrt/immortalwrt)
- [ImmortalWrt v25.12.1 稳定版](https://github.com/immortalwrt/immortalwrt/releases/tag/v25.12.1)
- [PASSWALL 源码](https://github.com/Openwrt-Passwall/openwrt-passwall)
- [rtp2httpd 源码](https://github.com/stackia/rtp2httpd)

---

## 免责声明

本固件仅供学习和研究使用。使用者需遵守当地法律法规，自行承担使用风险。作者不对任何人因使用本固件所遭受的损失承担责任。
