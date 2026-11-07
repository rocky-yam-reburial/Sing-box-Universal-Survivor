#!/bin/sh
# ==========================================================
# Sing-box 面板 v4.5 Pro (配置智能继承 / 双引擎常驻生存版)
# Author: rocky-yam-reburial
# Repo: Sing-box-Universal-Survivor
# ==========================================================

if [ "$(id -u)" != "0" ]; then
    echo "[-] 请使用 root 权限运行此脚本"
    exit 1
fi

DIR="/etc/sing-box"
CFG="$DIR/config.json"
ENV="$DIR/node_info.env"
BIN="/usr/bin/sing-box"
LOG="/var/log/sing-box.log"

init_env() {
    mkdir -p "$DIR" /var/log
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    fi
    case "$ID" in
        debian|ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            CMD="apt-get install -y --no-install-recommends"
            apt-get update -y >/dev/null 2>&1
            $CMD wget curl openssl socat git procps libc6 >/dev/null 2>&1
            ;;
        centos|rhel|almalinux|rocky|fedora|amzn)
            CMD="yum install -y"
            $CMD wget curl openssl socat git procps-ng tar gzip >/dev/null 2>&1
            ;;
        *)
            CMD="apk add --no-cache"
            $CMD wget curl openssl socat git tar gzip libc6-compat gcompat >/dev/null 2>&1
            ;;
    esac
}

pull_core() {
    echo "[*] 正在动态探测官方版本库..."
    init_env

    VER_LATEST=$(curl -sIL -m 5 -o /dev/null -w '%{url_effective}' https://github.com/SagerNet/sing-box/releases/latest 2>/dev/null | sed 's#.*/v##' | tr -d '\r\n')
    [ -z "$VER_LATEST" ] || echo "$VER_LATEST" | grep -q "releases" && VER_LATEST="1.14.2"

    RELS=$(curl -s -m 5 https://api.github.com/repos/SagerNet/sing-box/releases 2>/dev/null)
    
    VER_110=$(echo "$RELS" | grep -oE 'v1\.10\.[0-9]+' | head -n 1 | tr -d 'v')
    [ -z "$VER_110" ] && VER_110="1.10.1"

    VER_MID=$(echo "$RELS" | grep -oE 'v1\.1[34]\.[0-9]+' | head -n 1 | tr -d 'v')
    [ -z "$VER_MID" ] && VER_MID="1.14.2"

    echo "=========================================================="
    echo "       📦 请选择部署的 Sing-box 核心版本 (流式直写防 OOM)  "
    echo "=========================================================="
    echo "  1. v${VER_110} (64M ~ 128M 容器首选，极度轻量约 28MB)"
    echo "  2. v${VER_MID} (128M ~ 256M 容器首选，平衡稳定)"
    echo "  3. v${VER_LATEST} (Latest 官方最新正式版，适合 256MB+ 或 KVM)"
    echo "  4. 自定义输入版本号"
    if [ -x "$BIN" ]; then
        echo "  0. 保持当前已安装核心 ($("$BIN" version 2>/dev/null | head -n1))"
    fi
    echo "----------------------------------------------------------"
    printf "请选择核心版本 [默认 1]: "
    read c_choice
    case "$c_choice" in
        0)
            if [ -x "$BIN" ]; then
                echo "[*] 沿用现有已安装核心"
                return 0
            fi
            VER="$VER_110"
            ;;
        2) VER="$VER_MID" ;;
        3) VER="$VER_LATEST" ;;
        4)
            printf "请输入指定的官方版本号 (如 1.13.12): "
            read custom_ver
            VER="${custom_ver:-$VER_110}"
            ;;
        *) VER="$VER_110" ;;
    esac
    VER=$(echo "$VER" | sed 's/^v//' | tr -d ' \r\n')
    
    if [ -n "$(pidof sing-box)" ]; then
        killall sing-box 2>/dev/null
    fi
    
    ARCH=$(uname -m)
    [ "$ARCH" = "aarch64" ] && A="arm64" || A="amd64"
    
    URL="https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-${A}.tar.gz"

    echo "[*] 正在管道流式直写拉取 v${VER} 核心 (零硬盘落地防 OOM)..."
    DL_OK=0
    for MIRROR in "" "https://ghproxy.net/" "https://mirror.ghproxy.com/" "https://fastgh.js.org/"; do
        if curl -sL --connect-timeout 8 -m 60 "${MIRROR}${URL}" 2>/dev/null | tar -xz -C /usr/bin/ --strip-components=1 "sing-box-${VER}-linux-${A}/sing-box" 2>/dev/null; then
            DL_OK=1
            chmod +x "$BIN"
            echo "✅ 内核下载并解压成功！"
            break
        elif wget --no-check-certificate -qO- -T 10 "${MIRROR}${URL}" 2>/dev/null | tar -xz -C /usr/bin/ --strip-components=1 "sing-box-${VER}-linux-${A}/sing-box" 2>/dev/null; then
            DL_OK=1
            chmod +x "$BIN"
            echo "✅ 内核下载并解压成功！"
            break
        fi
    done
    
    if [ "$DL_OK" = "0" ] || ! "$BIN" version >/dev/null 2>&1; then
        echo "[-] 核心拉取或执行校验失败，请检查网络。"
        return 1
    fi
    
    CORE_V=$("$BIN" version | head -n1)
    echo "OK: $CORE_V"
    return 0
}

get_cert() {
    D=$1
    echo "[*] 准备向 Let's Encrypt 申请真实证书..."
    init_env
    
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        curl -s https://get.acme.sh | sh -s email="admin@$D" >/dev/null 2>&1
        if [ ! -f ~/.acme.sh/acme.sh ]; then
            git clone https://gitee.com/neilpang/acme.sh.git /tmp/acme.sh >/dev/null 2>&1
            cd /tmp/acme.sh && ./acme.sh --install -m "admin@$D" >/dev/null 2>&1
            cd - >/dev/null 2>&1
        fi
    fi
    command -v fuser >/dev/null 2>&1 && fuser -k 80/tcp >/dev/null 2>&1
    if [ -f ~/.acme.sh/acme.sh ]; then
        ~/.acme.sh/acme.sh --issue -d "$D" --standalone --server letsencrypt --insecure
        RET=$?
        if [ "$RET" = "0" ] || [ "$RET" = "2" ]; then
            mkdir -p "$DIR"
            ~/.acme.sh/acme.sh --install-cert -d "$D" --key-file "$DIR/key.pem" --fullchain-file "$DIR/cert.pem"
            [ -f "$DIR/cert.pem" ] && return 0
        fi
    fi
    echo "[-] 证书申请失败！"
    return 1
}

gen_self_cert() {
    echo "[*] 正在动态生成全新独享 ECC 自签证书 (内存占用 <5MB)..."
    mkdir -p "$DIR"
    if ! command -v openssl >/dev/null 2>&1; then
        init_env
    fi
    openssl ecparam -genkey -name prime256v1 -out "$DIR/key.pem" >/dev/null 2>&1
    openssl req -new -x509 -days 36500 -key "$DIR/key.pem" -out "$DIR/cert.pem" -subj "/CN=www.apple.com" >/dev/null 2>&1
    echo "✅ 自签证书生成完毕！"
}

gen_json() {
    mkdir -p "$DIR"
    add_basic=0
    add_tuic=0
    add_hy2=0
    add_naive=0
    case "$MODE" in
        full)
            add_basic=1; add_tuic=1; add_hy2=1; add_naive=1
            ;;
        combo)
            add_basic=1; add_tuic=1; add_hy2=1
            ;;
        lite)
            add_basic=1
            ;;
        hy2)
            add_hy2=1
            ;;
        tuic)
            add_tuic=1
            ;;
    esac

    cat << 'EOF' > "$CFG"
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
EOF

    FIRST=1
    add_comma() {
        if [ "$FIRST" = "0" ]; then
            printf ",\n" >> "$CFG"
        else
            FIRST=0
        fi
    }

    if [ "$add_basic" = "1" ]; then
        add_comma
        cat << EOF >> "$CFG"
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": $P_ANYTLS,
      "tcp_fast_open": true,
      "users": [{"password": "$UUID"}],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {"server": "$SNI", "server_port": 443},
          "private_key": "$PK",
          "short_id": ["$SID"]
        }
      }
    }
EOF
        add_comma
        cat << EOF >> "$CFG"
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $P_VLESS,
      "tcp_fast_open": true,
      "users": [{"uuid": "$UUID", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {"server": "$SNI", "server_port": 443},
          "private_key": "$PK",
          "short_id": ["$SID"]
        }
      }
    }
EOF
        add_comma
        cat << EOF >> "$CFG"
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": $P_SS,
      "tcp_fast_open": true,
      "method": "$SS_M",
      "password": "$SS_P"
    }
EOF
    fi

    if [ "$add_tuic" = "1" ]; then
        add_comma
        cat << EOF >> "$CFG"
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": $P_TUIC,
      "users": [{"uuid": "$UUID", "password": "$UUID"}],
      "congestion_control": "cubic",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$DIR/cert.pem",
        "key_path": "$DIR/key.pem"
      }
    }
EOF
    fi

    if [ "$add_naive" = "1" ]; then
        add_comma
        cat << EOF >> "$CFG"
    {
      "type": "naive",
      "tag": "naive-in",
      "listen": "::",
      "listen_port": $P_NAIVE,
      "network": "tcp",
      "users": [{"username": "$N_USER", "password": "$UUID"}],
      "tls": {
        "enabled": true,
        "certificate_path": "$DIR/cert.pem",
        "key_path": "$DIR/key.pem"
      }
    }
EOF
    fi

    if [ "$add_hy2" = "1" ]; then
        add_comma
        cat << EOF >> "$CFG"
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $P_HY2,
      "users": [{"password": "$UUID"}],
      "obfs": {
        "type": "salamander",
        "password": "$OBFS_PWD"
      },
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$DIR/cert.pem",
        "key_path": "$DIR/key.pem"
      }
    }
EOF
    fi

    cat << 'EOF' >> "$CFG"
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}, {"type": "block", "tag": "block"}],
  "route": {
    "rules": [
      {"port": [22], "outbound": "direct"},
      {"ip_cidr": ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "::1/128"], "outbound": "block"}
    ]
  }
}
EOF
}

setup_daemon() {
    # 1. Systemd 宿主或 KVM 架构守护
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        cat << 'SERVICE_EOF' > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3s
LimitNOFILE=65535
Environment="GOMEMLIMIT=30MiB"
StandardOutput=append:/var/log/sing-box.log
StandardError=append:/var/log/sing-box.log

[Install]
WantedBy=multi-user.target
SERVICE_EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable sing-box >/dev/null 2>&1
        INIT_MODE="systemd"

    # 2. Alpine Linux OpenRC 原生常驻守护
    elif command -v rc-service >/dev/null 2>&1 && [ -d /etc/init.d ]; then
        cat << 'OPENRC_EOF' > /etc/init.d/sing-box
#!/sbin/openrc-run
description="Sing-box Service"
command="/usr/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background=true
pidfile="/run/sing-box.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"

depend() {
    need net
    after firewall
}

start_pre() {
    export GOMEMLIMIT=30MiB
    ulimit -n 65535
}
OPENRC_EOF
        chmod +x /etc/init.d/sing-box
        rc-update add sing-box default >/dev/null 2>&1
        INIT_MODE="openrc"

    # 3. 极简环境独立守护
    else
        INIT_MODE="direct"
    fi

    # 配置 Keeper 内存熔断监控 Watchdog
    cat << 'KEEPER_EOF' > /root/keeper.sh
#!/bin/sh
ulimit -n 65535 2>/dev/null
export GOMEMLIMIT=30MiB
export GOGC=25

if ! pgrep -f "sing-box run" >/dev/null; then
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl restart sing-box >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>&1 && [ -x /etc/init.d/sing-box ]; then
        rc-service sing-box restart >/dev/null 2>&1
    else
        nohup /usr/bin/sing-box run -c /etc/sing-box/config.json </dev/null >>/var/log/sing-box.log 2>&1 &
    fi
    exit 0
fi

PID=$(pidof sing-box)
[ -z "$PID" ] && PID=$(pgrep -f "sing-box run" | head -n1)
if [ -n "$PID" ]; then
    PAGES=$(awk '{print $2}' "/proc/$PID/statm" 2>/dev/null)
    if [ -n "$PAGES" ] && [ "$PAGES" -gt 8000 ]; then
        if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
            systemctl restart sing-box >/dev/null 2>&1
        elif command -v rc-service >/dev/null 2>&1 && [ -x /etc/init.d/sing-box ]; then
            rc-service sing-box restart >/dev/null 2>&1
        else
            kill -9 $PID 2>/dev/null
            sleep 1
            nohup /usr/bin/sing-box run -c /etc/sing-box/config.json </dev/null >>/var/log/sing-box.log 2>&1 &
        fi
    fi
fi
KEEPER_EOF
    chmod +x /root/keeper.sh

    crontab -l 2>/dev/null | grep -v "keeper.sh" > /tmp/cron
    echo "* * * * * /root/keeper.sh >/dev/null 2>&1" >> /tmp/cron
    crontab /tmp/cron
    rm -f /tmp/cron

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1
        systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>&1; then
        rc-update add crond default >/dev/null 2>&1
        rc-service crond start >/dev/null 2>&1
    fi
}

restart_svc() {
    echo "[*] 正在校验配置并重启服务..."
    chmod -R 755 "$DIR"
    [ -f "$DIR/key.pem" ] && chmod 644 "$DIR"/*.pem
    chmod 644 "$CFG"

    # 启动前强制做语法与配置校验
    if ! "$BIN" check -c "$CFG" >/tmp/sb_check.log 2>&1; then
        echo "❌ 配置文件校验未通过！内核返回具体错误如下："
        cat /tmp/sb_check.log
        printf "按回车键返回菜单..."
        read d
        return 1
    fi

    setup_daemon

    if [ "$INIT_MODE" = "systemd" ]; then
        systemctl restart sing-box >/dev/null 2>&1
    elif [ "$INIT_MODE" = "openrc" ]; then
        rc-service sing-box restart >/dev/null 2>&1
    else
        killall sing-box 2>/dev/null
        sleep 1
        export GOMEMLIMIT=30MiB
        nohup "$BIN" run -c "$CFG" </dev/null >>"$LOG" 2>&1 &
    fi

    sleep 2
    
    PID=$(pidof sing-box)
    [ -z "$PID" ] && PID=$(pgrep -f "sing-box run" | head -n1)

    if [ -n "$PID" ]; then
        echo "✅ 服务已成功运行！PID: $PID (已接入系统级常驻服务: $INIT_MODE)"
    else
        echo "❌ 启动失败！服务未能成功驻留后台。内核日志如下："
        echo "----------------------------------------------------------"
        [ -f "$LOG" ] && tail -n 15 "$LOG"
        echo "----------------------------------------------------------"
    fi
    printf "按回车键返回菜单..."
    read d
}

do_install() {
    MODE=$1
    REAL="www.apple.com"
    init_env

    # 1. 核心版本选择与拉取
    if [ "$MODE" = "full" ] || [ "$MODE" = "combo" ] || [ ! -x "$BIN" ]; then
        clear
        if [ "$MODE" = "full" ]; then
            echo "=========================================================="
            echo "   📦 正在部署【正规全量包】(需真实域名+80端口)"
            echo "=========================================================="
        elif [ "$MODE" = "combo" ]; then
            echo "=========================================================="
            echo "   🦄 正在部署【免域全家桶】(免域名 / 自签证书)"
            echo "=========================================================="
        fi
        pull_core || { echo "[-] 核心拉取未完成，终止安装"; printf "按回车返回..."; read d; return 1; }
    fi

    # 2. 关键检查：先读取并探测本地配置
    USE_EXISTING=0
    if [ -f "$ENV" ]; then
        . "$ENV" 2>/dev/null
        if [ -n "$UUID" ] && [ -n "$P_SS" ] && [ -n "$PK" ] && [ -n "$PUB" ]; then
            echo ""
            echo "=========================================================="
            echo "  🔍 检测到本地已存在历史配置凭据："
            echo "  - 统一凭据(UUID) : $UUID"
            echo "  - 起始端口       : $P_SS"
            echo "  - 伪装域名(SNI)  : $SNI"
            echo "  - Reality 公钥   : $PUB"
            [ -n "$OBFS_PWD" ] && echo "  - HY2 混淆密码   : $OBFS_PWD"
            echo "=========================================================="
            printf "[?] 检测到历史配置，是否继承已有参数直接安装？(y/n) [默认 y]: "
            read inherit_choice
            inherit_choice=${inherit_choice:-y}
            if [ "$inherit_choice" = "y" ] || [ "$inherit_choice" = "Y" ]; then
                echo "✅ 已确认继承本地配置参数，客户端参数保持不变！"
                USE_EXISTING=1
            else
                echo "[*] 用户选择放弃旧配置，正在生成全新随机凭据..."
            fi
        else
            echo ""
            echo "⚠️ 侦测到本地历史配置已损坏或参数不全，将自动生成全新参数..."
        fi
    else
        echo ""
        echo "ℹ️ 未侦测到本地历史配置，将自动生成全新参数..."
    fi

    # 3. 证书处理
    if [ "$MODE" = "full" ]; then
        if [ "$USE_EXISTING" = "1" ] && [ "$REAL" != "www.apple.com" ] && [ -f "$DIR/cert.pem" ]; then
            echo "[*] 沿用已有证书域名: $REAL"
        else
            printf "[?] 是否立刻申请真实证书(需绑定域名)? (y/n): "
            read y
            if [ "$y" = "y" ] || [ "$y" = "Y" ]; then
                printf "请输入你的域名: "
                read d
                if get_cert "$d"; then
                    REAL="$d"
                else
                    echo "[-] 证书失败，降级为免域全家桶"
                    MODE="combo"
                    printf "按回车继续..."
                    read d
                fi
            else
                echo "[-] 自动降级为免域全家桶"
                MODE="combo"
                printf "按回车继续..."
                read d
            fi
        fi
    fi
    
    case "$MODE" in
        hy2|tuic|combo)
            if [ ! -f "$DIR/cert.pem" ] || [ ! -f "$DIR/key.pem" ]; then
                gen_self_cert
            fi
            ;;
    esac

    # 4. 生成新参数或继承已有参数
    if [ "$USE_EXISTING" = "0" ]; then
        printf "请输入起始端口 [默认 37841]: "
        read PORT
        PORT=${PORT:-37841}
        P_SS=$PORT
        P_VLESS=$((PORT+1))
        P_ANYTLS=$((PORT+2))
        P_TUIC=$((PORT+3))
        P_NAIVE=$((PORT+4))
        P_HY2=$((PORT+5))
        
        UUID=$(sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null)
        KEYS=$(sing-box generate reality-keypair 2>/dev/null)
        PK=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
        PUB=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')
        SID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c 1-16)
        [ -z "$SID" ] && SID=$(sing-box generate rand 8 --hex 2>/dev/null)
        
        SS_M="chacha20-ietf-poly1305"
        SS_P="$UUID"
        
        OBFS_PWD=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c 1-16)
        [ -z "$OBFS_PWD" ] && OBFS_PWD=$(sing-box generate rand 8 --hex 2>/dev/null)
        
        IP=$(wget -qO- -T 5 https://api.ipify.org 2>/dev/null || curl -s -m 5 https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
        SNI="www.apple.com"
        N_USER="nv$SID"
    else
        # 继承模式下进行必要容灾补齐
        [ -z "$OBFS_PWD" ] && OBFS_PWD=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c 1-16)
        [ -z "$OBFS_PWD" ] && OBFS_PWD=$(sing-box generate rand 8 --hex 2>/dev/null)
        SS_P="$UUID"
        
        # 刷新公网 IP 避免漂移
        CURR_IP=$(wget -qO- -T 5 https://api.ipify.org 2>/dev/null || curl -s -m 5 https://api.ipify.org 2>/dev/null)
        [ -n "$CURR_IP" ] && IP="$CURR_IP"
    fi

    cat << ENV_EOF > "$ENV"
IP="$IP"
SNI="$SNI"
PK="$PK"
PUB="$PUB"
SID="$SID"
UUID="$UUID"
SS_M="$SS_M"
SS_P="$SS_P"
OBFS_PWD="$OBFS_PWD"
REAL="$REAL"
MODE="$MODE"
P_SS=$P_SS
P_VLESS=$P_VLESS
P_ANYTLS=$P_ANYTLS
P_TUIC=$P_TUIC
P_NAIVE=$P_NAIVE
P_HY2=$P_HY2
N_USER="$N_USER"
ENV_EOF

    gen_json
    restart_svc
}

load_env() {
    if [ ! -f "$ENV" ]; then
        echo "[-] 未安装配置！"
        printf "按回车返回..."
        read d
        return 1
    fi
    . "$ENV"
    SSB=$(printf "%s:%s" "$SS_M" "$SS_P" | base64 | tr -d '\n\r')
    SEC_HY=""
    SEC_TC=""
    if [ "$MODE" != "full" ]; then
        SEC_HY="&insecure=1"
        SEC_TC="&allow_insecure=1"
    fi

    if [ "$REAL" = "www.apple.com" ] || [ -z "$REAL" ]; then
        case "$IP" in
            *:*) URL_HOST="[$IP]" ;;
            *) URL_HOST="$IP" ;;
        esac
        C_SNI="www.apple.com"
    else
        URL_HOST="$REAL"
        C_SNI="$REAL"
    fi

    L_SS="ss://${SSB}@${URL_HOST}:${P_SS}#SingBox-SS"
    L_VL="vless://${UUID}@${URL_HOST}:${P_VLESS}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp&headerType=none#SingBox-VLESS"
    L_AT="trojan://${UUID}@${URL_HOST}:${P_ANYTLS}?security=reality&sni=${SNI}&pbk=${PUB}&sid=${SID}&type=tcp&headerType=none#SingBox-Trojan"
    L_TC="tuic://${UUID}:${UUID}@${URL_HOST}:${P_TUIC}?sni=${C_SNI}&alpn=h3${SEC_TC}#SingBox-TUIC"
    L_NV="naive+https://${N_USER}:${UUID}@${URL_HOST}:${P_NAIVE}#SingBox-Naive"
    L_HY="hysteria2://${UUID}@${URL_HOST}:${P_HY2}/?sni=${C_SNI}${SEC_HY}&obfs=salamander&obfs-password=${OBFS_PWD}#SingBox-HY2"
    return 0
}

view_params() {
    load_env || return
    clear
    echo "=========================================================="
    echo "                 📝 当前运行参数明细清单                 "
    echo "=========================================================="
    case "$MODE" in
        full|lite|combo)
            echo "【全局 REALITY 伪装参数】"
            echo "连接地址 : $URL_HOST | 伪装域名: $SNI | Short ID: $SID"
            echo "公钥(PBK): $PUB"
            ;;
        *)
            echo "连接地址 : $URL_HOST | 伪装/SNI 域名: $C_SNI (自签证书)"
            ;;
    esac
    echo "----------------------------------------------------------"
    echo "【密码凭证】 统一凭据(UUID/SS密码) : $UUID"
    echo "             HY2 混淆密码(obfs)     : $OBFS_PWD"
    echo "----------------------------------------------------------"
    case "$MODE" in
        full)
            echo "【端口分布】 SS:$P_SS | VLESS:$P_VLESS | Trojan:$P_ANYTLS | TUIC:$P_TUIC | Naive:$P_NAIVE | HY2:$P_HY2"
            ;;
        combo)
            echo "【端口分布】 SS:$P_SS | VLESS:$P_VLESS | Trojan:$P_ANYTLS | TUIC:$P_TUIC | HY2:$P_HY2"
            ;;
        lite)
            echo "【端口分布】 SS:$P_SS | VLESS:$P_VLESS | Trojan:$P_ANYTLS"
            ;;
        hy2)
            echo "【端口分布】 Hysteria2: $P_HY2"
            ;;
        tuic)
            echo "【端口分布】 TUIC: $P_TUIC"
            ;;
    esac
    echo "=========================================================="
    printf "按回车键返回菜单..."
    read dummy
}

do_edit() {
    if [ ! -f "$ENV" ]; then
        echo "[-] 尚未配置！"
        printf "按回车返回..."
        read d
        return
    fi
    . "$ENV"
    clear
    echo "=== ⚙️ 直接回车则该项保持不变 ==="
    printf "👉 新伪装域名 [$SNI]: "
    read i_sni
    [ -n "$i_sni" ] && SNI="$i_sni"
    printf "👉 新统一UUID (同时生效于SS) [$UUID]: "
    read i_id
    if [ -n "$i_id" ]; then
        UUID="$i_id"
        SS_P="$i_id"
    fi
    printf "👉 修改 HY2 混淆密码 [$OBFS_PWD]: "
    read i_obfs
    [ -n "$i_obfs" ] && OBFS_PWD="$i_obfs"
    printf "👉 修改 Trojan 端口 [$P_ANYTLS]: "
    read i_at
    [ -n "$i_at" ] && P_ANYTLS=$i_at
    printf "👉 修改 VLESS 端口 [$P_VLESS]: "
    read i_vl
    [ -n "$i_vl" ] && P_VLESS=$i_vl
    printf "👉 修改 SS 端口 [$P_SS]: "
    read i_ss
    [ -n "$i_ss" ] && P_SS=$i_ss
    case "$MODE" in
        full|combo|hy2)
            printf "👉 修改 HY2 端口 [$P_HY2]: "
            read i_hy
            [ -n "$i_hy" ] && P_HY2=$i_hy
            ;;
    esac
    case "$MODE" in
        full|combo|tuic)
            printf "👉 修改 TUIC 端口 [$P_TUIC]: "
            read i_tc
            [ -n "$i_tc" ] && P_TUIC=$i_tc
            ;;
    esac

    cat << ENV_EOF > "$ENV"
IP="$IP"
SNI="$SNI"
PK="$PK"
PUB="$PUB"
SID="$SID"
UUID="$UUID"
SS_M="$SS_M"
SS_P="$SS_P"
OBFS_PWD="$OBFS_PWD"
REAL="$REAL"
MODE="$MODE"
P_SS=$P_SS
P_VLESS=$P_VLESS
P_ANYTLS=$P_ANYTLS
P_TUIC=$P_TUIC
P_NAIVE=$P_NAIVE
P_HY2=$P_HY2
N_USER="$N_USER"
ENV_EOF

    gen_json
    restart_svc
}

while true; do
    clear
    echo "=========================================================="
    echo "   🚀 Sing-box 面板 v4.5 Pro (全平台兼容 / 极限生存版)    "
    echo "=========================================================="
    echo "  1. 📦 部署【正规全量包】(6大顶级协议，需真实域名+80端口)"
    echo "  2. 🦄 部署【免域全家桶】(包含 VLESS+SS+Trojan+HY2+TUIC)"
    echo "  3. 🍃 部署【精简包】(3大Reality大件，完全免域名)"
    echo "  4. ⚡ 部署【HY2 独立包】(自签证书+Salamander混淆)"
    echo "  5. 🚄 部署【TUIC 独立包】(自签证书，免域名/免80端口)"
    echo "  6. 📝 查看运行参数明细"
    echo "  7. 🔗 导出快捷导入链接 (全部节点明文)"
    echo "  8. ⚙️ 修改 端口/UUID/混淆/域名 (支持热修补)"
    echo "  9. 🔄 手动重启并检查核心服务"
    echo "  0. 🚪 退出面板"
    echo "=========================================================="
    printf "请选择 [0-9]: "
    read choice
    case "$choice" in
        1) do_install "full" ;;
        2) do_install "combo" ;;
        3) do_install "lite" ;;
        4) do_install "hy2" ;;
        5) do_install "tuic" ;;
        6) view_params ;;
        7)
            load_env && { 
                clear
                case "$MODE" in
                    full|lite|combo)
                        printf "Trojan:\n%s\n\nVLESS:\n%s\n\nSS:\n%s\n\n" "$L_AT" "$L_VL" "$L_SS"
                        ;;
                esac
                case "$MODE" in
                    full)
                        printf "Naive:\n%s\n\n" "$L_NV"
                        ;;
                esac
                case "$MODE" in
                    full|combo|tuic)
                        printf "TUIC:\n%s\n\n" "$L_TC"
                        ;;
                esac
                case "$MODE" in
                    full|combo|hy2)
                        printf "HY2:\n%s\n\n" "$L_HY"
                        ;;
                esac
                printf "按回车返回..."
                read d
            }
            ;;
        8) do_edit ;;
        9) restart_svc ;;
        0) clear; exit 0 ;;
        *) echo "[-] 输入无效"; sleep 1 ;;
    esac
done
