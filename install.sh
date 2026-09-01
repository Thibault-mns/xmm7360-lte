#!/bin/bash
# Installe la connexion LTE XMM7360 : scripts, unites systemd, regle polkit,
# lanceur et widget Plasma.
#
# A lancer en utilisateur normal, PAS avec sudo : les parties systeme appellent
# sudo elles-memes, et les fichiers utilisateur (widget, lanceur) doivent
# atterrir dans le $HOME de l'utilisateur courant.
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)

if [ "$(id -u)" -eq 0 ]; then
    echo "Ne lancez pas ce script avec sudo : il appelle sudo lui-meme pour" >&2
    echo "les fichiers systeme, et doit poser le widget dans le \$HOME de" >&2
    echo "l'utilisateur courant." >&2
    exit 1
fi

echo "==> scripts dans /usr/local/bin"
sudo install -m755 "$SRC"/bin/xmm7360-connect    /usr/local/bin/
sudo install -m755 "$SRC"/bin/xmm7360-disconnect /usr/local/bin/
sudo install -m755 "$SRC"/bin/xmm7360-toggle     /usr/local/bin/
sudo install -m755 "$SRC"/bin/xmm7360-status     /usr/local/bin/

echo "==> unites systemd"
sudo install -m644 "$SRC"/systemd/xmm7360.service        /etc/systemd/system/
sudo install -m644 "$SRC"/systemd/xmm7360-resume.service /etc/systemd/system/
sudo systemctl daemon-reload

echo "==> regle polkit"
sudo install -m644 "$SRC"/polkit/49-xmm7360.rules /etc/polkit-1/rules.d/

echo "==> verification du blacklist iosm"
if grep -rqs "^blacklist[[:space:]]\+iosm" /etc/modprobe.d/; then
    echo "    ATTENTION : iosm est blackliste dans /etc/modprobe.d/, le modem" >&2
    echo "    restera sans pilote. Retirez cette ligne." >&2
fi

echo "==> lanceur et widget (utilisateur $USER)"
install -Dm644 "$SRC"/desktop/xmm7360.desktop \
    "$HOME/.local/share/applications/xmm7360.desktop"
mkdir -p "$HOME/.local/share/plasma/plasmoids"
cp -r "$SRC"/plasmoid/org.kde.xmm7360 "$HOME/.local/share/plasma/plasmoids/"

echo "==> xmm7360-pci"
XMM_REPO="${XMM7360_REPO:-$HOME/xmm7360-pci}"
if [ -d "$XMM_REPO" ]; then
    if [ ! -f "$XMM_REPO/xmm7360.ini" ]; then
        cp "$SRC"/config/xmm7360.ini.example "$XMM_REPO/xmm7360.ini"
        echo "    xmm7360.ini cree : verifiez l'APN."
    fi
    if ! grep -q "family=socket.AF_INET" "$XMM_REPO/rpc/open_xdatachannel.py"; then
        echo "    application du correctif pyroute2"
        git -C "$XMM_REPO" apply "$SRC"/patches/0001-pyroute2-0.9-address-family.patch
    fi
else
    echo "    ATTENTION : $XMM_REPO absent. Clonez le depot amont :" >&2
    echo "    git clone https://github.com/xmm7360/xmm7360-pci $XMM_REPO" >&2
fi

echo
echo "Installation terminee."
echo "  connexion       : systemctl start xmm7360   (ou le widget)"
echo "  au demarrage    : sudo systemctl enable xmm7360 xmm7360-resume"
echo "  widget          : systemctl --user restart plasma-plasmashell.service"
echo "                    puis clic droit sur le panneau > Ajouter des widgets"
