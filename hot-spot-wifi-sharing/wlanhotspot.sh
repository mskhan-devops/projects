#!/bin/bash

echo "########################################"
echo "#                                      #"
echo "#       Wifi Hotspot Setup Script      #"
echo "# Made with love by j12tee - version 1 #"
echo "#                                      #"
echo "########################################"

if [[ $1 == "help" || $1 == "" ]]; then
    echo ">>> Executing command 'help'..."
    echo "USAGE: wlanhotspot.sh [command] [ssid] [password] [band] [device]"
    echo "         command  : (required) The command to use. Either 'help', 'start', 'stop', or 'info'."
    echo "         ssid     : (optional) The SSID of the hotspot."
    echo "         password : (optional) The password of the hotspot."
    echo "         band     : (optional) The Wifi band to use. Either 'bg' or 'a'. For 2.4GHz band only, use 'bg'. To use 5GHz if available, use 'a'."
    echo "         device   : (optional) The network device to use."
    echo "NOTE: You can create /etc/.wlanhotspotrc file to define values."
    echo "EXAMPLE:"
    echo "       wlanhotspot.sh help"
    echo "       wlanhotspot.sh info"
    echo "       wlanhotspot.sh start"
    echo "       wlanhotspot.sh stop"
    echo "       wlanhotspot.sh start teepot j12teepot"
    echo "       wlanhotspot.sh stop teepot"
    exit 0
fi

echo ">>> Configuring values..."

if [[ -e "/etc/.wlanhotspotrc" ]]; then
    echo "Config file found! Loading the file .wlanhotspotrc"
    source /etc/.wlanhotspotrc
else
    echo "Config file not found! Using in-line arguments..."
    SSID="${2:-LQTWLAN}"
    PWD="${3:-su123456789}"
    BAND="${4:-bg}" # bg=2.4GHz_fixed a=5GHz_if_available
    DEV="${5:-wlp0s20f3}"
fi

echo "ssid='$SSID' pwd='$PWD' band='$BAND' dev='$DEV'"

start() {
    echo "Creating hotspot ssid=\"$SSID\"..."
    nmcli connection add type wifi ifname "$DEV" con-name "$SSID" autoconnect yes ssid "$SSID"
    nmcli connection modify "$SSID" 802-11-wireless.mode ap 802-11-wireless.band "$BAND"
    nmcli connection modify "$SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PWD"
    nmcli connection modify "$SSID" ipv4.method shared
    echo "Starting hotspot ssid=\"$SSID\"..."
    nmcli connection up "$SSID"
    echo "Done!"
}

stop() {
    echo "Stopping hotspot ssid=\"$SSID\"..."
    nmcli connection down "$SSID"
    echo "Cleaning up..."
    nmcli connection delete "$SSID"
    echo "Resetting WLAN mode..."
    nmcli radio wifi off
    nmcli radio wifi on
    echo "Done!"
}

info() {
    echo "==== Hotspot Config ====" > /tmp/hpi
    echo "SSID: $SSID" >> /tmp/hpi
    echo "PASS: $PWD" >> /tmp/hpi
    echo "BAND: $BAND" >> /tmp/hpi
    echo "DEV : $DEV" >> /tmp/hpi
    echo "==== Applied Config from NetworkManager ====" >> /tmp/hpi
    echo ">>> WLAN Status" >> /tmp/hpi
    nmcli d status | grep --color=never "wifi" >> /tmp/hpi
    echo ">>> Hotspot status" >> /tmp/hpi
    nmcli connection show "$SSID" >> /tmp/hpi
    less /tmp/hpi
    rm -f /tmp/hpi
}

if [[ $1 == "start" ]]; then
    echo ">>> Executing command 'start'..."
    start
fi

if [[ $1 == "stop" ]]; then
    echo ">>> Executing command 'stop'..."
    stop
fi

if [[ $1 == "info" ]]; then
    echo ">>> Executing command 'info'..."
    info
fi

echo ">>> End."