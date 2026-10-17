import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    readonly property var palettes: ColorSchemes {}
    readonly property var commentSets: CommentSets {}

    property alias cfg_refreshMinutes: refreshMinutes.value
    property alias cfg_allowTokenRefresh: allowTokenRefresh.checked
    property alias cfg_compactShowTokens: compactShowTokens.checked
    property alias cfg_compactLayout: compactLayout.checked
    property alias cfg_colorScheme: colorScheme.currentIndex
    property int cfg_colorSchemeDefault: 1
    property alias cfg_funnyComments: funnyComments.checked
    property int cfg_commentSet
    property int cfg_commentSetDefault: -1
    property bool cfg_funnyCommentsDefault: true
    property int cfg_backgroundOpacity
    property int cfg_backgroundOpacityDefault: 55

    // Plasma 6 sets these on every config page; declare them to avoid warnings.
    property int cfg_refreshMinutesDefault: 1
    property bool cfg_allowTokenRefreshDefault: true
    property bool cfg_compactShowTokensDefault: false
    property bool cfg_compactLayoutDefault: false

    // Follows the language picked below, so the page changes as soon as it is selected.
    readonly property int textSet: commentSets.resolve(cfg_commentSet)
    function t(source) {
        return commentSets.text(textSet, source, Array.prototype.slice.call(arguments, 1));
    }

    Kirigami.FormLayout {
        ColumnLayout {
            Kirigami.FormData.label: t("Sprache / Language:")
            QQC2.ComboBox {
                id: commentSet
                Layout.fillWidth: true
                // fixed model, only the names follow the language (a new model would reset the selection)
                readonly property var names: [t("Automatisch (Systemsprache)")].concat(commentSets.sets.map(x => x.name))
                model: commentSets.sets.length + 1
                currentIndex: cfg_commentSet + 1
                displayText: names[currentIndex] || ""
                onActivated: cfg_commentSet = currentIndex - 1
                delegate: QQC2.ItemDelegate {
                    required property int index
                    width: commentSet.width
                    text: commentSet.names[index]
                    highlighted: commentSet.highlightedIndex === index
                }
            }
        }
        QQC2.CheckBox {
            id: compactLayout
            Kirigami.FormData.label: t("Ansicht:")
            text: t("Kompakte Karten-Ansicht (große Prozentzahl, schmale Balken)")
        }
        QQC2.SpinBox {
            id: refreshMinutes
            Kirigami.FormData.label: t("Aktualisieren alle (Minuten):")
            from: 1
            to: 60
        }
        ColumnLayout {
            Kirigami.FormData.label: t("Balkenfarben:")
            spacing: Kirigami.Units.smallSpacing
            QQC2.ComboBox {
                id: colorScheme
                Layout.fillWidth: true
                // fixed model, only the names follow the set (a new model would reset the selection)
                readonly property var names: commentSets.schemeNames(textSet, palettes.schemes.map(s => s.name))
                model: palettes.schemes.length
                displayText: names[currentIndex] || ""
                delegate: QQC2.ItemDelegate {
                    required property int index
                    width: colorScheme.width
                    text: colorScheme.names[index]
                    highlighted: colorScheme.highlightedIndex === index
                }
            }
            // preview of the selected profile: the full scale, 0 % -> 100 %
            Rectangle {
                id: preview
                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.gridUnit * 0.7
                radius: height / 2
                readonly property var st: palettes.stops(colorScheme.currentIndex)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: preview.st[0].pos; color: preview.st[0].color }
                    GradientStop { position: preview.st[1].pos; color: preview.st[1].color }
                    GradientStop { position: preview.st[2].pos; color: preview.st[2].color }
                    GradientStop { position: preview.st[3].pos; color: preview.st[3].color }
                    GradientStop { position: preview.st[4].pos; color: preview.st[4].color }
                }
            }
        }
        QQC2.CheckBox {
            id: funnyComments
            Kirigami.FormData.label: t("Status-Text:")
            text: t("Lustige Sprüche anzeigen (aus = sachliche Statustexte)")
        }
        RowLayout {
            Kirigami.FormData.label: t("Hintergrund-Deckkraft:")
            QQC2.Slider {
                id: opacitySlider
                from: 0
                to: 100
                stepSize: 5
                snapMode: QQC2.Slider.SnapAlways
                value: cfg_backgroundOpacity
                onMoved: cfg_backgroundOpacity = Math.round(value)
            }
            QQC2.Label {
                text: cfg_backgroundOpacity + " %"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
            }
        }
        QQC2.CheckBox {
            id: allowTokenRefresh
            Kirigami.FormData.label: t("Login:")
            text: t("Abgelaufenen Claude-Code-Login automatisch erneuern")
        }
        QQC2.CheckBox {
            id: compactShowTokens
            Kirigami.FormData.label: t("Panel:")
            text: t("Tokens im aktuellen 5h-Block statt Limit-Prozent zeigen")
        }
    }
}
