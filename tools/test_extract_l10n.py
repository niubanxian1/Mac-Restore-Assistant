import tempfile, unittest
from pathlib import Path
import extract_l10n

class ExtractorTests(unittest.TestCase):
    def scan(self, body):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"x.swift"; p.write_text(body, encoding="utf-8")
            return extract_l10n.strip_and_scan_calls(p)

    def test_literal_duplicate_and_multiline(self):
        calls, unresolved = self.scan('Text(L10n.t("模型校准"))\nText(L10n.t("模型校准"))\nlet s = """L10n.t("nope")"""')
        self.assertEqual([c["key"] for c in calls], ["模型校准", "模型校准"])
        self.assertEqual(unresolved, [])

    def test_dynamic_is_unresolved(self):
        calls, unresolved = self.scan('Text(L10n.t("候选端口：\\(candidate.label)"))')
        self.assertEqual(calls, [])
        self.assertEqual(len(unresolved), 1)

    def test_placeholder_parser(self):
        self.assertEqual(extract_l10n.placeholders("候选端口：\\(candidate.label) / \\(x)"), ["candidate.label", "x"])

    def test_locale_parser_has_real_key(self):
        locales = extract_l10n.parse_locales()
        self.assertIn("模型校准", locales["en"])
        self.assertIn("模型校准", locales["zh-Hant"])

if __name__ == "__main__":
    unittest.main()
