#!/bin/sh
#
# v6watch 一键安装（不依赖 OpenWrt SDK）
#
#   wget -O- https://raw.githubusercontent.com/Jonnyan404/openwrt-v6watch/main/install.sh | sh
#   或下载后： sh install.sh
#   本地源码目录： SRC_DIR=/path/to/openwrt-v6watch sh install.sh
#   卸载： sh install.sh --uninstall
#
set -e

REPO=${REPO:-Jonnyan404/openwrt-v6watch}
BRANCH=${BRANCH:-main}

say() { printf '%s\n' "$*"; }
die() {
	say "错误: $*" >&2
	exit 1
}

[ "$(id -u)" = "0" ] || die "需要 root 权限运行"

if [ "$1" = "--uninstall" ]; then
	/etc/init.d/v6watch stop >/dev/null 2>&1 || true
	/etc/init.d/v6watch disable >/dev/null 2>&1 || true
	rm -f /usr/bin/v6watch /etc/init.d/v6watch
	rm -rf /tmp/v6watch
	say "已卸载。配置文件 /etc/config/v6watch 保留，如需彻底清除："
	say "  rm -f /etc/config/v6watch"
	exit 0
fi

# ---- 环境检查 ----
[ -f /etc/openwrt_release ] || say "提示: 没检测到 OpenWrt，继续尝试安装"
command -v ubus >/dev/null 2>&1 || die "缺少 ubus，这似乎不是 OpenWrt 系统"
command -v jsonfilter >/dev/null 2>&1 ||
	say "提示: 没有 jsonfilter，接口自动识别会失效，请手动设置 interface 选项"

# ---- 取源码 ----
if [ -n "$SRC_DIR" ] && [ -d "$SRC_DIR/root" ]; then
	ROOT=$SRC_DIR/root
	say "使用本地源码: $ROOT"
else
	TMP=$(mktemp -d)
	trap 'rm -rf "$TMP"' EXIT
	URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
	say "下载 $URL"
	if command -v wget >/dev/null 2>&1; then
		wget -qO- "$URL" | tar xz -C "$TMP"
	elif command -v curl >/dev/null 2>&1; then
		curl -fsSL "$URL" | tar xz -C "$TMP"
	else
		die "需要 wget 或 curl"
	fi
	ROOT=$(find "$TMP" -maxdepth 2 -type d -name root | head -n 1)
	[ -n "$ROOT" ] || die "下载包结构异常，找不到 root 目录"
fi

# ---- 安装文件 ----
install -m 0755 "$ROOT/usr/bin/v6watch" /usr/bin/v6watch
install -m 0755 "$ROOT/etc/init.d/v6watch" /etc/init.d/v6watch
install -d /etc/uci-defaults
install -m 0755 "$ROOT/etc/uci-defaults/90-v6watch" /etc/uci-defaults/90-v6watch

if [ -f /etc/config/v6watch ]; then
	say "已存在 /etc/config/v6watch，保留现有配置"
else
	install -m 0644 "$ROOT/etc/config/v6watch" /etc/config/v6watch
fi

# ---- 启用并启动 ----
/etc/init.d/v6watch enable
/etc/init.d/v6watch restart >/dev/null 2>&1 || /etc/init.d/v6watch start

say ""
say "安装完成。当前诊断结果："
say ""
/usr/bin/v6watch --diag
say "守护服务状态："
if pgrep -f 'v6watch --daemon' >/dev/null 2>&1; then
	say "  运行中"
else
	say "  未运行，可执行 /etc/init.d/v6watch start 并查看 logread -e v6watch"
fi
say ""
say "查看日志: cat /tmp/v6watch/v6watch.log"
say "调整配置: uci set v6watch.settings.interval=120 && uci commit v6watch && /etc/init.d/v6watch restart"
