#!/bin/bash
#
# wifi-share - Share your WiFi internet connection as an access point
# 
# Usage: wifi-share [start|stop|configure] [-v|--verbose]
#

set -e

SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE="/etc/wifi-share.conf"
LOG_FILE="/var/log/wifi-share.log"

VERBOSE=false

DEFAULT_SSID="MyHotspot"
DEFAULT_PASSWORD="password123"
DEFAULT_AP_IP="192.168.45.1"
DEFAULT_DHCP_RANGE="192.168.45.20,192.168.45.100"
DEFAULT_NETMASK="255.255.255.0"

detect_internet_interface() {
    local iface
    iface=$(ip route | awk '/default/ {print $5; exit}')
    if [[ -z "$iface" ]]; then
        log_error "Could not detect internet interface. Are you connected to the internet?"
        return 1
    fi
    echo "$iface"
}

detect_wireless_interface() {
    local iface
    iface=$(ip -o link show | awk -F': ' '{print $2}' | while read -r i; do
        if iw "$i" info >/dev/null 2>&1; then
            echo "$i"
            break
        fi
    done)
    
    if [[ -z "$iface" ]]; then
        log_error "Could not detect wireless interface. Is your WiFi card working?"
        return 1
    fi
    echo "$iface"
}

check_driver_ap_support() {
    local wlan="$1"
    local phy
    local mode
    
    phy=$(iw dev "$wlan" info 2>/dev/null | awk '/wiphy/ {print "phy"$2}')
    mode=$(iw phy "$phy" info 2>/dev/null | grep -i "supported interface modes" -A 10 | grep -i "AP" || true)
    
    if [[ -z "$mode" ]]; then
        log_error "WiFi driver does not support AP mode on $wlan"
        log_error "This often happens with:"
        log_error "  - Broadcom BCM4311, BCM4312, BCM4313, BCM4321, BCM4322, BCM43224, BCM43225, BCM43227, BCM43228"
        log_error "  - Intel Centrino cards (use iw list to check)"
        log_error "Consider using a USB WiFi adapter with AP support (e.g., Atheros, Ralink, Realtek)"
        return 1
    fi
    log_info "Driver supports AP mode on $wlan"
}

check_dependencies() {
    local missing=()
    
    for cmd in hostapd dnsmasq iptables; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing dependencies: ${missing[*]}"
        log_info "Installing dependencies..."
        
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq
            apt-get install -y -qq "${missing[@]}" || {
                log_error "Failed to install dependencies. Please install manually:"
                log_error "  sudo apt-get install ${missing[*]}"
                return 1
            }
        else
            log_error "Unsupported package manager. Please install manually:"
            log_error "  ${missing[*]}"
            return 1
        fi
    fi
    
    log_info "All dependencies satisfied"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        SSID="$DEFAULT_SSID"
        PASSWORD="$DEFAULT_PASSWORD"
        AP_IP="$DEFAULT_AP_IP"
        DHCP_RANGE="$DEFAULT_DHCP_RANGE"
        NETMASK="$DEFAULT_NETMASK"
    fi
    
    SSID="${SSID:-$DEFAULT_SSID}"
    PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
    AP_IP="${AP_IP:-$DEFAULT_AP_IP}"
    DHCP_RANGE="${DHCP_RANGE:-$DEFAULT_DHCP_RANGE}"
    NETMASK="${NETMASK:-$DEFAULT_NETMASK}"
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
# wifi-share configuration
# Generated on $(date)

SSID="$SSID"
PASSWORD="$PASSWORD"
AP_IP="$AP_IP"
DHCP_RANGE="$DHCP_RANGE"
NETMASK="$NETMASK"
WLAN_INTERFACE="$WLAN_INTERFACE"
INTERNET_INTERFACE="$INTERNET_INTERFACE"
EOF
    log_info "Configuration saved to $CONFIG_FILE"
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" | tee -a "$LOG_FILE"
    fi
}

stop_hotspot() {
    log_info "Stopping WiFi hotspot..."
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Killing hostapd..."
    fi
    if pgrep -x hostapd >/dev/null 2>&1; then
        pkill hostapd || true
        sleep 1
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Killing dnsmasq..."
    fi
    if pgrep -x dnsmasq >/dev/null 2>&1; then
        pkill dnsmasq || true
        sleep 1
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Removing virtual interface..."
    fi
    if ip link show "${WLAN_INTERFACE}ap" >/dev/null 2>&1; then
        iw dev "${WLAN_INTERFACE}ap" del 2>/dev/null || ip link delete "${WLAN_INTERFACE}ap" 2>/dev/null || true
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Flushing iptables NAT rules..."
    fi
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -F FORWARD 2>/dev/null || true
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Disabling IP forwarding..."
    fi
    echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
    
    log_info "Hotspot stopped"
}

configure_hotspot() {
    echo "=== WiFi Hotspot Configuration ==="
    echo
    
    echo -n "Enter SSID (WiFi name) [$DEFAULT_SSID]: "
    read -r input
    SSID="${input:-$DEFAULT_SSID}"
    
    while true; do
        echo -n "Enter password (min 8 characters) [$DEFAULT_PASSWORD]: "
        read -r -s input
        PASSWORD="${input:-$DEFAULT_PASSWORD}"
        if [[ ${#PASSWORD} -lt 8 ]]; then
            echo
            echo "Error: Password must be at least 8 characters"
        else
            break
        fi
    done
    echo
    
    echo -n "Enter AP IP address [$DEFAULT_AP_IP]: "
    read -r input
    AP_IP="${input:-$DEFAULT_AP_IP}"
    
    echo -n "Enter DHCP range (start,end) [$DEFAULT_DHCP_RANGE]: "
    read -r input
    DHCP_RANGE="${input:-$DEFAULT_DHCP_RANGE}"
    
    echo -n "Enter netmask [$DEFAULT_NETMASK]: "
    read -r input
    NETMASK="${input:-$DEFAULT_NETMASK}"
    
    save_config
    
    echo
    echo "Configuration complete!"
    echo "Run 'wifi-share start' to start the hotspot"
}

start_hotspot() {
    log_info "Starting WiFi hotspot..."
    
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    check_dependencies
    load_config
    
    INTERNET_INTERFACE=$(detect_internet_interface)
    log_info "Internet interface: $INTERNET_INTERFACE"
    
    WLAN_INTERFACE=$(detect_wireless_interface)
    log_info "Wireless interface: $WLAN_INTERFACE"
    
    check_driver_ap_support "$WLAN_INTERFACE"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Configuration:"
        log_debug "  SSID: $SSID"
        log_debug "  AP IP: $AP_IP"
        log_debug "  DHCP Range: $DHCP_RANGE"
        log_debug "  Netmask: $NETMASK"
    fi
    
    log_info "Setting up virtual AP interface..."
    
    ip link show "${WLAN_INTERFACE}ap" >/dev/null 2>&1 && {
        log_warn "Virtual interface already exists, removing..."
        iw dev "${WLAN_INTERFACE}ap" del 2>/dev/null || ip link delete "${WLAN_INTERFACE}ap" 2>/dev/null || true
    }
    
    local MAC
    # Generate a locally administered random MAC address
    MAC=$(printf '02:%02x:%02x:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    
    iw dev "$WLAN_INTERFACE" interface add "${WLAN_INTERFACE}ap" type __ap addr "$MAC" 2>/dev/null || \
        iw dev "$WLAN_INTERFACE" interface add "${WLAN_INTERFACE}ap" type __ap
    
    # Tell NetworkManager to ignore this virtual interface to avoid "Device or resource busy"
    if command -v nmcli >/dev/null 2>&1; then
        nmcli dev set "${WLAN_INTERFACE}ap" managed no 2>/dev/null || true
    fi
    

    log_info "Enabling IP forwarding..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    log_info "Configuring NAT (iptables)..."
    iptables -t nat -A POSTROUTING -o "$INTERNET_INTERFACE" -j MASQUERADE
    iptables -A FORWARD -i "$INTERNET_INTERFACE" -o "${WLAN_INTERFACE}ap" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i "${WLAN_INTERFACE}ap" -o "$INTERNET_INTERFACE" -j ACCEPT
    
    local CHNL
    CHNL=$(iw dev "$WLAN_INTERFACE" info 2>/dev/null | awk '/channel/ {print $2}')
    if [[ -z "$CHNL" ]]; then
        CHNL=6
        log_info "Using default WiFi channel $CHNL"
    else
        log_info "Using WiFi channel $CHNL (from $WLAN_INTERFACE) to satisfy driver restrictions"
    fi
    
    HOSTAPD_CONF="/tmp/hostapd-wifi-share.conf"
    log_info "Creating hostapd configuration..."
    cat > "$HOSTAPD_CONF" << EOF
interface=${WLAN_INTERFACE}ap
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHNL
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
    
    log_info "Starting hostapd..."
    if [[ "$VERBOSE" == "true" ]]; then
        hostapd -B "$HOSTAPD_CONF" -d >> "$LOG_FILE" 2>&1
    else
        hostapd -B "$HOSTAPD_CONF" >> "$LOG_FILE" 2>&1
    fi
    
    sleep 2
    
    if ! pgrep -x hostapd >/dev/null 2>&1; then
        log_error "hostapd failed to start!"
        log_error "Check $LOG_FILE for details"
        if [[ "$VERBOSE" == "false" ]]; then
            log_info "Run with -v flag for more debug information"
        fi
        exit 1
    fi
    
    log_info "Configuring AP interface IP..."
    ip addr add "${AP_IP}/${NETMASK}" dev "${WLAN_INTERFACE}ap" 2>/dev/null || true
    ip link set "${WLAN_INTERFACE}ap" up
    
    log_info "Starting DHCP server (dnsmasq)..."
    DNSMASQ_CONF="/tmp/dnsmasq-wifi-share.conf"
    cat > "$DNSMASQ_CONF" << EOF
interface=${WLAN_INTERFACE}ap
bind-interfaces
dhcp-range=$DHCP_RANGE,$NETMASK,4h
dhcp-option=3,$AP_IP
dhcp-option=6,$AP_IP
log-dhcp
EOF
    
    if [[ "$VERBOSE" == "true" ]]; then
        dnsmasq -C "$DNSMASQ_CONF" -d >> "$LOG_FILE" 2>&1 &
    else
        dnsmasq -C "$DNSMASQ_CONF" >> "$LOG_FILE" 2>&1 &
    fi
    
    sleep 2
    
    if ! pgrep -x dnsmasq >/dev/null 2>&1; then
        log_error "dnsmasq failed to start!"
        log_error "Check $LOG_FILE for details"
        stop_hotspot
        exit 1
    fi
    
    log_info "=========================================="
    log_info "WiFi Hotspot is running!"
    log_info "SSID: $SSID"
    log_info "Password: $PASSWORD"
    log_info "AP IP: $AP_IP"
    log_info "=========================================="
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Logs are being written to $LOG_FILE"
    fi
}

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [command] [options]

Commands:
    start           Start the WiFi hotspot
    stop            Stop the WiFi hotspot
    configure       Configure hotspot settings
    status          Show hotspot status

Options:
    -v, --verbose   Enable verbose logging
    -h, --help      Show this help message

Examples:
    $SCRIPT_NAME start
    $SCRIPT_NAME start -v
    $SCRIPT_NAME stop
    $SCRIPT_NAME configure

Log file: $LOG_FILE (verbose mode only)

EOF
}

main() {
    local command=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            start|stop|configure|status)
                command="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    case "$command" in
        start)
            start_hotspot
            ;;
        stop)
            if [[ $EUID -ne 0 ]]; then
                log_error "This script must be run as root (use sudo)"
                exit 1
            fi
            stop_hotspot
            ;;
        configure)
            configure_hotspot
            ;;
        status)
            if pgrep -x hostapd >/dev/null 2>&1; then
                echo "Hotspot is RUNNING"
                echo "SSID: $SSID"
                echo "AP IP: $AP_IP"
            else
                echo "Hotspot is STOPPED"
            fi
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"

