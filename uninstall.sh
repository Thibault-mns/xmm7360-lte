#!/bin/bash
# Desinstalle tout ce que pose install.sh.
# Ne touche ni a ~/xmm7360-pci, ni a /var/log/xmm7360.log.
set -uo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Ne lancez pas ce script avec sudo (voir install.sh)." >&2
    exit 1
fi

sudo systemctl disable --now xmm7360.service xmm7360-resume.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/xmm7360.service \
           /etc/systemd/system/xmm7360-resume.service
sudo systemctl daemon-reload
sudo rm -f /usr/local/bin/xmm7360-connect \
           /usr/local/bin/xmm7360-disconnect \
           /usr/local/bin/xmm7360-toggle \
           /usr/local/bin/xmm7360-status
sudo rm -f /etc/polkit-1/rules.d/49-xmm7360.rules

rm -f "$HOME/.local/share/applications/xmm7360.desktop"
rm -rf "$HOME/.local/share/plasma/plasmoids/org.kde.xmm7360"

echo "Desinstalle. ~/xmm7360-pci et /var/log/xmm7360.log sont conserves."
echo "Le module iosm reste charge : modprobe -r iosm pour couper la radio."
