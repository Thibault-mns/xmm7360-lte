# xmm7360-lte

Mise en service de la 4G d'un **ThinkPad X1 Yoga 3rd (20LD)** sous **CachyOS**,
modem **Intel XMM7360 / Fibocom L850-GL** (PCI `8086:7360`), avec intégration
au bureau KDE Plasma 6.

Établi le 2026-09-01 sur le noyau 7.2.2-1-cachyos, Plasma 6.7.4, ModemManager
1.24.2, pyroute2 0.9.6.

## Le problème

Le modem est présent et détecté sur le bus PCI, mais **ModemManager ne peut pas
le piloter** : il est en *mode RPC* (protocole propriétaire Intel), et le plugin
Intel de ModemManager refuse ce mode par conception. La chaîne est en dur dans
le binaire :

```
Intel XMM7360 in RPC mode not supported
```

Ce n'est pas un défaut de configuration : aucun réglage de ModemManager n'y
changera quoi que ce soit. Le modem n'expose aucun port MBIM, seulement des
ports AT (muets tant que la séquence RPC n'a pas tourné) et un port RPC.

## La solution

Le pilote noyau **`iosm`**, qui est *in-tree* et gère `8086:7360`, plus les
scripts Python RPC du projet [xmm7360-pci](https://github.com/xmm7360/xmm7360-pci).

**Le module noyau de `xmm7360-pci` n'a pas besoin d'être compilé.** Son
`rpc/rpc.py` cible déjà le port du pilote officiel :

```python
def __init__(self, interfaces=['/dev/xmm0/rpc', '/dev/wwan0xmmrpc0']):
```

Ce dépôt-ci n'apporte que l'enrobage : scripts de connexion, unités systemd,
règle polkit, lanceur et widget Plasma.

## Prérequis

```bash
sudo pacman -S --needed python-pyroute2 python-configargparse python-dbus
git clone https://github.com/xmm7360/xmm7360-pci ~/xmm7360-pci
```

Vérifier qu'`iosm` **n'est pas** blacklisté dans `/etc/modprobe.d/`.

## Installation

```bash
./install.sh
```

À lancer en utilisateur normal — le script appelle `sudo` lui-même pour les
fichiers système, et doit poser le widget dans le `$HOME` courant. Il applique
aussi le correctif pyroute2 à `~/xmm7360-pci` s'il manque.

Puis, pour le widget :

```bash
systemctl --user restart plasma-plasmashell.service
```

Clic droit sur le panneau → *Ajouter des widgets* → « 4G ».

## Usage

| Action | Commande |
| --- | --- |
| Connecter | `systemctl start xmm7360` |
| Déconnecter | `systemctl stop xmm7360` |
| Au démarrage + réveil de veille | `sudo systemctl enable xmm7360 xmm7360-resume` |
| État complet | `xmm7360-status` |
| Journal détaillé | `/var/log/xmm7360.log` |

La règle polkit autorise `start`/`stop`/`restart` de l'unité sans mot de passe
pour le groupe `wheel`, depuis une session locale active — c'est ce qui permet
au widget et au lanceur de fonctionner d'un clic.

Le widget offre en plus : icône d'état dans le panneau, infobulle avec l'IP et
le trafic, **consommation cumulée du mois calendaire** (tenue par
`xmm7360-status` dans `~/.local/state/xmm7360/usage` — elle ne compte que
pendant que le widget sonde, soit au pire ~5 s de trafic perdues par session),
clic du milieu pour basculer, et deux actions au clic droit (*Reconnecter*,
*Ouvrir le journal*).

À la connexion, les DNS fournis par l'opérateur sont déclarés à
systemd-resolved sur `wwan0` (`resolvectl`) ; sans resolved, la résolution
retombe sur ses serveurs de secours et fonctionne quand même.

**Radio éteinte au démarrage** : `modprobe/xmm7360-lte.conf` blackliste
`iosm` pour que le modem reste hors tension au boot. C'est sûr *uniquement*
parce que `xmm7360-connect` charge le module explicitement (un blacklist ne
bloque que le chargement automatique par alias, jamais un `modprobe`
explicite). Supprimer ce fichier pour retrouver un modem alimenté dès le
boot — par exemple pour que `enable xmm7360` connecte immédiatement après
l'ouverture de session sans la latence du chargement.

## Changer d'opérateur (APN)

L'APN est le seul paramètre propre à l'opérateur. **Le plus simple : le
sélecteur dans le widget** (liste déroulante éditable, presets des quatre
opérateurs français) — il écrit la configuration via `xmm7360-apn` et
relance la connexion si elle est active.

En ligne de commande : `xmm7360-apn set <apn>` puis
`systemctl restart xmm7360`, ou éditer directement
`~/xmm7360-pci/xmm7360.ini` (`apn=...`). APN grand public
français : Free `free`, Orange/Sosh `orange`, SFR/RED `sl2sfr`,
Bouygues/B&You `mmsbouygtel.com` ; pour un MVNO, chercher « APN Android »
dans sa doc. Un APN faux donne un attach sans adresse IP — visible dans
`/var/log/xmm7360.log`.

**Code PIN : à désactiver.** Cette pile ne sait pas présenter le PIN — la
méthode du projet amont passe par les ports AT, muets en mode RPC. Mettre
la SIM dans un téléphone et désactiver le verrouillage SIM avant de
l'insérer dans le PC.

Au passage : le journal `/var/log/xmm7360.log` est tronqué à chaque
connexion et ne contient que la dernière session (~60 Ko au plus). Il ne
grossit pas.

## Les trois pièges rencontrés

1. **`blacklist iosm`** dans `/etc/modprobe.d/`, posé pour préparer
   l'installation du module communautaire. La compilation de celui-ci avait
   échoué, laissant le modem sans aucun pilote — un blacklist n'est
   inoffensif que si quelque chose charge le module explicitement. Ce dépôt
   en installe d'ailleurs un (`modprobe/xmm7360-lte.conf`, radio éteinte au
   boot), mais accompagné du `modprobe iosm` explicite de `xmm7360-connect`.
2. **La compilation du module communautaire** est inutile — voir plus haut, les
   scripts RPC parlent directement au pilote noyau.
3. **pyroute2 ≥ 0.9 casse `open_xdatachannel.py`** : `dst='default'` n'infère
   plus la famille d'adresses, le noyau reçoit `AF_UNSPEC` et répond
   `EOPNOTSUPP (95)`. Le crash survenait *avant* les appels qui ouvrent le canal
   de données, d'où une IP obtenue mais aucun trafic possible — un symptôme très
   trompeur. Correctif dans `patches/`.

## Limites connues

- **Pas d'indicateur de qualité de signal.** Les appels RPC existent
  (`UtaMsNetSingleShotRadioSignalReportingReq` 0x55,
  `UtaMsNetGetExtendedRadioSignalInfoReq` 0xEC) mais aucun `pack`/`unpack` n'est
  implémenté dans `xmm7360-pci`, et une lecture continue supposerait un démon
  gardant le canal RPC ouvert. Faisable, mais c'est un projet en soi.
- **Pas d'intégration NetworkManager.** L'option `dbus=True` de
  `xmm7360.ini` crée bien un profil NM visible dans le widget réseau, mais son
  bouton « Connecter » n'applique qu'une IP statique sans lancer la séquence
  RPC : l'indicateur mentirait. Elle force en plus `ipv6: ignore`, ce qui fait
  perdre l'IPv6. Écartée volontairement.
- **Le modem s'éteint en veille.** D'où `xmm7360-resume.service`, et le
  rechargement de `iosm` en second essai dans `xmm7360-connect`.
- **Codes de retour inexploitables** : `open_xdatachannel.py` sort en 1 en cas
  de succès (`sys.exit(1)` final) et en 0 quand l'ouverture RPC échoue. Les
  scripts jugent donc sur la présence d'une adresse IP, jamais sur `$?`.
- **Le correctif pyroute2 est local à `~/xmm7360-pci`** : un `git pull` amont
  l'écrasera. `install.sh` le réapplique.

## Dépannage

```bash
xmm7360-status                     # état, IP, trafic, durée
systemctl status xmm7360
tail -40 /var/log/xmm7360.log
lspci -k -s 04:00.0                # doit afficher : Kernel driver in use: iosm
ls /sys/class/wwan/wwan0/          # doit lister wwan0at0, wwan0at1, wwan0xmmrpc0
ping -c3 -I wwan0 9.9.9.9          # force le test par la 4G, pas par le Wi-Fi
journalctl --user -u plasma-plasmashell -n 50   # erreurs QML du widget
```

Les ports AT (`/dev/wwan0at*`) sont **muets** en mode RPC : inutile de les
interroger, l'absence de réponse est normale.

## Contenu

```
bin/xmm7360-connect       établit la connexion (juge sur l'IP, recharge iosm au besoin)
bin/xmm7360-disconnect    coupe la radio en déchargeant iosm
bin/xmm7360-toggle        bascule + notification de bureau
bin/xmm7360-status        état en 6 lignes (dont cumul mensuel), consommé par le widget
bin/xmm7360-apn           lecture/écriture validée de l'APN (widget et CLI)
systemd/                  unité principale + relance au réveil de veille
polkit/                   start/stop sans mot de passe pour le groupe wheel
modprobe/                 radio éteinte au boot (blacklist + chargement explicite)
plasmoid/                 widget Plasma 6
desktop/                  lanceur pour le menu KDE
patches/                  correctif pyroute2 ≥ 0.9 pour xmm7360-pci
config/                   exemple de xmm7360.ini (APN)
```

## Licence

MIT pour le contenu de ce dépôt. `xmm7360-pci` est sous double licence
BSD / GPL, voir son propre dépôt.
