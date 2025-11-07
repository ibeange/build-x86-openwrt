#!/bin/bash

# 打包Toolchain
if [[ $REBUILD_TOOLCHAIN = 'true' ]]; then
    echo -e "\e[1;33m开始打包toolchain目录\e[0m"
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    [ -d ".ccache" ] && (ccache=".ccache"; ls -alh .ccache)
    du -h --max-depth=1 ./staging_dir
    du -h --max-depth=1 ./ --exclude=staging_dir
    tar -I zstdmt -cf $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst staging_dir/host* staging_dir/tool* $ccache
    ls -lh $GITHUB_WORKSPACE/output
    [ -e $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst ] || exit 1
    exit 0
fi

[ -d $GITHUB_WORKSPACE/output ] || mkdir $GITHUB_WORKSPACE/output

color() {
    case $1 in
        cr) echo -e "\e[1;31m$2\e[0m" ;;  # 红色
        cg) echo -e "\e[1;32m$2\e[0m" ;;  # 绿色
        cy) echo -e "\e[1;33m$2\e[0m" ;;  # 黄色
        cb) echo -e "\e[1;34m$2\e[0m" ;;  # 蓝色
        cp) echo -e "\e[1;35m$2\e[0m" ;;  # 紫色
        cc) echo -e "\e[1;36m$2\e[0m" ;;  # 青色
    esac
}

status() {
    local check=$? end_time=$(date '+%H:%M:%S') total_time
    total_time="==> 用时 $[$(date +%s -d $end_time) - $(date +%s -d $begin_time)] 秒"
    [[ $total_time =~ [0-9]+ ]] || total_time=""
    if [[ $check = 0 ]]; then
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $1) [ $(color cg ✔) ] $(echo -e "\e[1m$total_time")
    else
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $1) [ $(color cr ✕) ] $(echo -e "\e[1m$total_time")
    fi
}

find_dir() {
    find $1 -maxdepth 3 -type d -name $2 -print -quit 2>/dev/null
}

print_info() {
    printf "%s %-40s %s %s %s\n" $1 $2 $3 $4 $5
}

# 添加整个源仓库(git clone)
git_clone() {
    local repo_url branch target_dir current_dir
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    if [[ -n "$@" ]]; then
        target_dir="$@"
    else
        target_dir="${repo_url##*/}"
    fi
    git clone -q $branch --depth=1 $repo_url $target_dir 2>/dev/null || {
        print_info $(color cr 拉取) $repo_url [ $(color cr ✕) ]
        return 0
    }
    rm -rf $target_dir/{.git*,README*.md,LICENSE}
    current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
    if ([[ -d $current_dir ]] && rm -rf $current_dir); then
        mv -f $target_dir ${current_dir%/*}
        print_info $(color cg 替换) $target_dir [ $(color cg ✔) ]
    else
        mv -f $target_dir $destination_dir
        print_info $(color cb 添加) $target_dir [ $(color cb ✔) ]
    fi
}

# 添加源仓库内的指定目录
clone_dir() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        print_info $(color cr 拉取) $repo_url [ $(color cr ✕) ]
        return 0
    }
    local target_dir source_dir current_dir
    for target_dir in "$@"; do
        source_dir=$(find_dir "$temp_dir" "$target_dir")
        [[ -d $source_dir ]] || \
        source_dir=$(find $temp_dir -maxdepth 4 -type d -name $target_dir -print -quit) && \
        [[ -d $source_dir ]] || {
            print_info $(color cr 查找) $target_dir [ $(color cr ✕) ]
            continue
        }
        current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
        if ([[ -d $current_dir ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            print_info $(color cg 替换) $target_dir [ $(color cg ✔) ]
        else
            mv -f $source_dir $destination_dir
            print_info $(color cb 添加) $target_dir [ $(color cb ✔) ]
        fi
    done
    rm -rf $temp_dir
}

# 添加源仓库内的所有目录
clone_all() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        print_info $(color cr 拉取) $repo_url [ $(color cr ✕) ]
        return 0
    }
    local target_dir source_dir current_dir
    for target_dir in $(ls -l $temp_dir/$@ | awk '/^d/ {print $NF}'); do
        source_dir=$(find_dir "$temp_dir" "$target_dir")
        current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
        if ([[ -d $current_dir ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            print_info $(color cg 替换) $target_dir [ $(color cg ✔) ]
        else
            mv -f $source_dir $destination_dir
            print_info $(color cb 添加) $target_dir [ $(color cb ✔) ]
        fi
    done
    rm -rf $temp_dir
}

# 设置编译源码与分支
REPO_URL="https://github.com/immortalwrt/immortalwrt"
echo "REPO_URL=$REPO_URL" >>$GITHUB_ENV
REPO_BRANCH="openwrt-24.10"
echo "REPO_BRANCH=$REPO_BRANCH" >>$GITHUB_ENV

# 拉取编译源码
begin_time=$(date '+%H:%M:%S')
[[ $REPO_BRANCH != "master" ]] && BRANCH="-b $REPO_BRANCH --single-branch"
cd /workdir
git clone -q $BRANCH $REPO_URL openwrt
status "拉取编译源码"
ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
[ -d openwrt ] && cd openwrt || exit
echo "OPENWRT_PATH=$PWD" >>$GITHUB_ENV

# 生成全局变量
begin_time=$(date '+%H:%M:%S')
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cp -f $GITHUB_WORKSPACE/$CONFIG_FILE .config
make defconfig 1>/dev/null 2>&1

# 源仓库与分支
SOURCE_REPO=$(basename $REPO_URL)
echo "SOURCE_REPO=$SOURCE_REPO" >>$GITHUB_ENV
echo "LITE_BRANCH=${REPO_BRANCH#*-}" >>$GITHUB_ENV

# 平台架构
TARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_BOARD/{print $2}' .config)
SUBTARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_SUBTARGET/{print $2}' .config)
DEVICE_TARGET=$TARGET_NAME-$SUBTARGET_NAME
echo "DEVICE_TARGET=$DEVICE_TARGET" >>$GITHUB_ENV

# 内核版本
KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[^ ]+' target/linux/$TARGET_NAME/Makefile)
KERNEL_VERSION=$(awk -F '-' '/KERNEL/{print $2}' include/kernel-$KERNEL | awk '{print $1}')
echo "KERNEL_VERSION=$KERNEL_VERSION" >>$GITHUB_ENV

# Toolchain缓存文件名
TOOLS_HASH=$(git log --pretty=tformat:"%h" -n1 tools toolchain)
CACHE_NAME="$SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-cache-$TOOLS_HASH"
echo "CACHE_NAME=$CACHE_NAME" >>$GITHUB_ENV

# 源码更新信息
COMMIT_AUTHOR=$(git show -s --date=short --format="作者: %an")
echo "COMMIT_AUTHOR=$COMMIT_AUTHOR" >>$GITHUB_ENV
COMMIT_DATE=$(git show -s --date=short --format="时间: %ci")
echo "COMMIT_DATE=$COMMIT_DATE" >>$GITHUB_ENV
COMMIT_MESSAGE=$(git show -s --date=short --format="内容: %s")
echo "COMMIT_MESSAGE=$COMMIT_MESSAGE" >>$GITHUB_ENV
COMMIT_HASH=$(git show -s --date=short --format="hash: %H")
echo "COMMIT_HASH=$COMMIT_HASH" >>$GITHUB_ENV
status "生成全局变量"

# 下载并部署Toolchain
if [[ $TOOLCHAIN = 'true' ]]; then
    cache_xa=$(curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | awk -F '"' '/download_url/{print $4}' | grep $CACHE_NAME)
    cache_xc=$(curl -sL api.github.com/repos/haiibo/toolchain-cache/releases | awk -F '"' '/download_url/{print $4}' | grep $CACHE_NAME)
    if [[ $cache_xa || $cache_xc ]]; then
        begin_time=$(date '+%H:%M:%S')
        [ $cache_xa ] && wget -qc -t=3 $cache_xa || wget -qc -t=3 $cache_xc
        [ -e *.tzst ]; status "下载toolchain缓存文件"
        [ -e *.tzst ] && {
            begin_time=$(date '+%H:%M:%S')
            tar -I unzstd -xf *.tzst || tar -xf *.tzst
            [ $cache_xa ] || (cp *.tzst $GITHUB_WORKSPACE/output && echo "OUTPUT_RELEASE=true" >>$GITHUB_ENV)
            sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
            [ -d staging_dir ]; status "部署toolchain编译缓存"
        }
    else
        echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
    fi
else
    echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
fi

# 更新&安装插件
begin_time=$(date '+%H:%M:%S')
./scripts/feeds update -a 1>/dev/null 2>&1
./scripts/feeds install -a 1>/dev/null 2>&1
status "更新&安装插件"

color cr "更换golang版本"
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

color cy "添加&替换插件"

# 创建插件保存目录
destination_dir="package/A"
[ -d $destination_dir ] || mkdir -p $destination_dir

# 添加额外插件
# clone_all https://github.com/sbwml/luci-app-openlist2
clone_all https://github.com/sbwml/luci-app-mosdns
# clone_all https://github.com/brvphoenix/luci-app-wrtbwmon
# clone_all https://github.com/brvphoenix/wrtbwmon

# UU游戏加速器
clone_dir https://github.com/kiddin9/kwrt-packages luci-app-uugamebooster
clone_dir https://github.com/kiddin9/kwrt-packages uugamebooster

# ddns-go 动态域名
clone_all https://github.com/sirpdboy/luci-app-ddns-go

# 关机
clone_all https://github.com/sirpdboy/luci-app-poweroffdevice

# luci-app-filemanager
git_clone https://github.com/sbwml/luci-app-filemanager luci-app-filemanager

# 添加 Turbo ACC 网络加速
# git_clone https://github.com/kiddin9/kwrt-packages luci-app-turboacc

# 科学上网插件
clone_all https://github.com/nikkinikki-org/OpenWrt-nikki
clone_dir https://github.com/vernesong/OpenClash luci-app-openclash
clone_dir https://github.com/kiddin9/kwrt-packages luci-app-v2ray-server

# Themes
git_clone https://github.com/kiddin9/luci-theme-edge
git_clone https://github.com/jerrykuku/luci-theme-argon
git_clone https://github.com/jerrykuku/luci-app-argon-config

# 强制禁用旧版 firewall (fw3)
sed -i 's/CONFIG_PACKAGE_firewall=y/# CONFIG_PACKAGE_firewall is not set/g' .config

# 强制启用新版 firewall4 (fw4)
# (先删除旧的设置行，再确保它是y)
sed -i '/CONFIG_PACKAGE_firewall4/d' .config
echo "CONFIG_PACKAGE_firewall4=y" >> .config

# D 确保 LuCI 防火墙应用被选中 (它会自动适配 fw4)
sed -i '/CONFIG_PACKAGE_luci-app-firewall/d' .config
echo "CONFIG_PACKAGE_luci-app-firewall=y" >> .config

# 加载个人设置
begin_time=$(date '+%H:%M:%S')

[ -e $GITHUB_WORKSPACE/files ] && mv $GITHUB_WORKSPACE/files files

# ==============================================================
# 调整：将防火墙清理移动到这里
# 确保 /files/etc 目录存在
mkdir -p files/etc/

# 覆盖或创建一个空的 firewall.user 文件
# 这将清除任何可能存在的旧 iptables 规则，从根本上解决 fw4 警告
echo "# This file is intentionally left blank by the build script." > files/etc/firewall.user
echo "Cleaned files/etc/firewall.user to prevent fw4 legacy warnings."
# ==============================================================

# 设置固件rootfs大小
if [ $PART_SIZE ]; then
    sed -i '/ROOTFS_PARTSIZE/d' $GITHUB_WORKSPACE/$CONFIG_FILE
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE" >>$GITHUB_WORKSPACE/$CONFIG_FILE
fi

# 修改默认IP
[ $DEFAULT_IP ] && sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 设置 root 用户密码为 password
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# 更改 Argon 主题背景
cp -f $GITHUB_WORKSPACE/images/bg1.jpg feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

# 删除主题默认设置
# find $destination_dir/luci-theme-*/ -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \;

echo
status "菜单 调整..."
sed -i 's|/services/|/control/|' feeds/luci/applications/luci-app-wol/root/usr/share/luci/menu.d/luci-app-wol.json
#sed -i 's|/services/|/network/|' feeds/luci/applications/luci-app-nlbwmon/root/usr/share/luci/menu.d/luci-app-nlbwmon.json
#sed -i 's|/services/|/nas/|' feeds/luci/applications/luci-app-alist/root/usr/share/luci/menu.d/luci-app-openlist2.json
sed -i '/"title": "Nikki",/a \        "order": -9,' package/waynesg/luci-app-nikki/luci-app-nikki/root/usr/share/luci/menu.d/luci-app-nikki.json
sed -i 's/("OpenClash"), 50)/("OpenClash"), -10)/g' feeds/luci/applications/luci-app-openclash/luasrc/controller/openclash.lua
sed -i 's/"网络存储"/"存储"/g' `grep "网络存储" -rl ./`
sed -i 's/"软件包"/"软件管理"/g' `grep "软件包" -rl ./`

# 重命名
sed -i 's,UPnP IGD 和 PCP,UPnP,g' feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po
        
status "插件 重命名..."
echo "重命名系统菜单"
#status menu
sed -i 's/"概览"/"系统概览"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
sed -i 's/"路由"/"路由映射"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
#system menu
sed -i 's/"系统"/"系统设置"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
sed -i 's/"管理权"/"权限管理"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
sed -i 's/"重启"/"立即重启"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
sed -i 's/"备份与升级"/"备份升级"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
sed -i 's/"挂载点"/"挂载路径"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
sed -i 's/"启动项"/"启动管理"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po
sed -i 's/"软件包"/"软件管理"/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po

# 【<--- 修改】 修正 Argon-config 重命名的路径
# if [ -f "package/A/luci-app-argon-config/po/zh_Hans/argon-config.po" ]; then
#     sed -i 's/"Argon 主题设置"/"主题设置"/g' package/A/luci-app-argon-config/po/zh_Hans/argon-config.po
# fi

# 精简 UPnP 菜单名称
sed -i 's#\"title\": \"UPnP IGD \& PCP/NAT-PMP\"#\"title\": \"UPnP服务\"#g' feeds/luci/applications/luci-app-upnp/root/usr/share/luci/menu.d/luci-app-upnp.json

# 更改 ttyd 顺序和名称
sed -i '3a \		"order": 10,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i 's/"终端"/"命令终端"/g' feeds/luci/applications/luci-app-ttyd/po/zh_Hans/ttyd.po

# 设置 nlbwmon 独立菜单
sed -i 's/524288/16777216/g' feeds/packages/net/nlbwmon/files/nlbwmon.config
sed -i 's/option commit_interval.*/option commit_interval 24h/g' feeds/packages/net/nlbwmon/files/nlbwmon.config
sed -i 's/services\/nlbw/nlbw/g; /path/s/admin\///g' feeds/luci/applications/luci-app-nlbwmon/root/usr/share/luci/menu.d/luci-app-nlbwmon.json
sed -i 's/services\///g' feeds/luci/applications/luci-app-nlbwmon/htdocs/luci-static/resources/view/nlbw/config.js

echo "重命名网络菜单"
#network
sed -i 's/"接口"/"网络接口"/g' `grep "接口" -rl ./`
sed -i 's/DHCP\/DNS/DNS设定/g' feeds/luci/modules/luci-base/po/zh_Hans/base.po

sed -i 's/"Bandix 流量监控"/"流量监控"/g' package/waynesg/luci-app-bandix/luci-app-bandix/po/zh_Hans/bandix.po

# x86 型号只显示 CPU 型号
sed -i 's/${g}.*/${a}${b}${c}${d}${e}${f}${hydrid}/g' package/emortal/autocore/files/x86/autocore

# 最大连接数修改为65535
sed -i '$a net.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf

# 修改本地时间格式
sed -i 's/os.date()/os.date("%a %Y-%m-%d %H:%M:%S")/g' package/emortal/autocore/files/*/index.htm

#nlbwmon 修复log警报
sed -i '$a net.core.wmem_max=16777216' package/base-files/files/etc/sysctl.conf
sed -i '$a net.core.rmem_max=16777216' package/base-files/files/etc/sysctl.conf

# 调整 V2ray服务器 到 VPN 菜单 (修正路径)
if [ -d "package/A/luci-app-v2ray-server" ]; then
    sed -i 's/services/vpn/g' package/A/luci-app-v2ray-server/luasrc/controller/*.lua
    sed -i 's/services/vpn/g' package/A/luci-app-v2ray-server/luasrc/model/cbi/v2ray_server/*.lua
    sed -i 's/services/vpn/g' package/A/luci-app-v2ray-server/luasrc/view/v2ray_server/*.htm
fi

# 显示增加编译时间
sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION=\"ImmortalWrt By @Ethan\"/g" package/base-files/files/etc/openwrt_release
sed -i "s/OPENWRT_RELEASE=.*/OPENWRT_RELEASE=\"ImmortalWrt R$(TZ=UTC-8 date +'%y.%-m.%-d') (By @Ethan build $(TZ=UTC-8 date '+%Y-%m-%d %H:%M'))\"/g" package/base-files/files/usr/lib/os-release
echo -e "\e[41m当前写入的编译时间:\e[0m \e[33m$(grep 'OPENWRT_RELEASE' package/base-files/files/usr/lib/os-release)\e[0m"


# 修复 Makefile 路径
find $destination_dir/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i \
    -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?' \
    -e 's?include \.\./\.\./\(lang\|devel\)?include $(TOPDIR)/feeds/packages/\1?' {}

# 转换插件语言翻译
for e in $(ls -d $destination_dir/luci-*/po feeds/luci/applications/luci-*/po); do
    if [[ -d $e/zh-cn && ! -d $e/zh_Hans ]]; then
        ln -s zh-cn $e/zh_Hans 2>/dev/null
    elif [[ -d $e/zh_Hans && ! -d $e/zh-cn ]]; then
        ln -s zh_Hans $e/zh-cn 2>/dev/null
    fi
done
status "加载个人设置"

# 更新配置文件
begin_time=$(date '+%H:%M:%S')
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cp -f $GITHUB_WORKSPACE/$CONFIG_FILE .config
make defconfig 1>/dev/null 2>&1
status "更新配置文件"

# 下载openclash运行内核
[[ $CLASH_KERNEL =~ amd64|arm64|armv7|armv6|armv5|386 ]] && grep -q "luci-app-openclash=y" .config && {
    begin_time=$(date '+%H:%M:%S')
    chmod +x $GITHUB_WORKSPACE/scripts/preset-clash-core.sh
    $GITHUB_WORKSPACE/scripts/preset-clash-core.sh $CLASH_KERNEL
    status "下载openclash运行内核"
}

# 下载zsh终端工具
[[ $ZSH_TOOL = 'true' ]] && grep -q "zsh=y" .config && {
    begin_time=$(date '+%H:%M:%S')
    chmod +x $GITHUB_WORKSPACE/scripts/preset-terminal-tools.sh
    $GITHUB_WORKSPACE/scripts/preset-terminal-tools.sh
    status "下载zsh终端工具"
}

echo -e "$(color cy 当前编译机型) $(color cb $SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-$KERNEL_VERSION)"

# 更改固件文件名
# sed -i "s/\$(VERSION_DIST_SANITIZED)/$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION/" include/image.mk
# sed -i "/IMG_PREFIX:/ {s/=/=$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION-\$(shell date +%y.%m.%d)-/}" include/image.mk

color cp "脚本运行完成！"
