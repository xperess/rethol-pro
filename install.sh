#!/bin/bash
# =================================================================
#  KHALIFEH TUNNEL v2 - MASTER INSTALLER WITH INTERNAL PROXY FIX
# =================================================================

if [[ $EUID -ne 0 ]]; then
   echo -e "\033[0;31m[-] Please run this script as root (sudo).\033[0m" 
   exit 1
fi

BASE_DIR="/opt/khalifeh"
BIN_DIR="$BASE_DIR/bin"
CFG_DIR="$BASE_DIR/configs"
MOD_DIR="$BASE_DIR/modules"
WEB_DIR="$BASE_DIR/web"

# پاک‌سازی کامل برای جلوگیری از تداخل پورت‌های مشغول
systemctl stop khalifeh-web khalifeh-failover khalifeh-rathole-server khalifeh-rathole-client khalifeh-local-proxy >/dev/null 2>&1
rm -rf "$BASE_DIR"
rm -f /usr/local/bin/khalifeh

mkdir -p "$BIN_DIR" "$CFG_DIR" "$MOD_DIR" "$WEB_DIR/templates"

echo "[*] Upgrading system core and installing network packages..."
apt update -y && apt install -y curl wget jq unzip openssl python3-flask python3-pip net-tools sshpass -y

# =================================================================
# ۱. ماژول رتهول ارتقا یافته (rathole.sh)
# =================================================================
cat << 'EOF' > "$MOD_DIR/rathole.sh"
#!/bin/bash
rathole_menu() {
    while true; do
        banner
        echo -e "${CYAN}=== Rathole Tunnel Manager ===${NC}"
        echo "1) Configure IRAN Server (Server Mode)"
        echo "2) Configure KHAREJ Server (Client Mode)"
        echo "3) Live Connection Logs"
        echo "0) Back"
        read -p "Selection: " c
        case $c in
            1) rathole_iran ;;
            2) rathole_kharej ;;
            3) journalctl -u khalifeh-rathole-server -u khalifeh-rathole-client -n 30 --no-pager; read -p "Press Enter..." ;;
            0) break ;;
        esac
    done
}
rathole_iran() {
    read -p "Enter Tunnel Bind Port [Default: 2333]: " port
    port=${port:-2333}
    read -p "Enter X-UI Ports to tunnel (separated by comma, e.g. 443,8080): " ports
    token=$(openssl rand -hex 16)
    cat <<EOF > /opt/khalifeh/configs/rathole-server.toml
[server]
bind_addr = "0.0.0.0:$port"
default_token = "$token"
[server.transport]
type = "tcp"
EOF
    IFS=',' read -ra ADDR <<< "$ports"
    for p in "${ADDR[@]}"; do
        p=$(echo $p | xargs)
        cat <<EOF >> /opt/khalifeh/configs/rathole-server.toml
[server.services.port_$p]
bind_addr = "0.0.0.0:$p"
EOF
    done
    cat <<EOF > /etc/systemd/system/khalifeh-rathole-server.service
[Unit]
Description=Khalifeh Rathole Server
After=network.target
[Service]
ExecStart=/opt/khalifeh/bin/rathole /opt/khalifeh/configs/rathole-server.toml
Restart=always
EOF
    systemctl daemon-reload && systemctl enable --now khalifeh-rathole-server
    echo -e "${GREEN}[+] Iran Server active on tunnel port $port.${NC}"
    echo -e "${YELLOW}[!] Secure Token for Kharej Node: $token${NC}"
    read -p "Press Enter..."
}
rathole_kharej() {
    read -p "Enter Iran Server IP: " ip
    read -p "Enter Iran Bind Port [Default: 2333]: " port
    port=${port:-2333}
    read -p "Enter Token: " token
    read -p "Enter local X-UI ports to forward (comma separated, e.g. 443,8080): " ports
    cat <<EOF > /opt/khalifeh/configs/rathole-client.toml
[client]
remote_addr = "$ip:$port"
default_token = "$token"
[client.transport]
type = "tcp"
EOF
    IFS=',' read -ra ADDR <<< "$ports"
    for p in "${ADDR[@]}"; do
        p=$(echo $p | xargs)
        cat <<EOF >> /opt/khalifeh/configs/rathole-client.toml
[client.services.port_$p]
local_addr = "127.0.0.1:$p"
EOF
    done
    cat <<EOF > /etc/systemd/system/khalifeh-rathole-client.service
[Unit]
Description=Khalifeh Rathole Client
After=network.target
[Service]
ExecStart=/opt/khalifeh/bin/rathole /opt/khalifeh/configs/rathole-client.toml
Restart=always
EOF
    systemctl daemon-reload && systemctl enable --now khalifeh-rathole-client
    echo -e "${GREEN}[+] Kharej Server successfully linked to Iran!${NC}"
    read -p "Press Enter..."
}
EOF

# =================================================================
# ۲. ماژول انقلابی فیکس پینگ و ساخت پروکسی داخلی (ping_fix.sh)
# =================================================================
cat << 'EOF' > "$MOD_DIR/ping_fix.sh"
#!/bin/bash
proxy_menu() {
    while true; do
        banner
        echo -e "${YELLOW}=== FIX PING: Self-Hosted Kharej Proxy Engine ===${NC}"
        echo "1) Build & Enable Proxy Link (Run this on IRAN Server)"
        echo "2) Disable Proxy Routing"
        echo "3) Test Connection Health & Latency"
        echo "0) Back"
        read -p "Selection: " cp
        case $cp in
            1) deploy_internal_proxy ;;
            2) disable_internal_proxy ;;
            3) clear; echo "[*] Testing latency to international gateway..."; curl -I -s --connect-timeout 4 https://www.google.com | head -n 1; read -p "Press Enter..." ;;
            0) break ;;
        esac
    done
}
deploy_internal_proxy() {
    echo -e "${CYAN}[*] Let's bridge Iran to your Kharej Server safely...${NC}"
    read -p "Enter your KHAREJ Server IP: " kharej_ip
    read -p "Enter KHAREJ SSH Port [Default: 22]: " kharej_ssh_port
    kharej_ssh_port=${kharej_ssh_port:-22}
    read -p "Enter KHAREJ Root Password: " kharej_pass

    echo -e "${YELLOW}[*] Generating highly secure SSH Tunnel Proxy on port 1080...${NC}"
    
    # ساخت یک سرویس سیستمی پایدار که از خود سرور خارج یک پراکسی سوکس۵ امن می‌سازد
    cat <<EOF > /etc/systemd/system/khalifeh-local-proxy.service
[Unit]
Description=Khalifeh Secure Fix-Ping Proxy Forwarder
After=network.target

[Service]
ExecStart=/usr/bin/sshpass -p "$kharej_pass" ssh -o StrictHostKeyChecking=no -N -D 127.0.0.1:1080 root@$kharej_ip -p $kharej_ssh_port
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now khalifeh-local-proxy
    sleep 3

    # تزریق به متغیرهای سیستمی اوبونتو برای هدایت رتهول از داخل این تونل پروکسی
    cat <<EOF > /etc/profile.d/khalifeh_proxy.sh
export http_proxy="socks5://127.0.0.1:1080"
export https_proxy="socks5://127.0.0.1:1080"
export all_proxy="socks5://127.0.0.1:1080"
export HTTP_PROXY="socks5://127.0.0.1:1080"
export HTTPS_PROXY="socks5://127.0.0.1:1080"
EOF

    source /etc/profile.d/khalifeh_proxy.sh
    echo -e "${GREEN}[+] SUCCESS: Server Iran is now fully proxied via Kharej Server!${NC}"
    echo -e "${GREEN}[+] Rathole connections will now bypass Iran national filtering data blocks.${NC}"
    read -p "Press Enter to continue..."
}
disable_internal_proxy() {
    systemctl stop khalifeh-local-proxy && systemctl disable khalifeh-local-proxy
    rm -f /etc/profile.d/khalifeh_proxy.sh
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY
    echo -e "${RED}[- ] Internal Proxy Tunnel completely terminated.${NC}"
    read -p "Press Enter..."
}
EOF

# =================================================================
# ۳. ساختار بدنه و منوی اصلی (core.sh)
# =================================================================
cat << 'EOF' > "$BASE_DIR/core.sh"
#!/bin/bash
BASE="/opt/khalifeh"
MOD="$BASE/modules"

[[ -f "$MOD/rathole.sh" ]] && source "$MOD/rathole.sh"
[[ -f "$MOD/ping_fix.sh" ]] && source "$MOD/ping_fix.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

banner() {
    clear
    echo -e "${MAGENTA}==================================================${NC}"
    echo -e "${CYAN}     KHALIFEH PRO TUNNEL FRAMEWORK (FIX PING)     ${NC}"
    echo -e "${MAGENTA}==================================================${NC}"
}
main_menu() {
    while true; do
        banner
        echo -e "1) ${CYAN}Rathole Tunnel Core (Manage Ports)${NC}"
        echo -e "2) ${YELLOW}Fix Connection Ping (Create Free Internal Proxy)${NC}"
        echo "0) Exit CLI Session"
        echo "--------------------------------------------------"
        read -p "Select Menu Entry: " choice
        case $choice in
            1) rathole_menu ;;
            2) proxy_menu ;;
            0) exit 0 ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}
EOF

# =================================================================
# ۴. دانلود و راه‌اندازی ملزومات سیستم
# =================================================================
ARCH=$(uname -m)
echo "[*] Downloading stable core binaries..."
if [[ "$ARCH" == "x86_64" ]]; then
    R_URL="https://github.com/rapiz1/rathole/releases/download/v0.5.0/rathole-x86_64-unknown-linux-gnu.zip"
else
    R_URL="https://github.com/rapiz1/rathole/releases/download/v0.5.0/rathole-aarch64-unknown-linux-gnu.zip"
fi
curl -Ls "$R_URL" -o /tmp/rathole.zip && unzip -o /tmp/rathole.zip -d /tmp/ && cp /tmp/rathole "$BIN_DIR/"

chmod +x $BIN_DIR/*
chmod +x "$BASE_DIR"/core.sh
chmod 755 "$MOD_DIR"/*.sh

# ساخت میانبر اجرای خط فرمان
cat > /usr/local/bin/khalifeh << 'LAUNCHER'
#!/bin/bash
source /opt/khalifeh/core.sh
main_menu
LAUNCHER
chmod +x /usr/local/bin/khalifeh

clear
echo -e "\033[0;32m[+] FULLY INSTALLED SUCCESSFULLY! \033[0m"
echo -e "[*] Type \033[1;36mkhalifeh\033[0m anywhere to configure your multi-ports and fix ping layers."
