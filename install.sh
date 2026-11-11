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

	# 用 codeload 直连：github.com 的 archive 链接会 302 跳转，
	# 部分网络环境下重定向会被拦，拿到的就不是 tar.gz 了。
	PKG=$TMP/archive.tar.gz
	ok=0
	for URL in \
		"https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" \
		"https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"; do
		say "下载 $URL"
		if command -v wget >/dev/null 2>&1; then
			wget -q -O "$PKG" --timeout=30 "$URL" || continue
		elif command -v curl >/dev/null 2>&1; then
			curl -fsSL --max-time 30 -o "$PKG" "$URL" || continue
		else
			die "需要 wget 或 curl"
		fi
		if tar tzf "$PKG" >/dev/null 2>&1; then
			ok=1
			break
		fi
		say "  这个地址拿到的不是有效的压缩包，换下一个"
	done
	[ "$ok" = "1" ] || die "下载失败。可直接下载仓库后本地安装： SRC_DIR=/path/to/openwrt-v6watch sh install.sh"

	tar xzf "$PKG" -C "$TMP" || die "解压失败"
	ROOT=$(find "$TMP" -maxdepth 2 -type d -name root | head -n 1)
	[ -n "$ROOT" ] || die "下载包结构异常，找不到 root 目录"
fi

# ---- 安装文件 ----
# 不用 install：OpenWrt 的 busybox 里没有这个命令
put() {
	cp "$1" "$2" && chmod "$3" "$2" || die "写入 $2 失败"
}

put "$ROOT/usr/bin/v6watch" /usr/bin/v6watch 0755
put "$ROOT/etc/init.d/v6watch" /etc/init.d/v6watch 0755
mkdir -p /etc/uci-defaults
put "$ROOT/etc/uci-defaults/90-v6watch" /etc/uci-defaults/90-v6watch 0755

if [ -f /etc/config/v6watch ]; then
	say "已存在 /etc/config/v6watch，保留现有配置"
else
	put "$ROOT/etc/config/v6watch" /etc/config/v6watch 0644
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
