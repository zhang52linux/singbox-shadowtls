#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

ps=$(openssl rand -base64 16)

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前你的VPS的操作系统暂未支持！" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        *) red " 不支持的CPU架构！" && exit 1 ;;
    esac
    return 0
}

install_singbox(){
    version_tag=$(curl -Ls "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$version_tag" ]]; then
        red "检测 Sing-box 版本失败，可能是超出 Github API 限制，请稍后再试"
        exit 1
    fi
    download_tag=$(echo $version_tag | sed "s/v//g")


    if [[ $SYSTEM == "CentOS" ]]; then
        wget -N --no-check-certificate https://github.com/SagerNet/sing-box/releases/download/$version_tag/sing-box_"$download_tag"_linux_$(archAffix).rpm
        rpm -i sing-box_"$download_tag"_linux_$(archAffix).rpm
        rm -f sing-box_"$download_tag"_linux_$(archAffix).rpm
    else
        wget -N --no-check-certificate https://github.com/SagerNet/sing-box/releases/download/$version_tag/sing-box_"$download_tag"_linux_$(archAffix).deb
        dpkg -i sing-box_"$download_tag"_linux_$(archAffix).deb
        rm -f sing-box_"$download_tag"_linux_$(archAffix).deb
    fi

    rm -f /etc/sing-box/config.json
    wget --no-check-certificate -O /etc/sing-box/config.json https://raw.githubusercontent.com/lanhebe/singbox-shadowtls/main/configs/server-config.json
    
    mkdir /root/sing-box
    wget --no-check-certificate -O /root/sing-box/client-sockshttp.json https://raw.githubusercontent.com/lanhebe/singbox-shadowtls/main/configs/client-sockshttp.json
    wget --no-check-certificate -O /root/sing-box/client-tun.json https://raw.githubusercontent.com/lanhebe/singbox-shadowtls/main/configs/client-tun.json
    
    wgcfv6status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2) 
    wgcfv4status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $wgcfv4status =~ "on"|"plus" ]] || [[ $wgcfv6status =~ "on"|"plus" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        v6=$(curl -s6m8 api64.ipify.org -k)
        v4=$(curl -s4m8 api64.ipify.org -k)
        wg-quick up wgcf >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
    else
        v6=$(curl -s6m8 api64.ipify.org -k)
        v4=$(curl -s4m8 api64.ipify.org -k)
    fi
    
    if [[ -n $v4 ]]; then
        sed -i "s/填写服务器ip地址/${v4}/g" /root/sing-box/client-sockshttp.json
        sed -i "s/填写服务器ip地址/${v4}/g" /root/sing-box/client-tun.json
    elif [[ -n $v6 ]]; then
        sed -i "s/填写服务器ip地址/[${v6}]/g" /root/sing-box/client-sockshttp.json
        sed -i "s/填写服务器ip地址/[${v6}]/g" /root/sing-box/client-tun.json
    fi
    
    sed -i "s/填写自定义密码/${ps}/g" /etc/sing-box/config.json
    sed -i "s/填写自定义密码/${ps}/g" /root/sing-box/client-sockshttp.json
    sed -i "s/填写自定义密码/${ps}/g" /root/sing-box/client-tun.json

    
    systemctl start sing-box
    systemctl enable sing-box

    if [[ -n $(service sing-box status 2>/dev/null | grep "inactive") ]]; then
        red "Sing-box 安装失败"
    elif [[ -n $(service sing-box status 2>/dev/null | grep "active") ]]; then
        green "Sing-box 安装成功"
        yellow "客户端Socks / HTTP代理模式配置文件已保存到 /root/sing-box/client-sockshttp.json 请自行下载到本地使用"
        yellow "客户端TUN模式配置文件已保存到 /root/sing-box/client-tun.json 请自行下载到本地使用"
    fi
}

uninstall_singbox(){
    systemctl stop sing-box
    systemctl disable sing-box
    rm -rf /root/sing-box
    rm -rf /etc/sing-box
    ${PACKAGE_UNINSTALL} sing-box
    green "Sing-box 已彻底卸载完成"
}

start_singbox() {
    systemctl start sing-box
    green "Sing-box 已启动！"
}

stop_singbox() {
    systemctl stop sing-box
    green "Sing-box 已停止！"
}

restart_singbox(){
    systemctl restart sing-box
    green "Sing-box 已重启！"
}

menu(){
    clear
    echo "#############################################################"
    echo -e "# ${RED} Sing-box+ShadowTLS  一键管理脚本${PLAIN}                         #"
    echo -e "# ${YELLOW} 脚本适用于"Ubuntu" "CentOS" "CentOS" "Fedora" ${PLAIN}                   #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Sing-box"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Sing-box${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 启动 Sing-box"
    echo -e " ${GREEN}4.${PLAIN} 重启 Sing-box"
    echo -e " ${GREEN}5.${PLAIN} 停止 Sing-box"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出"
    echo ""
    read -rp "请输入选项 [0-5]：" menuChoice
    case $menuChoice in
        1) install_singbox ;;
        2) uninstall_singbox ;;
        3) start_singbox ;;
        4) restart_singbox ;;
        5) stop_singbox ;;
        *) exit 1 ;;
    esac
}

menu
