/*
 * Widget Plasma : etat et bascule de la connexion LTE du modem Intel XMM7360.
 *
 * Le modem est en mode RPC, que ModemManager refuse de piloter : il est donc
 * invisible pour NetworkManager et pour le widget reseau de Plasma. Ce widget
 * lit a la place l'etat de l'unite systemd xmm7360.service et de l'interface
 * wwan0, et pilote l'unite via systemctl (autorise sans mot de passe par la
 * regle polkit 49-xmm7360.rules).
 *
 * Les chaines sont en dur, sans i18n() : ce widget est local et n'a pas de
 * catalogue de traduction.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property string unit: "xmm7360.service"
    // Le sondage vit dans xmm7360-status, qui garantit une sortie a 5 lignes.
    // L'ecrire ici rendrait le QML illisible et impossible a tester seul.
    readonly property string pollCommand: "xmm7360-status"
    readonly property string logFile: "/var/log/xmm7360.log"

    property string unitState: "unknown"
    property string ipAddress: ""
    property real rxBytes: -1
    property real txBytes: -1
    property int elapsedSeconds: -1
    property bool commandPending: false

    readonly property bool connected: unitState === "active"
    readonly property bool failed: unitState === "failed"
    // Le modem s'eteint en veille mais l'unite reste active (RemainAfterExit) :
    // unite active sans adresse IP = liaison morte, a afficher honnetement.
    readonly property bool stale: connected && !busy && ipAddress === ""
    // systemctl passe par "activating"/"deactivating" : on les traite comme
    // une operation en cours au meme titre qu'une commande lancee d'ici.
    readonly property bool busy: commandPending
        || unitState === "activating"
        || unitState === "deactivating"

    readonly property string statusIcon: busy
        ? "network-mobile-available-symbolic"
        : stale ? "network-limited-symbolic"
        : connected ? "network-mobile-100-lte-symbolic"
                    : "network-mobile-off-symbolic"

    readonly property string statusText: busy
        ? "Opération en cours…"
        : stale ? "Liaison perdue — reconnectez"
        : connected ? "Connectée"
        : failed ? "Échec de la connexion"
                 : "Déconnectée"

    // Bases 1024 et unites CEI, coherent avec le reste de Plasma.
    function formatBytes(n) {
        if (n < 0) {
            return "—";
        }
        const units = ["o", "Kio", "Mio", "Gio", "Tio"];
        let i = 0;
        let v = n;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
    }

    function formatDuration(s) {
        if (s < 0) {
            return "—";
        }
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (h > 0) {
            return h + " h " + (m < 10 ? "0" : "") + m + " min";
        }
        if (m > 0) {
            return m + " min";
        }
        return s + " s";
    }

    function toInt(s) {
        const v = parseInt(s, 10);
        return isNaN(v) ? -1 : v;
    }

    Plasmoid.icon: statusIcon

    toolTipMainText: "Connexion 4G"
    toolTipSubText: connected
        ? (ipAddress !== "" ? ipAddress + "\n" : "")
          + "↓ " + formatBytes(rxBytes) + "   ↑ " + formatBytes(txBytes)
        : statusText

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Reconnecter"
            icon.name: "view-refresh"
            enabled: root.connected && !root.busy
            onTriggered: root.reconnect()
        },
        PlasmaCore.Action {
            text: "Ouvrir le journal"
            icon.name: "text-x-generic"
            onTriggered: root.openLog()
        }
    ]

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            const stdout = data["stdout"] || "";
            disconnectSource(source);
            root.handleResult(source, stdout);
        }

        function run(cmd) {
            connectSource(cmd);
        }
    }

    function handleResult(source, stdout) {
        if (source === pollCommand) {
            const l = stdout.split("\n");
            unitState = (l[0] || "").trim();
            ipAddress = (l[1] || "").trim();
            rxBytes = toInt((l[2] || "").trim());
            txBytes = toInt((l[3] || "").trim());
            elapsedSeconds = toInt((l[4] || "").trim());
            return;
        }
        // Ne liberer le verrou que pour les commandes qui l'ont pose : ouvrir
        // le journal ne doit pas debloquer une bascule encore en cours.
        if (source.indexOf("systemctl ") === 0) {
            commandPending = false;
        }
        poll();
    }

    function poll() {
        executable.run(pollCommand);
    }

    function toggle() {
        if (busy) {
            return;
        }
        commandPending = true;
        executable.run(connected ? "systemctl stop " + unit
                                 : "systemctl start " + unit);
    }

    function reconnect() {
        if (busy) {
            return;
        }
        commandPending = true;
        executable.run("systemctl restart " + unit);
    }

    function openLog() {
        executable.run("xdg-open " + logFile);
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    compactRepresentation: MouseArea {
        id: compactRoot

        // Le clic gauche deplie la fenetre, conformement a l'usage Plasma ;
        // le clic du milieu bascule directement, pour l'acces en un geste.
        property bool wasExpanded: false

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onPressed: mouse => {
            wasExpanded = root.expanded;
        }
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.toggle();
            } else {
                root.expanded = !wasExpanded;
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: root.statusIcon
            active: compactRoot.containsMouse
            opacity: root.connected || root.busy ? 1.0 : 0.65
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 15

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: root.statusIcon
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Kirigami.Heading {
                        level: 3
                        text: "Connexion 4G"
                    }

                    PlasmaComponents.Label {
                        text: root.statusText
                        opacity: 0.7
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "Adresse IP :"
                    opacity: 0.7
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.ipAddress !== "" ? root.ipAddress : "aucune"
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    text: "Reçu :"
                    opacity: 0.7
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.formatBytes(root.rxBytes)
                }

                PlasmaComponents.Label {
                    text: "Émis :"
                    opacity: 0.7
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.formatBytes(root.txBytes)
                }

                PlasmaComponents.Label {
                    visible: root.connected
                    text: "Depuis :"
                    opacity: 0.7
                }
                PlasmaComponents.Label {
                    visible: root.connected
                    Layout.fillWidth: true
                    text: root.formatDuration(root.elapsedSeconds)
                }

                PlasmaComponents.Label {
                    text: "Opérateur :"
                    opacity: 0.7
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: "Free (APN free)"
                }
            }

            Item {
                Layout.fillHeight: true
            }

            PlasmaComponents.Button {
                Layout.fillWidth: true
                enabled: !root.busy
                icon.name: root.connected ? "network-disconnect" : "network-connect"
                text: root.busy ? "Veuillez patienter…"
                     : root.stale ? "Reconnecter"
                     : root.connected ? "Déconnecter" : "Connecter"
                onClicked: root.stale ? root.reconnect() : root.toggle()
            }
        }
    }
}
