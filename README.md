# openwrt-v6watch

**IPv6 出口自愈，并且能告诉你为什么断。**

绝大多数 IPv6 看门狗只做一件事：`ping` 不通 → 重启接口。v6watch 先把故障分层定位，只在确实该动手的时候才动手——因为在很多情况下，重启接口根本没用，反复重启还有副作用。

适用于 OpenWrt / ImmortalWrt（25.x `apk` 与 24.10 及更早的 `opkg` 都支持）。

## 它解决的那类问题

你打开路由器的状态页：地址在、前缀在、默认路由在、邻居表正常、lifetime 一直在续期。IPv4 一切正常。**但 IPv6 一个包都出不去。**

重拨/重启接口就好了，过几天又坏。

这类故障的典型特征是：上游把「这个客户端的前缀归谁」的转发表项丢了（上游重启、清表、加载状态），而路由器仍然拿着旧租约继续 `renew`，双方状态已经脱节，却没有任何一方报错。伴随日志通常是：

```
odhcp6c: Server returned IA_NA status 'No Binding'
odhcp6c: Server returned IA_PD status 'No Binding'
```

`v6watch` 把这种形态命名为 `delegation_lost`，并且**只在这种形态下**重启接口。

## 判定

| verdict | 判据 | 动作 |
|---|---|---|
| `healthy` | 出口正常 | 无 |
| `link_down` | 上游网关 ND 不可达 | 不动，等链路恢复 |
| `no_v6_route` | 接口上没有 IPv6 默认路由 | 不动，等 DHCPv6/RA |
| `egress_down` | 网关可达，连直连前缀的源地址也出不去 | 默认只告警 |
| `delegation_lost` | 网关可达，直连 /64 源地址能出去，委派地址不能 | 重启接口 |
| `unknown_egress` | 网可达、出口不通，但没有 /64 地址可对照 | 重启一次（有冷却） |

关键判据是最后两行那个**源地址对比**：同一个目标、同一时刻、同一个接口，只换源地址。如果直连前缀（SLAAC）的源能出去、而委派的 `IA_NA` / PD 地址出不去，那问题就明确在上游的转发表，而不在本机。

## 不是"ping 不通就重启"

| | 普通看门狗 | v6watch |
|---|---|---|
| 故障定位 | 无，一律重启 | 分层，6 种判定 |
| 重启后复查 | 通常没有 | 有，确认恢复才记 `RESOLVED` |
| 冷却 / 退避 | 通常没有 | 有（默认 10 分钟 / 30 分钟） |
| 运营商关闭 IPv6 时 | 无限重启，每次抖一次 PD | 只告警，不动手 |
| 无线掉线时 | 重启一个 dhcpv6 接口 | 跳过 |
| 接口名 | 要手填 | 自动识别带 IPv6 委派的接口 |

「无限重启」不是危言耸听：如果按 `interval=300s`、阈值 3 次来计算，运营商那天真的关了 IPv6，普通看门狗会每 15 分钟 `down/up` 一次接口，永远不停。

## 安装

### 一键（不需要 SDK）

```sh
wget -O- https://raw.githubusercontent.com/Jonnyan404/openwrt-v6watch/main/install.sh | sh
```

装完会自动跑一次诊断，并启用 procd 服务（开机自启，在 LuCI「系统 → 启动项」里能看到）。

卸载：

```sh
wget -O- https://raw.githubusercontent.com/Jonnyan404/openwrt-v6watch/main/install.sh | sh -s -- --uninstall
```

### 用 SDK 编译成包

```sh
echo "src-git v6watch https://github.com/Jonnyan404/openwrt-v6watch.git" >> feeds.conf.default
./scripts/feeds update v6watch && ./scripts/feeds install v6watch
make menuconfig          # Network -> v6watch
make package/v6watch/compile V=s
```

产物格式（`.apk` / `.ipk`）由 SDK 自身版本决定，同一份 Makefile 通用。

## 使用

```sh
v6watch --diag      # 诊断报告，不修复
v6watch --status    # 一行状态，给脚本消费
v6watch --once      # 检测一次并按需修复
v6watch --daemon    # 守护模式（由 init 托管，一般不需要手动跑）
```

一份真实的输出：

```
v6watch 诊断报告  2026-11-11 11:44:51
----------------------------------------------------
interface       : wwan6 (phy0-sta0)
status          : up
v6 default route: via fe80::9284:8eff:fe41:57b0
upstream gateway: reachable
egress (default): ok
egress (slaac)  : ok  2408:820c:9c39:8280:82af:caff:fe83:3c61
----------------------------------------------------
verdict         : healthy
meaning         : 正常
advice          : 无需处理
```

坏的时候长这样：

```
egress (default): FAIL
egress (slaac)  : ok  2408:820c:9c39:8280:82af:caff:fe83:3c61
----------------------------------------------------
verdict         : delegation_lost
meaning         : 上游不认本机的委派地址（PD / IA_NA），直连前缀正常
advice          : 重启接口可强制重新 DHCPv6 交涉，通常立即恢复
```

## 配置

`/etc/config/v6watch`，也可以用 uci：

```sh
uci set v6watch.settings.interval=120
uci commit v6watch
/etc/init.d/v6watch restart
```

| 选项 | 默认 | 说明 |
|---|---|---|
| `enabled` | `1` | 总开关 |
| `interface` | `auto` | 要监控的接口；`auto` 自动挑带 IPv6 委派的那个 |
| `interval` | `120` | 检测周期（秒） |
| `failure_threshold` | `2` | 连续多少次判定才动手，防抖动 |
| `cooldown` | `600` | 两次修复的最小间隔（秒） |
| `backoff` | `1800` | 连续修复失败后的退避（秒） |
| `auto_repair` | `1` | 关掉就只诊断告警 |
| `repair_egress` | `0` | 是否对 `egress_down` 也尝试修复 |
| `log_level` | `2` | 0 只记错误 / 1 记状态变化 / 2 详细 |

探测目标是独立的 section，可以加多个：

```
config probe 'ali_dns'
	option host '2400:3200::1'
	option enabled '1'
```

建议填国内可达的地址。填一堆被墙的境外地址会让"部分失败"变成常态。

## 日志

```sh
cat /tmp/v6watch/v6watch.log     # 不写 flash，重启清空
logread -e v6watch               # 同步写了一份到 syslog
```

```
[1] WARN: delegation_lost（连续 2/2）
[1] REPAIR: 重启 wwan6（判定 delegation_lost）
[1] RESOLVED: ifup 后已恢复
```

如果看到 `GIVEUP: 连续 N 次修复无效`，说明问题不在委派层，该去查上游设备或运营商了。

## 一个陷阱

在这类配置上，`ip -6 route get <公网v6>` 经常返回 `Network unreachable`，因为 netifd 只装 source-specific 默认路由（`default from <前缀> via ...`），从来不装裸 default。

**这是常态，不是故障。** 别据此判断 IPv6 有问题——`v6watch` 也不会。

## 相关文档

- [案例：一切正常，但 IPv6 一个包都出不去](docs/case-2026-11-delegation-lost.md) —— `delegation_lost` 这档判定的完整排查记录

## License

MIT
