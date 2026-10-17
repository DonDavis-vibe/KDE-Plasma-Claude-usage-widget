import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var usage: null
    property bool loading: false
    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../code/claude_usage.py").toString().replace("file://", ""))

    readonly property var limitItems: usage && usage.limits ? usage.limits.items : []
    readonly property string limitError: usage && usage.limits && usage.limits.error ? t(usage.limits.error) : ""
    readonly property var used: usage ? usage.used : null

    function limitByKey(key) {
        for (let i = 0; i < limitItems.length; ++i) {
            if (limitItems[i].key === key) return limitItems[i];
        }
        return null;
    }
    readonly property var fiveHour: limitByKey("five_hour")
    readonly property var weekly: limitByKey("seven_day")

    // POSIX single-quote escaping: the command is run through "sh -c".
    function shellQuote(str) {
        return "'" + String(str).replace(/'/g, "'\\''") + "'";
    }

    // The backend output is data, not trusted code: accept it only if it has the
    // expected shape and every limit carries a finite percentage.
    function acceptUsage(o) {
        if (!o || typeof o !== "object" || !o.limits || typeof o.limits !== "object" || !Array.isArray(o.limits.items))
            return null;
        o.limits.items = o.limits.items.filter(i => i && typeof i.percent === "number" && isFinite(i.percent));
        const u = o.used;
        if (u === undefined) o.used = null;
        else if (u !== null && (typeof u !== "object" || !u.block || !u.block.tokens || !u.today || !u.week
                                || !u.models_today || typeof u.models_today !== "object"))
            o.used = null;
        return o;
    }

    function refresh(force) {
        if (loading) return;
        loading = true;
        // -I: isolated mode (ignores PYTHON* variables and the user site directory)
        let cmd = "python3 -I " + shellQuote(scriptPath);
        if (!Plasmoid.configuration.allowTokenRefresh) cmd += " --no-refresh";
        if (force) cmd += " --force";
        exec.connectSource(cmd);
    }

    function fmtTokens(n) {
        if (n === undefined || n === null) return "–";
        if (n >= 1e9) return t("%1 Mrd", (n / 1e9).toFixed(2));
        if (n >= 1e6) return t("%1 M", (n / 1e6).toFixed(n >= 1e8 ? 0 : 1));
        if (n >= 1e3) return t("%1 k", (n / 1e3).toFixed(n >= 1e5 ? 0 : 1));
        return String(n);
    }

    function fmtRel(iso) {
        let mins = Math.max(0, Math.round((new Date(iso).getTime() - Date.now()) / 60000));
        const days = Math.floor(mins / 1440);
        const hours = Math.floor((mins % 1440) / 60);
        mins = mins % 60;
        return days > 0 ? t("%1 T %2 h", days, hours) : (hours > 0 ? t("%1 h %2 min", hours, mins) : t("%1 min", mins));
    }

    function fmtReset(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        const abs = d.toLocaleString(Qt.locale(commentSets.localeName(textSet)), d.getTime() - Date.now() > 86400000 ? "ddd HH:mm" : "HH:mm");
        return t("Reset in %1 (%2)", fmtRel(iso), abs);
    }

    function shortLabel(key, label) {
        if (key === "five_hour") return t("Aktuell");
        if (key === "seven_day") return t("Woche");
        return t(label);
    }

    // Bar colour profiles live in ColorSchemes.qml (shared with the settings page);
    // the bar fill blends smoothly between the stops of the selected profile.
    // A text label always accompanies the colour.
    ColorSchemes { id: palettes }
    readonly property int schemeIndex: palettes.clampIndex(Plasmoid.configuration.colorScheme)
    readonly property var statusStops: palettes.stops(schemeIndex)

    function statusColor(pct) {
        return palettes.colorAt(schemeIndex, pct);
    }

    // Language packs live in CommentSets.qml (shared with the settings page): each
    // brings its comments and the replacement texts for the whole interface (see
    // "ui" there); t() is i18n() plus that. The language is independent of the
    // "funny comments" switch, which only decides whether comments or plain status
    // labels are shown. A negative setting means automatic (system language).
    CommentSets { id: commentSets }
    readonly property int languageIndex: commentSets.resolve(Plasmoid.configuration.commentSet)
    readonly property var funnyComments: commentSets.comments(languageIndex)
    readonly property int textSet: languageIndex
    property int commentRoll: 0   // re-rolled on every refresh, picks the comment variant

    function t(source) {
        return commentSets.text(textSet, source, Array.prototype.slice.call(arguments, 1));
    }

    function statusText(pct) {
        if (Plasmoid.configuration.funnyComments)
            return commentSets.pick(funnyComments[pct >= 99.5 ? 10 : Math.min(9, Math.floor(pct / 10))], commentRoll);
        if (pct >= 99.5) return t("Limit erreicht");
        if (pct >= 95) return t("Fast am Limit");
        if (pct >= 75) return t("Wird knapp");
        if (pct >= 50) return t("Aufpassen");
        return t("Freie Fahrt");
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.loading = false;
            root.commentRoll = Math.floor(Math.random() * 1000);
            let parsed = null;
            try {
                parsed = root.acceptUsage(JSON.parse(data["stdout"]));
            } catch (e) {
                parsed = null;
            }
            root.usage = parsed || { used: null, limits: { items: [], error:
                String(data["stderr"] || "").split("\n")[0].slice(0, 200) || "Skript-Fehler" } };
        }
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMinutes) * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    // On the desktop the widget draws its own background so the opacity is
    // adjustable; in a panel/tray popup the system background stays.
    readonly property bool planar: Plasmoid.formFactor === PlasmaCore.Types.Planar
    Plasmoid.backgroundHints: planar ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground

    Plasmoid.icon: "utilities-system-monitor"
    Plasmoid.status: fiveHour && fiveHour.percent >= 90 ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.t("Jetzt aktualisieren")
            icon.name: "view-refresh"
            onTriggered: root.refresh(true)
        }
    ]

    toolTipMainText: t("Claude-Verbrauch")
    toolTipSubText: {
        let lines = [];
        if (fiveHour) lines.push(t("5 Stunden: %1 % genutzt", Math.round(fiveHour.percent)));
        if (weekly) lines.push(t("Woche: %1 % genutzt", Math.round(weekly.percent)));
        if (used && used.block.active) lines.push(t("Block: %1 Tokens", fmtTokens(used.block.tokens.total)));
        if (limitError) lines.push(limitError);
        return lines.join("\n");
    }

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "utilities-system-monitor"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            Rectangle {
                visible: !!root.fiveHour && !Plasmoid.configuration.compactShowTokens
                Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                Layout.preferredHeight: Layout.preferredWidth
                radius: width / 2
                color: root.statusColor(Math.max(root.fiveHour ? root.fiveHour.percent : 0, root.weekly ? root.weekly.percent : 0))
            }
            PlasmaComponents3.Label {
                readonly property bool showTokens: Plasmoid.configuration.compactShowTokens || !root.fiveHour
                text: {
                    if (!root.usage) return "…";
                    if (showTokens) return root.used && root.used.block.active ? root.fmtTokens(root.used.block.tokens.total) : "0";
                    let t = Math.round(root.fiveHour.percent) + " %";
                    if (root.weekly) t += " · " + Math.round(root.weekly.percent) + " %";
                    return t;
                }
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        readonly property bool compact: Plasmoid.configuration.compactLayout
        readonly property real pad: root.planar ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing

        Rectangle {
            visible: root.planar
            anchors.fill: parent
            z: -1
            radius: Kirigami.Units.cornerRadius * 2
            color: Qt.alpha(Kirigami.Theme.backgroundColor, Plasmoid.configuration.backgroundOpacity / 100)
        }

        Layout.minimumWidth: Kirigami.Units.gridUnit * (compact ? 14 : 18)
        Layout.preferredWidth: Kirigami.Units.gridUnit * (compact ? 16 : 20)
        Layout.preferredHeight: (compact ? cards.implicitHeight : content.implicitHeight) + Kirigami.Units.largeSpacing * 2

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.usage && root.usage.limits && root.usage.limits.plan
                        ? root.t("Claude %1", root.usage.limits.plan.charAt(0).toUpperCase() + root.usage.limits.plan.slice(1))
                        : root.t("Claude")
                }
                PlasmaComponents3.BusyIndicator {
                    visible: root.loading
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh(true)
                    PlasmaComponents3.ToolTip.text: root.t("Jetzt aktualisieren")
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }
        }

        // Compact "device" style: one card per limit, big percentage, thin bar.
        ColumnLayout {
            id: cards
            visible: compact
            anchors.fill: parent
            anchors.margins: pad
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                visible: root.limitError !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.limitError
                textFormat: Text.PlainText
                color: Kirigami.Theme.neutralTextColor
            }

            Repeater {
                model: root.limitItems
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property real pct: modelData.percent
                    Layout.fillWidth: true
                    implicitHeight: cardCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: Kirigami.Units.cornerRadius * 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.07)

                    ColumnLayout {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            Kirigami.Heading {
                                level: 1
                                font.bold: true
                                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.8)
                                text: Math.round(card.pct) + "%"
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                implicitWidth: pill.implicitWidth + Kirigami.Units.largeSpacing * 2
                                implicitHeight: pill.implicitHeight + Kirigami.Units.smallSpacing
                                radius: height / 2
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                                PlasmaComponents3.Label {
                                    id: pill
                                    anchors.centerIn: parent
                                    font.bold: true
                                    textFormat: Text.PlainText
                                    text: root.shortLabel(card.modelData.key, card.modelData.label)
                                }
                            }
                        }

                        StatusBar {
                            Layout.fillWidth: true
                            percent: card.pct
                            fillColor: root.statusColor(card.pct)
                            trackStops: root.statusStops
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                                Layout.preferredHeight: Layout.preferredWidth
                                radius: width / 2
                                color: root.statusColor(card.pct)
                            }
                            PlasmaComponents3.Label {
                                text: root.statusText(card.pct)
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PlasmaComponents3.Label {
                                visible: card.modelData.resets_at !== undefined && card.modelData.resets_at !== null
                                text: root.t("Reset in %1", root.fmtRel(card.modelData.resets_at))
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                            }
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                visible: root.used !== null && root.used.block.active
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                text: root.used ? root.t("Block %1 · heute %2 · Woche %3",
                    root.fmtTokens(root.used.block.tokens.total),
                    root.fmtTokens(root.used.today.total),
                    root.fmtTokens(root.used.week.total)) : ""
            }

            Item { Layout.fillHeight: true }
        }

        ColumnLayout {
            id: content
            visible: !compact
            anchors.fill: parent
            anchors.margins: pad
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading { level: 4; text: root.t("Limits"); opacity: 0.8 }

            PlasmaComponents3.Label {
                visible: root.limitError !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.limitError
                textFormat: Text.PlainText
                color: Kirigami.Theme.neutralTextColor
            }

            Repeater {
                model: root.limitItems
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: root.t(modelData.label); textFormat: Text.PlainText; Layout.fillWidth: true }
                        PlasmaComponents3.Label {
                            text: root.t("%1 % genutzt · %2 % frei", Math.round(modelData.percent), Math.max(0, 100 - Math.round(modelData.percent)))
                        }
                    }
                    StatusBar {
                        Layout.fillWidth: true
                        percent: modelData.percent
                        fillColor: root.statusColor(modelData.percent)
                        trackStops: root.statusStops
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                            Layout.preferredHeight: Layout.preferredWidth
                            radius: width / 2
                            color: root.statusColor(modelData.percent)
                        }
                        PlasmaComponents3.Label {
                            text: root.statusText(modelData.percent)
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: root.fmtReset(modelData.resets_at)
                            visible: text !== ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

            Kirigami.Heading { level: 4; text: root.t("Verbraucht (Claude Code)"); opacity: 0.8 }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: 2
                visible: root.used !== null

                PlasmaComponents3.Label { text: ""; Layout.fillWidth: true }
                PlasmaComponents3.Label { text: root.t("Gesamt"); font: Kirigami.Theme.smallFont; opacity: 0.7; Layout.alignment: Qt.AlignRight }
                PlasmaComponents3.Label { text: root.t("Output"); font: Kirigami.Theme.smallFont; opacity: 0.7; Layout.alignment: Qt.AlignRight }

                PlasmaComponents3.Label {
                    text: root.used && root.used.block.active ? root.t("Aktueller 5h-Block") : root.t("5h-Block (inaktiv)")
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label { text: root.used ? root.fmtTokens(root.used.block.tokens.total) : ""; Layout.alignment: Qt.AlignRight }
                PlasmaComponents3.Label { text: root.used ? root.fmtTokens(root.used.block.tokens.output) : ""; Layout.alignment: Qt.AlignRight }

                PlasmaComponents3.Label { text: root.t("Heute"); Layout.fillWidth: true }
                PlasmaComponents3.Label { text: root.used ? root.fmtTokens(root.used.today.total) : ""; Layout.alignment: Qt.AlignRight }
                PlasmaComponents3.Label { text: root.used ? root.fmtTokens(root.used.today.output) : ""; Layout.alignment: Qt.AlignRight }

                PlasmaComponents3.Label { text: root.t("Diese Woche"); Layout.fillWidth: true }
                PlasmaComponents3.Label { text: root.used ? root.fmtTokens(root.used.week.total) : ""; Layout.alignment: Qt.AlignRight }
                PlasmaComponents3.Label { text: root.used ? root.fmtTokens(root.used.week.output) : ""; Layout.alignment: Qt.AlignRight }
            }

            PlasmaComponents3.Label {
                visible: root.used !== null && Object.keys(root.used.models_today).length > 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: {
                    if (!root.used) return "";
                    const m = root.used.models_today;
                    return root.t("Heute: %1", Object.keys(m).map(k => root.t("%1 %2", k.replace("claude-", ""), root.fmtTokens(m[k]))).join(", "));
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.5
                text: root.t("Gesamt enthält Cache-Reads. Limits gelten für alle Claude-Nutzungen, die Token-Zahlen nur für Claude Code.")
            }

            Item { Layout.fillHeight: true }
        }
    }
}
