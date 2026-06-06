#!/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   sleep 1
   exit 1
fi

config_dir="/root/rathole-core"
service_dir="/etc/systemd/system"
mkdir -p "$config_dir"

# Colors for UI
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
NC='\033[0m'

press_key(){
 read -p "Press any key to continue..."
}

colorize() {
    local color="$1"
    local text="$2"
    local style="${3:-normal}"
    local color_code style_code
    case $color in
        black) color_code="\033[30m" ;;
        red) color_code="\033[31m" ;;
        green) color_code="\033[32m" ;;
        yellow) color_code="\033[33m" ;;
        blue) color_code="\033[34m" ;;
        magenta) color_code="\033[35m" ;;
        cyan) color_code="\033[36m" ;;
        white) color_code="\033[37m" ;;
        *) color_code="\033[0m" ;;
    esac
    case $style in
        bold) style_code="\033[1m" ;;
        underline) style_code="\033[4m" ;;
        *) style_code="\033[0m" ;;
    esac
    echo -e "${style_code}${color_code}${text}\033[0m"
}

# Install packages smoothly without Ubuntu 24 prompt freezes
install_dependencies() {
    apt-get update -y && apt-get install -y unzip cron jq net-tools ufw sshpass curl lsof < /dev/null
}
install_dependencies

# Robust anti-clash system to free up frozen ports
clear_port_clash() {
    local target_port=$1
    if [ ! -z "$target_port" ]; then
        # Kill using lsof
        sudo kill -9 $(sudo lsof -t -i:$target_port) >/dev/null 2>&1
        # Double check with netstat
        local pid=$(netstat -lntp 2>/dev/null | grep ":$target_port " | awk '{print $7}' | cut -d'/' -f1)
        if [ ! -z "$pid" ] && [[ "$pid" =~ ^[0-9]+$ ]]; then
            kill -9 $pid >/dev/null 2>&1
        fi
    fi
}

download_and_extract_rathole() {
    if [[ -f "${config_dir}/rathole" ]]; then
        return 0
    fi
    ENTRY="185.199.108.133 raw.githubusercontent.com"
    if ! grep -q "$ENTRY" /etc/hosts; then
        echo "$ENTRY" >> /etc/hosts
    fi

    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        DOWNLOAD_URL='https://github.com/Musixal/rathole-tunnel/raw/main/core/rathole.zip'
    else
        DOWNLOAD_URL="https://github.com/rapiz1/rathole/releases/download/v0.5.0/rathole-aarch64-unknown-linux-gnu.zip"
    fi

    DOWNLOAD_DIR=$(mktemp -d)
    curl -sSL -o "$DOWNLOAD_DIR/rathole.zip" "$DOWNLOAD_URL"
    unzip -q "$DOWNLOAD_DIR/rathole.zip" -d "$config_dir"
    chmod u+x ${config_dir}/rathole
    rm -rf "$DOWNLOAD_DIR"
}
download_and_extract_rathole

SERVER_COUNTRY=$(curl --max-time 3 -sS "http://ipwhois.app/json/$SERVER_IP" | jq -r '.country' 2>/dev/null)
SERVER_ISP=$(curl --max-time 3 -sS "http://ipwhois.app/json/$SERVER_IP" | jq -r '.isp' 2>/dev/null)

display_logo() {   
    echo -e "${CYAN}"
    cat << "EOF"
               __  .__            .__          
____________ _/  |_|  |__   ____ |  |   ____  
\_  __ \__  \\   __|  |  \ /  _ \|  | _/ __ \ 
 |  | \// __ \|  | |  |  \(  <_> )  |_\  ___/ 
 |__|  (____  /__| |___|  /\____/|____/\___  >
            \/          \/                 \/ 
EOF
    echo -e "${NC}${GREEN}Version: ${YELLOW}v3.0 PRO (Fixed Name Sync & Anti-Clash)${NC}"
}

display_server_info() {
    echo -e "\e[93m═════════════════════════════════════════════\e[0m"  
    echo -e "${CYAN}Location:${NC} $SERVER_COUNTRY "
    echo -e "${CYAN}Datacenter:${NC} $SERVER_ISP"
}

display_rathole_core_status() {
    if [[ -f "${config_dir}/rathole" ]]; then
        echo -e "${CYAN}Rathole Core:${NC} ${GREEN}Installed${NC}"
    else
        echo -e "${CYAN}Rathole Core:${NC} ${RED}Not installed${NC}"
    fi
    echo -e "\e[93m═════════════════════════════════════════════\e[0m"  
}

check_port() {
    local PORT=$1
    local TRANSPORT=$2
    if [[ "$TRANSPORT" == "tcp" ]]; then
        ss -tlnp "sport = :$PORT" | grep "$PORT" > /dev/null && return 0 || return 1
    else
        ss -ulnp "sport = :$PORT" | grep "$PORT" > /dev/null && return 0 || return 1
    fi
}

configure_tunnel() {
    if [[ ! -d "$config_dir" ]]; then
        echo -e "\n${RED}Rathole-core directory not found.${NC}\n"
        return 1
    fi
    clear
    colorize green "1) Configure for IRAN server (Server Mode)" bold
    colorize magenta "2) Configure for KHAREJ server (Client Mode)" bold
    echo
    read -p "Enter your choice: " configure_choice
    case "$configure_choice" in
        1) iran_server_configuration ;;
        2) kharej_server_configuration ;;
        *) echo -e "${RED}Invalid option!${NC}" && sleep 1 ;;
    esac
}

iran_server_configuration() {  
    clear
    colorize cyan "Configuring IRAN server (With Fix-Ping Corridor Proxy)" bold
    
    echo -e "${YELLOW}[*] Enter KHAREJ server credentials to create Proxy Corridor:${NC}"
    read -p "Kharej Server IP: " kharej_ip
    read -p "Kharej SSH Port [Default: 22]: " kharej_ssh_port
    kharej_ssh_port=${kharej_ssh_port:-22}
    read -p "Kharej Root Password: " kharej_pass

    # Save credentials securely
    mkdir -p "$config_dir/secure"
    cat <<EOT > "$config_dir/secure/ssh_creds.conf"
KHAREJ_IP="$kharej_ip"
KHAREJ_PORT="$kharej_ssh_port"
KHAREJ_PASS="$kharej_pass"
EOT
    chmod 600 "$config_dir/secure/ssh_creds.conf"

    # Build the SOCKS5 proxy corridor runner
    cat << 'RUNNER' > "$config_dir/proxy_runner.sh"
#!/bin/bash
source /root/rathole-core/secure/ssh_creds.conf
exec /usr/bin/sshpass -p "$KHAREJ_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -N -D 127.0.0.1:1080 root@$KHAREJ_IP -p $KHAREJ_PORT
RUNNER
    chmod +x "$config_dir/proxy_runner.sh"

    # Deploy Proxy service
    cat <<EOT > ${service_dir}/khalifeh-proxy.service
[Unit]
Description=Khalifeh Fix-Ping Proxy Corridor
After=network.target

[Service]
ExecStart=/bin/bash $config_dir/proxy_runner.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
    systemctl daemon-reload
    systemctl enable --now khalifeh-proxy.service

    # Create proxy environment rules for Rathole core routing
    cat <<EOT > "$config_dir/proxy_env.conf"
http_proxy=socks5://127.0.0.1:1080
https_proxy=socks5://127.0.0.1:1080
all_proxy=socks5://127.0.0.1:1080
HTTP_PROXY=socks5://127.0.0.1:1080
HTTPS_PROXY=socks5://127.0.0.1:1080
EOT

    echo
    local_ip='0.0.0.0'
    read -p "[-] Listen for IPv6 address? (y/n): " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then local_ip='[::]'; fi

    while true; do
        echo -ne "[*] Tunnel port [Default 2333]: "
        read -r tunnel_port
        tunnel_port=${tunnel_port:-2333}
        clear_port_clash "$tunnel_port"
        break
    done
    
    local nodelay="true"
    local HEARTBEAT="30"
    local transport="tcp"
    token="musixal"

    echo -ne "[*] Enter your X-UI ports separated by commas (e.g. 8443,46701): "
    read -r input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports

    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 22 ]; then
            clear_port_clash "$port"
            ufw allow $port/tcp >/dev/null 2>&1
            config_ports+=("$port")
        fi
    done

    ufw allow $tunnel_port/tcp >/dev/null 2>&1

    # Exact sync naming structure [server.services.port_XXX]
    cat << EOF > "${config_dir}/iran${tunnel_port}.toml"
[server]
bind_addr = "${local_ip}:${tunnel_port}"
default_token = "$token"
heartbeat_interval = $HEARTBEAT

[server.transport]
type = "tcp"
[server.transport.tcp]
nodelay = $nodelay
EOF

    for port in "${config_ports[@]}"; do
        cat << EOF >> "${config_dir}/iran${tunnel_port}.toml"
[server.services.port_${port}]
type = "$transport"
bind_addr = "${local_ip}:${port}"
EOF
    done

    cat << EOF > "${service_dir}/rathole-iran${tunnel_port}.service"
[Unit]
Description=Rathole Iran Port $tunnel_port
After=network.target khalifeh-proxy.service

[Service]
EnvironmentFile=-/root/rathole-core/proxy_env.conf
ExecStart=${config_dir}/rathole ${config_dir}/iran${tunnel_port}.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "rathole-iran${tunnel_port}.service"
    ufw reload >/dev/null 2>&1
    colorize green "Iran server configured successfully. Naming schema verified."
}

kharej_server_configuration() {
    clear
    colorize cyan "Configuring KHAREJ server" bold 
    echo
    read -p "[*] IRAN server IP address: " SERVER_ADDR
    read -p "[*] Tunnel port [Default 2333]: " tunnel_port
    tunnel_port=${tunnel_port:-2333}
    clear_port_clash "$tunnel_port"
    
    local nodelay="true"
    local HEARTBEAT="40"
    local transport="tcp"
    token="musixal"

    echo -ne "[*] Enter your X-UI ports separated by commas (e.g. 8443,46701): "
    read -r input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    declare -a config_ports

    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            clear_port_clash "$port"
            config_ports+=("$port")
        fi
    done

    local_ip='127.0.0.1'
    ufw allow $tunnel_port/tcp >/dev/null 2>&1

    # Exact sync naming structure [client.services.port_XXX]
    cat << EOF > "${config_dir}/kharej${tunnel_port}.toml"
[client]
remote_addr = "${SERVER_ADDR}:${tunnel_port}"
default_token = "$token"
heartbeat_timeout = $HEARTBEAT
retry_interval = 1

[client.transport]
type = "tcp"
[client.transport.tcp]
nodelay = $nodelay
EOF

    for port in "${config_ports[@]}"; do
        cat << EOF >> "${config_dir}/kharej${tunnel_port}.toml"
[client.services.port_${port}]
type = "$transport"
local_addr = "${local_ip}:${port}"
EOF
    done

    cat << EOF > "${service_dir}/rathole-kharej${tunnel_port}.service"
[Unit]
Description=Rathole Kharej Port $tunnel_port 
After=network.target

[Service]
Type=simple
ExecStart=${config_dir}/rathole ${config_dir}/kharej${tunnel_port}.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "rathole-kharej${tunnel_port}.service"
    ufw reload >/dev/null 2>&1
    colorize green "Kharej client configuration finalized."
}

check_tunnel_status() {
    clear
    colorize yellow "Checking all active systems status..." bold
    echo
    for config_path in "$config_dir"/iran*.toml; do
        if [ -f "$config_path" ]; then
            config_name=$(basename "$config_path" .toml)
            service_name="rathole-${config_name}.service"
            systemctl is-active --quiet "$service_name" && colorize green "$service_name is RUNNING" || colorize red "$service_name is DOWN"
        fi
    done
    for config_path in "$config_dir"/kharej*.toml; do
        if [ -f "$config_path" ]; then
            config_name=$(basename "$config_path" .toml)
            service_name="rathole-${config_name}.service"
            systemctl is-active --quiet "$service_name" && colorize green "$service_name is RUNNING" || colorize red "$service_name is DOWN"
        fi
    done
    if systemctl is-active --quiet khalifeh-proxy.service; then
        colorize green "khalifeh-proxy.service (Fix-Ping Proxy Corridor) is RUNNING"
    fi
    echo
    press_key
}

tunnel_management() {
    clear
    colorize cyan "List of existing services to manage:" bold
    local index=1
    declare -a configs

    for config_path in "$config_dir"/iran*.toml "$config_dir"/kharej*.toml; do
        if [ -f "$config_path" ]; then
            configs+=("$config_path")
            echo -e "${MAGENTA}${index}${NC}) $(basename "$config_path")"
            ((index++))
        fi
    done
    
    if [ ${#configs[@]} -eq 0 ]; then colorize red "No active configurations found."; press_key; return; fi
    
    echo -ne "\nEnter choice (0 to return): "
    read choice
    if (( choice == 0 )) 2>/dev/null || [ -z "$choice" ]; then return; fi
    
    selected_config="${configs[$((choice - 1))]}"
    config_name=$(basename "$selected_config" .toml)
    service_name="rathole-${config_name}.service"

    clear
    colorize cyan "Commands for $service_name:" bold
    echo "1) Remove this tunnel"
    echo "2) Restart this tunnel"
    echo "3) Add a new port configuration"
    echo "4) View live service logs"
    read -p "Action: " act
    
    case $act in
        1) destroy_tunnel "$selected_config" ;;
        2) systemctl restart "$service_name" && colorize green "Restarted." ;;
        3) add_new_config "$selected_config" ;;
        4) journalctl -eu "$service_name" -n 50 --no-pager ;;
    esac
    press_key
}

destroy_tunnel(){
    local config_path="$1"
    local config_name=$(basename "$config_path" .toml)
    local service_name="rathole-${config_name}.service"
    systemctl disable --now "$service_name" >/dev/null 2>&1
    rm -f "$config_path" "${service_dir}/${service_name}"
    systemctl daemon-reload
    colorize red "Tunnel wiped successfully."
}

add_new_config(){
    local config_path="$1"
    read -p "Enter new ports separated by commas: " input_ports
    input_ports=$(echo "$input_ports" | tr -d ' ')
    IFS=',' read -r -a ports <<< "$input_ports"
    
    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            clear_port_clash "$port"
            ufw allow $port/tcp >/dev/null 2>&1
            if grep -q "iran" <<< "$config_path"; then
                cat << EOF >> "$config_path"
[server.services.port_${port}]
type = "tcp"
bind_addr = "0.0.0.0:${port}"
EOF
            else
                cat << EOF >> "$config_path"
[client.services.port_${port}]
type = "tcp"
local_addr = "127.0.0.1:${port}"
EOF
            fi
        fi
    done
    config_name=$(basename "$config_path" .toml)
    systemctl restart "rathole-${config_name}.service"
    colorize green "Ports integrated cleanly."
}

wipe_all_services() {
    clear
    colorize red "Wiping all rathole and proxy infrastructure..." bold
    systemctl disable --now khalifeh-proxy.service >/dev/null 2>&1
    rm -f ${service_dir}/khalifeh-proxy.service
    
    for service in $(systemctl list-units --type=service --all | grep rathole | awk '{print $1}'); do
        systemctl disable --now "$service" >/dev/null 2>&1
        rm -f "${service_dir}/${service}"
    done
    rm -rf "$config_dir"
    systemctl daemon-reload
    colorize green "Everything uninstalled successfully."
    press_key
}

while true; do
    clear
    display_logo
    display_server_info
    display_rathole_core_status
    echo "1) Configure Tunnel Pipeline"
    echo "2) Check Tunnel Live Status"
    echo "3) Manage / Reconfigure Existing Tunnels"
    echo "4) Wipe/Stop All Infrastructure Services"
    echo "0) Exit"
    echo -ne "\nSelect an option: "
    read opt
    case $opt in
        1) configure_tunnel ;;
        2) check_tunnel_status ;;
        3) tunnel_management ;;
        4) wipe_all_services ;;
        0) exit 0 ;;
    esac
done
