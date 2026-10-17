#!/usr/bin/env python3
"""Checks that the language packs in CommentSets.qml are complete and well-formed.

Run:  python3 -I tests/test_translations.py

It reads the QML sources as text (no Qt needed): every German source string the
interface passes to t() must have a replacement in each non-German pack, every
pack must have 11 comment steps, and comments must be short enough for the cards.
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "package" / "contents" / "ui"
BACKEND = ROOT / "package" / "contents" / "code" / "claude_usage.py"
SETS_QML = (UI / "CommentSets.qml").read_text(encoding="utf-8")

MAX_COMMENT = 24
STR = r'"((?:[^"\\]|\\.)*)"'

# Labels that come from the backend and are translated through t(modelData.label)
BACKEND_LABELS = ["5 Stunden", "Woche", "Woche Opus", "Woche Sonnet", "Woche Apps"]
# Texts shown by the widget that are not passed to t() with a literal
PLAIN_STATUS = ["Freie Fahrt", "Aufpassen", "Wird knapp", "Fast am Limit", "Limit erreicht"]
# i18n() texts of the settings page that are built dynamically
EXTRA = ["Sprache / Language:", "Automatisch (Systemsprache)"]


def unescape(s):
    return json.loads('"%s"' % s)


def split_sets():
    """-> list of dicts {lang, text} for every set in CommentSets.qml."""
    marks = list(re.finditer(r'^        \{ name:', SETS_QML, flags=re.M))
    out = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else SETS_QML.index("    ]\n\n    function clampIndex")
        text = SETS_QML[m.start():end]
        lang = re.search(r'lang:\s*"(\w+)"', text)
        out.append({"lang": lang.group(1) if lang else "?", "text": text})
    return out


def ui_keys(block):
    i = block.find("ui: {")
    if i < 0:
        return set()
    return {unescape(k) for k in re.findall(r'^\s*' + STR + r'\s*:', block[i:], flags=re.M)}


def comment_groups(block):
    """The 11 entries of the comments array, each as a list of strings."""
    start = block.index("comments: [")
    end = block.index("\n          ]", start)         # the array closes at 10 spaces of indentation
    region = block[start + len("comments: ["):end]
    region = re.sub(r'//[^\n]*', '', region)             # drop trailing "// 0-9 %"
    groups, depth, cur, in_str, esc = [], 0, "", False, False
    for ch in region:
        if in_str:                                   # commas inside "..." do not split
            cur += ch
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        if ch == "[":
            depth += 1
        if depth > 0 or ch not in ",\n":
            cur += ch
        if ch == "]":
            depth -= 1
        if depth == 0 and ch == ",":
            groups.append(cur); cur = ""
    if cur.strip():
        groups.append(cur)
    out = []
    for g in groups:
        g = g.strip()
        if not g:
            continue
        strings = [unescape(x) for x in re.findall(STR, g)]
        if strings:
            out.append(strings)
    return out


def source_strings():
    """Every German source string the interface can show."""
    keys = set(BACKEND_LABELS + PLAIN_STATUS + EXTRA)
    for name in ("main.qml", "configGeneral.qml"):
        text = (UI / name).read_text(encoding="utf-8")
        for m in re.finditer(r'\bt\(\s*' + STR, text):
            keys.add(unescape(m.group(1)))
        # statusText() literals and i18n() fallbacks inside main.qml
        for m in re.finditer(r'\bi18n\(\s*' + STR, text):
            keys.add(unescape(m.group(1)))
    backend = BACKEND.read_text(encoding="utf-8")
    for m in re.finditer(r'^MSG_\w+ = ' + STR, backend, flags=re.M):
        keys.add(unescape(m.group(1)))
    for m in re.finditer(r'(?:raise (?:ValueError|RuntimeError)|clean_error)\(\s*' + STR + r'\s*\)', backend):
        s = unescape(m.group(1))
        if "%" not in s:
            keys.add(s)
    return keys


class TestLanguagePacks(unittest.TestCase):
    sets = split_sets()

    def test_there_are_german_jamaican_and_english(self):
        self.assertEqual([s["lang"] for s in self.sets], ["de", "jam", "en"])

    def test_every_set_has_a_locale_and_a_name(self):
        for s in self.sets:
            self.assertRegex(s["text"], r'locale:\s*"[a-z]{2}_[A-Z]{2}"', s["lang"])
            self.assertRegex(s["text"], r'name:\s*(qsTr\()?"[^"]+"', s["lang"])

    def test_eleven_comment_steps_each(self):
        for s in self.sets:
            self.assertEqual(len(comment_groups(s["text"])), 11, s["lang"])

    def test_comments_fit_on_the_cards(self):
        for s in self.sets:
            for step, group in enumerate(comment_groups(s["text"])):
                self.assertTrue(group, (s["lang"], step))
                for c in group:
                    self.assertLessEqual(len(c), MAX_COMMENT, "%s step %d: %r" % (s["lang"], step, c))
                    self.assertEqual(c, c.strip())

    def test_variants_are_distinct_within_a_step(self):
        for s in self.sets:
            for step, group in enumerate(comment_groups(s["text"])):
                self.assertEqual(len(group), len(set(group)), (s["lang"], step))

    def test_translations_are_complete(self):
        needed = source_strings()
        self.assertGreater(len(needed), 40)               # sanity: the scan found the interface
        for s in self.sets:
            if s["lang"] == "de":
                continue
            missing = sorted(needed - ui_keys(s["text"]))
            self.assertEqual(missing, [], "%s lacks translations for: %s" % (s["lang"], missing))

    def test_placeholders_are_preserved(self):
        for s in self.sets:
            block = s["text"]
            i = block.find("ui: {")
            if i < 0:
                continue
            for m in re.finditer(r'^\s*' + STR + r'\s*:\s*\n?\s*' + STR, block[i:], flags=re.M):
                src, dst = unescape(m.group(1)), unescape(m.group(2))
                want = sorted(re.findall(r'%\d', src))
                got = sorted(re.findall(r'%\d', dst))
                self.assertEqual(want, got, "%s: %r -> %r" % (s["lang"], src, dst))

    def test_scheme_names_cover_all_ten_profiles(self):
        for s in self.sets:
            if "schemes:" not in s["text"]:
                continue
            region = s["text"][s["text"].index("schemes:"):s["text"].index("ui: {")]
            self.assertEqual(len(re.findall(STR, region)), 10, s["lang"])

    def test_english_has_no_german_leftovers_in_comments(self):
        en = next(s for s in self.sets if s["lang"] == "en")
        text = " ".join(c for g in comment_groups(en["text"]) for c in g)
        self.assertNotRegex(text, r'[äöüßÄÖÜ]')


if __name__ == "__main__":
    unittest.main(verbosity=2)
