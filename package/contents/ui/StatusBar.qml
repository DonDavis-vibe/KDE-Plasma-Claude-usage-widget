import QtQuick
import org.kde.kirigami as Kirigami

// Usage bar: the track shows the whole scale (faint green -> red) so you can see
// where the limit is, the fill is one solid colour for the current state, so the
// state reads at a glance no matter how long the bar is.
Item {
    id: bar

    property real percent: 0
    property color fillColor: "#0ca30c"
    property var trackStops: []   // [{ pos: 0..1, color: "#rrggbb" }, ...]

    implicitHeight: Kirigami.Units.smallSpacing * 2.5

    function stopColor(i) { return i < trackStops.length ? trackStops[i].color : "gray"; }
    function stopPos(i) { return i < trackStops.length ? trackStops[i].pos : i / 4; }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        opacity: 0.28
        // five fixed stops, fed from trackStops (see statusStops in main.qml)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.00; color: bar.stopColor(0) }
            GradientStop { position: bar.stopPos(1); color: bar.stopColor(1) }
            GradientStop { position: bar.stopPos(2); color: bar.stopColor(2) }
            GradientStop { position: bar.stopPos(3); color: bar.stopColor(3) }
            GradientStop { position: 1.00; color: bar.stopColor(4) }
        }
    }

    Rectangle {
        visible: bar.percent > 0
        width: Math.max(height, bar.width * Math.min(100, bar.percent) / 100)
        height: parent.height
        radius: height / 2
        color: bar.fillColor
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }
    }
}
