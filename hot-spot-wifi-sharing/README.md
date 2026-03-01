# hot-spot‑wifi‑sharing

A bash utility that turns your laptop’s existing Wi‑Fi connection into a **wireless hotspot** that other devices can join.  
It is fully CLI‑driven, works on most Linux distributions (Ubuntu, Debian, Fedora, Arch) and requires only the standard networking tools.

---

## Features

| Feature | Description |
|---------|-------------|
| **AP creation** | Brings up a virtual interface (`wlan0` → `ap0`) and configures it as an access point. |
| **DHCP service** | Spins up `dnsmasq` to hand out IP addresses to connected clients. |
| **NAT** | Enables `iptables`‑based masquerading so clients reach the Internet via the laptop. |
| **Pre‑flight checks** | Verifies that the Wi‑Fi driver supports AP mode before starting. |
| **Process validation** | Confirms `hostapd` & `dnsmasq` start successfully. |
| **Logging** | All diagnostic output is timestamped and written to `/var/log/wifi‑share.log`. |
| **Verbose mode** | `-v` prints debug output to the console in real time. |

---

## Prerequisites

```bash
sudo apt-get install hostapd dnsmasq iproute2 iptables  # Debian/Ubuntu
sudo dnf install hostapd dnsmasq iproute iptables      # Fedora
sudo pacman -S hostapd dnsmasq iproute2 iptables       # Arch
```

> **Note:** Replace `wlan0` in the script with your actual wireless interface name if it differs.

---

## Installation

```bash
# 1️⃣ Copy the script to a directory in your $PATH
sudo cp wifi‑share.sh /usr/local/bin/wifi‑share

# 2️⃣ Make it executable
sudo chmod +x /usr/local/bin/wifi‑share
```

---

## Configuration (first‑time setup)

```bash
# Prompts for SSID and password and writes them to /etc/wifi‑share.conf
sudo wifi‑share configure
```

All further invocations use the stored credentials.

---

## Usage

| Command | Description |
|---------|-------------|
| `sudo wifi‑share start` | Starts the hotspot in normal mode. |
| `sudo wifi‑share start -v` | Starts the hotspot with verbose console output. |
| `sudo wifi‑share stop` | Stops the hotspot and cleans up. |
| `sudo wifi‑share status` | Shows the current hotspot state. |
| `sudo wifi‑share configure` | Re‑run configuration wizard. |

After a few seconds the hotspot SSID (default `LaptopHotspot`) should appear on any device. Connect using the password stored in the config file.

---

## Logging

All operations are logged to **/var/log/wifi‑share.log** with a `[YYYY‑MM‑DD HH:MM:SS]` timestamp.

```bash
sudo tail -f /var/log/wifi‑share.log
```

---

## Troubleshooting

| Symptom | Likely Cause | Remedy |
|---------|--------------|--------|
| `hostapd` fails to start | Driver doesn’t support AP mode | Verify `iw list` shows `Supported interface modes` containing `AP` |
| Clients never receive IP | `dnsmasq` not running | Check log file for `dnsmasq` errors; ensure `/etc/dnsmasq.conf` is correct |
| No Internet for clients | MTU or routing issue | Ensure `iptables -t nat -A POSTROUTING -o <WAN_IFACE> -j MASQUERADE` is correct; verify MTU on `ap0` |

---

## FAQ

**Why is the script named `wifi‑share` and not `wifi‑share.sh`?**  
Once the script is in `$PATH` it is executed as a normal command, hiding the file extension for a cleaner command line.

**Can I run the hotspot without root?**  
All networking changes require elevated privileges; run the command with `sudo`.

**How do I stop the script if it hangs?**  
Press `Ctrl+C`. The cleanup handler will disable the hotspot and stop both services.

---