import QtQuick

// Colour profiles for the usage bars. Every profile has five colours at the same
// positions (the first is held until 40 % while there is plenty of room). Used by
// the widget (main.qml) and the settings page (configGeneral.qml).
QtObject {
    readonly property var positions: [0.00, 0.40, 0.65, 0.85, 1.00]

    readonly property var schemes: [
        { name: qsTr("Ampel · Grün → Rot (universell)"),
          colors: ["#0ca30c", "#0ca30c", "#fab219", "#ec835a", "#d03b3b"] },
        { name: qsTr("Eis → Feuer · Blau → Rot (dunkelblau)"),
          colors: ["#3aa0ff", "#2ec4d6", "#ffc857", "#ff8a4c", "#ff4d5e"] },
        { name: qsTr("Neon · Blau → Magenta (Cyberpunk)"),
          colors: ["#38bdf8", "#6c8cff", "#b06cff", "#ff5fb0", "#ff4d6d"] },
        { name: qsTr("Bernstein · Gelb → Rot (grüne/blaue Hintergründe)"),
          colors: ["#ffe08a", "#ffc65c", "#ff9f43", "#ff6b3d", "#ff3b3b"] },
        { name: qsTr("Eisberg · nur kühle Töne (rote/warme Hintergründe)"),
          colors: ["#a5f3fc", "#67e8f9", "#38bdf8", "#6e8bff", "#8b7bff"] },
        { name: qsTr("Kräftig · satte Ampel (helle Hintergründe)"),
          colors: ["#15803d", "#4d8f12", "#b45309", "#c2410c", "#b91c1c"] },
        { name: qsTr("Sonnenuntergang · Gelb → Violett"),
          colors: ["#ffd166", "#ff9e6d", "#ff6b9d", "#c44dff", "#8b5cf6"] },
        { name: qsTr("Inferno · Violett → Gelb (Heatmap-Klassiker)"),
          colors: ["#7b6cf0", "#c0457f", "#f0553c", "#fb923c", "#fde047"] },
        { name: qsTr("Farbenblind-sicher · Blau → Orange"),
          colors: ["#2b8cd9", "#56b4e9", "#f0e442", "#e69f00", "#d55e00"] },
        { name: qsTr("Mono · Grau → Weiß (bunte/unruhige Hintergründe)"),
          colors: ["#7b8aa0", "#9aa8bc", "#c3cedd", "#e6edf6", "#ffffff"] }
    ]

    function clampIndex(i) { return Math.max(0, Math.min(schemes.length - 1, i | 0)); }

    function stops(i) {
        const c = schemes[clampIndex(i)].colors;
        return positions.map((p, k) => ({ pos: p, color: c[k] }));
    }

    // Colour for a usage percentage, blended linearly between the stops.
    function colorAt(i, pct) {
        const s = stops(i);
        const p = Math.max(0, Math.min(100, pct)) / 100;
        for (let k = 1; k < s.length; ++k) {
            if (p <= s[k].pos) {
                const t = (p - s[k - 1].pos) / (s[k].pos - s[k - 1].pos);
                const a = Qt.color(s[k - 1].color), b = Qt.color(s[k].color);
                return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
            }
        }
        return Qt.color(s[s.length - 1].color);
    }
}
