import QtQuick

// Language packs. Each set is one language/style: it brings its own status
// comments and (optionally) replacements for all other texts, see below.
// "lang" is a stable id, "locale" drives weekday names etc.
//
// Sets of status comments, one per 10 % step (0-9 % ... 90-99 %) plus one for a
// full limit (11 entries each). An entry is either one string or a list of
// variants; the widget rolls a new variant on every refresh. Used by the widget
// (main.qml) and the settings page (configGeneral.qml). Keep every entry short
// (about 24 characters at most) so it fits next to the reset time on the
// compact cards.
//
// A set may also carry "ui": replacements for the regular (German) interface
// texts, keyed by the German source string, so a set can restyle the whole
// widget and its settings page, not only the comments. Placeholders %1, %2 …
// are filled in the same way as with i18n(). "schemes" optionally renames the
// colour profiles (same order as ColorSchemes.qml).
QtObject {
    readonly property var sets: [
        { name: qsTr("Deutsch · chillig bis dramatisch"), lang: "de", locale: "de_DE",
          comments: [
            qsTr("Alle Zeit der Welt"),         //   0-9 %
            qsTr("Füße hoch!"),                 //  10-19 %
            qsTr("Kaffee in Ruhe trinken"),     //  20-29 %
            qsTr("Faultier-Modus aktiv"),       //  30-39 %
            qsTr("Noch locker flockig"),        //  40-49 %
            qsTr("Bergfest!"),                 //  50-59 %
            qsTr("Erste Schweißperlen"),       //  60-69 %
            qsTr("Der Tank hüstelt"),          //  70-79 %
            qsTr("Finger weg von Opus!"),      //  80-89 %
            qsTr("Mayday, Mayday!"),           //  90-99 %
            qsTr("Game Over – Kaffee holen")   //  100 %
          ] },
        { name: "Jamaica · bomboclaat edition, mon!", lang: "jam", locale: "en_US",
          comments: [
            [ "Wagwan! Everyting irie",   //   0-9 %
              "Bun a spliff, relax",
              "Irie vibes, mi bredda",
              "One love, full chalice",
              "Ganja inna di pipe, yow" ],
            [ "No problem, mon",          //  10-19 %
              "Likkle draw, no stress",
              "Seen, wi deh yah",
              "Cool an deadly, yute" ],
            [ "Easy nuh, bredren",        //  20-29 %
              "Spliff numba two, mon",
              "Chalice a bubble",
              "Reggae inna di speaker" ],
            [ "Likkle bit a vibes",       //  30-39 %
              "Ganja smoke a rise",
              "Wi a skank, mon",
              "Di herb a work, seen?" ],
            [ "Cool runnings",            //  40-49 %
              "Babylon cyaan touch wi",
              "Nuff vibes still",
              "Jah guide di tokens" ],
            [ "Half way, big up!",        //  50-59 %
              "Pull up, selector!",
              "Pussywagon pull up!",
              "Half di herb gone, yow" ],
            [ "Wi a sweat now",           //  60-69 %
              "Rassclaat, it a heat up",
              "Bloodclaat, slow down",
              "Babylon a watch wi" ],
            [ "Di chalice a cough",       //  70-79 %
              "Pussyclaat, herb low!",
              "Bomboclaat, mind it!",
              "Babylon a sniff round" ],
            [ "Hol' off di Opus, mon!",   //  80-89 %
              "Babylon a come, run!",
              "Rassclaat, last spliff",
              "Pussyclaat! Easy deh!" ],
            [ "Wi inna trouble, yow!",    //  90-99 %
              "BOMBOCLAAT! Mayday!",
              "Bun Babylon! Hol' on!",
              "Bloodclaat, wi dun soon" ],
            [ "Bomboclaat, limit reach!", //  100 %
              "Babylon win, rassclaat",
              "Pussyclaat! Herb dun!",
              "Chalice empty. Bun dem!" ]
          ],
          schemes: [
            "Rasta · green → red (fi everybody)",
            "Ice → fiyah · blue → red",
            "Neon · blue → pink (dancehall)",
            "Gold · yellow → red (fi green/blue backdrop)",
            "Ice-cold · jus cool colour (fi red backdrop)",
            "Heavy · strong rasta (fi bright backdrop)",
            "Negril sunset · yellow → purple",
            "Fiyah bun · purple → yellow",
            "Colour-blind safe · blue → orange",
            "Grey · grey → white (fi busy backdrop)"
          ],
          ui: {
            // widget
            "Aktuell": "Right now",
            "Woche": "Di week",
            "5 Stunden": "5 hour",
            "Woche Opus": "Week · bredda Opus",
            "Woche Sonnet": "Week · bredda Sonnet",
            "Woche Apps": "Week · apps",
            "Reset in %1 (%2)": "Fresh herb in %1 (%2)",
            "Reset in %1": "Fresh herb in %1",
            "%1 T %2 h": "%1 day %2 h",
            "%1 h %2 min": "%1 h %2 min",
            "%1 min": "%1 min",
            "%1 Mrd": "%1 Billion",
            "%1 M": "%1 Million",
            "%1 k": "%1 Tousand",
            "Skript-Fehler": "Script mash up, bomboclaat!",
            "Jetzt aktualisieren": "Pull up, selector!",
            "Claude-Verbrauch": "Claude Ganja Meter",
            "Claude %1": "Claude %1 · one love",
            "Claude": "Claude · one love",
            "5 Stunden: %1 % genutzt": "5 hour: %1 % bun",
            "Woche: %1 % genutzt": "Di week: %1 % bun",
            "Block: %1 Tokens": "Dis spliff: %1 token",
            "Block %1 · heute %2 · Woche %3": "Spliff %1 · today %2 · week %3",
            "Limits": "Babylon limits",
            "%1 % genutzt · %2 % frei": "%1 % bun · %2 % lef'",
            "Verbraucht (Claude Code)": "Wah wi smoke (Claude Code)",
            "Gesamt": "Total",
            "Output": "Exhale",
            "Aktueller 5h-Block": "Dis 5h spliff",
            "5h-Block (inaktiv)": "5h spliff (out)",
            "Heute": "Today",
            "Diese Woche": "Dis week",
            "Heute: %1": "Inna di house today: %1",
            "%1 %2": "mi bredda %1 spliffin %2 token",
            "Gesamt enthält Cache-Reads. Limits gelten für alle Claude-Nutzungen, die Token-Zahlen nur für Claude Code.":
                "Total include cache reads, seen? Babylon limits count fi all Claude, di token dem a jus Claude Code.",
            // plain status labels (comments switched off)
            "Freie Fahrt": "Free ride, mon",
            "Aufpassen": "Watch yuhself",
            "Wird knapp": "Getting tight",
            "Fast am Limit": "Almost a limit",
            "Limit erreicht": "Limit reach",
            // backend errors (claude_usage.py)
            "Token-Erneuerung läuft bereits": "Token renew a run already",
            "Ungültige Token-Antwort": "Token reply nuh good",
            "Antwort zu groß": "Reply too big",
            "Unerwartete Antwort": "Strange reply",
            "Kein OAuth-Login in der Credentials-Datei": "No OAuth login inna credentials file",
            "Nur https erlaubt": "Only https, seen?",
            "Kein Claude-Code-Login gefunden": "No Claude Code login, bredren",
            "Login abgelaufen – `claude` im Terminal starten": "Login dead, rassclaat – start `claude` inna terminal",
            "Login abgelaufen – im Terminal `claude` → /login": "Login dead, bomboclaat – `claude` → /login inna terminal",
            // settings page
            "Ansicht:": "Di look:",
            "Kompakte Karten-Ansicht (große Prozentzahl, schmale Balken)": "Likkle card dem (big number, slim bar)",
            "Aktualisieren alle (Minuten):": "Check di herb every (minute):",
            "Balkenfarben:": "Bar colour dem:",
            "Status-Text:": "Chat:",
            "Lustige Sprüche anzeigen (aus = sachliche Statustexte)": "Big up di funny chat (off = boring Babylon text)",
            "Sprache / Language:": "Language:",
            "Automatisch (Systemsprache)": "Auto (system language)",
            "Hintergrund-Deckkraft:": "Backdrop thickness:",
            "Login:": "Login:",
            "Abgelaufenen Claude-Code-Login automatisch erneuern": "Fix dead Claude Code login by itself",
            "Panel:": "Panel:",
            "Tokens im aktuellen 5h-Block statt Limit-Prozent zeigen": "Show token inna dis 5h spliff, nuh percent"
          } },
        { name: "English · chill to dramatic", lang: "en", locale: "en_US",
          comments: [
            [ "Plenty of time",             //   0-9 %
              "Fresh out of the box",
              "Not a care in the world" ],
            [ "Feet up!",                   //  10-19 %
              "Smooth sailing",
              "Cruising along" ],
            [ "Coffee, no rush",            //  20-29 %
              "Easy does it",
              "Nothing to see here" ],
            [ "Sloth mode: on",             //  30-39 %
              "Totally relaxed",
              "Chillin' like a villain" ],
            [ "Plenty left in the tank",    //  40-49 %
              "Still going strong",
              "Almost halftime" ],
            [ "Halfway there!",             //  50-59 %
              "Hump day!",
              "Halftime snack?" ],
            [ "First beads of sweat",       //  60-69 %
              "Getting spicy",
              "Things are heating up" ],
            [ "The tank is coughing",       //  70-79 %
              "Fuel light's flickering",
              "Running on fumes soon" ],
            [ "Hands off Opus!",            //  80-89 %
              "Opus? Not today.",
              "Careful with Opus!" ],
            [ "Mayday, mayday!",            //  90-99 %
              "Red alert!",
              "Brace for impact!" ],
            [ "Game over – grab coffee",    //  100 %
              "Limit hit. Touch grass.",
              "Out of juice. Coffee?" ]
          ],
          schemes: [
            "Traffic light · green → red (universal)",
            "Ice → Fire · blue → red (dark blue)",
            "Neon · blue → magenta (cyberpunk)",
            "Amber · yellow → red (green/blue wallpapers)",
            "Iceberg · cool tones only (red/warm wallpapers)",
            "Bold · strong traffic light (bright wallpapers)",
            "Sunset · yellow → violet",
            "Inferno · violet → yellow (classic heatmap)",
            "Colour-blind safe · blue → orange",
            "Mono · grey → white (busy wallpapers)"
          ],
          ui: {
            // widget
            "Aktuell": "Current",
            "Woche": "Weekly",
            "5 Stunden": "5 hours",
            "Woche Opus": "Weekly Opus",
            "Woche Sonnet": "Weekly Sonnet",
            "Woche Apps": "Weekly apps",
            "Reset in %1 (%2)": "Resets in %1 (%2)",
            "Reset in %1": "Resets in %1",
            "%1 T %2 h": "%1 d %2 h",
            "%1 h %2 min": "%1 h %2 min",
            "%1 min": "%1 min",
            "%1 Mrd": "%1 B",
            "%1 M": "%1 M",
            "%1 k": "%1 k",
            "Skript-Fehler": "Script error",
            "Jetzt aktualisieren": "Refresh now",
            "Claude-Verbrauch": "Claude Usage",
            "Claude %1": "Claude %1",
            "Claude": "Claude",
            "5 Stunden: %1 % genutzt": "5 hours: %1 % used",
            "Woche: %1 % genutzt": "Week: %1 % used",
            "Block: %1 Tokens": "Block: %1 tokens",
            "Block %1 · heute %2 · Woche %3": "Block %1 · today %2 · week %3",
            "Limits": "Limits",
            "%1 % genutzt · %2 % frei": "%1 % used · %2 % left",
            "Verbraucht (Claude Code)": "Used (Claude Code)",
            "Gesamt": "Total",
            "Output": "Output",
            "Aktueller 5h-Block": "Current 5h block",
            "5h-Block (inaktiv)": "5h block (inactive)",
            "Heute": "Today",
            "Diese Woche": "This week",
            "Heute: %1": "Today: %1",
            "%1 %2": "%1 %2",
            "Gesamt enthält Cache-Reads. Limits gelten für alle Claude-Nutzungen, die Token-Zahlen nur für Claude Code.":
                "Total includes cache reads. Limits apply to all Claude usage, the token counts cover Claude Code only.",
            // plain status labels (comments switched off)
            "Freie Fahrt": "Plenty of room",
            "Aufpassen": "Keep an eye on it",
            "Wird knapp": "Getting tight",
            "Fast am Limit": "Almost at the limit",
            "Limit erreicht": "Limit reached",
            // backend errors (claude_usage.py)
            "Kein Claude-Code-Login gefunden": "No Claude Code login found",
            "Login abgelaufen – `claude` im Terminal starten": "Login expired – start `claude` in a terminal",
            "Login abgelaufen – im Terminal `claude` → /login": "Login expired – run `claude` → /login in a terminal",
            "Token-Erneuerung läuft bereits": "Token renewal already running",
            "Ungültige Token-Antwort": "Invalid token response",
            "Antwort zu groß": "Response too large",
            "Unerwartete Antwort": "Unexpected response",
            "Kein OAuth-Login in der Credentials-Datei": "No OAuth login in the credentials file",
            "Nur https erlaubt": "Only https is allowed",
            // settings page
            "Ansicht:": "View:",
            "Kompakte Karten-Ansicht (große Prozentzahl, schmale Balken)": "Compact card view (big percentage, slim bars)",
            "Aktualisieren alle (Minuten):": "Refresh every (minutes):",
            "Balkenfarben:": "Bar colours:",
            "Status-Text:": "Status text:",
            "Lustige Sprüche anzeigen (aus = sachliche Statustexte)": "Show funny comments (off = plain status texts)",
            "Sprache / Language:": "Language:",
            "Automatisch (Systemsprache)": "Automatic (system language)",
            "Hintergrund-Deckkraft:": "Background opacity:",
            "Login:": "Login:",
            "Abgelaufenen Claude-Code-Login automatisch erneuern": "Renew an expired Claude Code login automatically",
            "Panel:": "Panel:",
            "Tokens im aktuellen 5h-Block statt Limit-Prozent zeigen": "Show tokens of the current 5h block instead of the limit percentage"
          } }
    ]

    function clampIndex(i) { return Math.max(0, Math.min(sets.length - 1, i | 0)); }

    function comments(i) { return sets[clampIndex(i)].comments; }

    function ui(i) { return sets[clampIndex(i)].ui || {}; }

    function indexOfLang(lang) {
        for (let k = 0; k < sets.length; ++k) if (sets[k].lang === lang) return k;
        return 0;
    }

    // Stored value -> set index. A negative value means "automatic": German for a
    // German system locale, English for everything else.
    function resolve(i) {
        if (i >= 0) return clampIndex(i);
        return indexOfLang(Qt.locale().name.indexOf("de") === 0 ? "de" : "en");
    }

    function localeName(i) { return sets[clampIndex(i)].locale || "en_US"; }

    function schemeNames(i, fallback) { return sets[clampIndex(i)].schemes || fallback; }

    // One comment for a step; "roll" picks the variant when the entry has several.
    function pick(entry, roll) { return Array.isArray(entry) ? entry[roll % entry.length] : entry; }

    // i18n() with the set's replacement text, if it has one.
    function text(i, source, args) {
        const s = ui(i)[source];
        if (s === undefined) return i18n(source, ...args);
        // function replacement: "$&" and friends inside an argument stay literal
        return args.reduce((acc, a, n) => acc.replace("%" + (n + 1), () => String(a)), s);
    }
}
