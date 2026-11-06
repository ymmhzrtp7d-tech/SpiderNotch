"""Tests for scripts/release_tools.py and the bundled data files (stdlib unittest)."""
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import release_tools  # noqa: E402


class ReleaseToolsTests(unittest.TestCase):
    def test_version_file_is_semver(self):
        version = (ROOT / "VERSION").read_text().strip()
        self.assertRegex(version, release_tools.VERSION_RE)

    def test_changelog_has_current_version(self):
        version = (ROOT / "VERSION").read_text().strip()
        self.assertTrue(release_tools.changelog_section(version),
                        f"CHANGELOG.md needs a '## {version}' section")

    def test_markdown_to_html(self):
        out = release_tools.markdown_to_html("- **Bold** item\n  continued\n- `code` & more\n\nA paragraph.")
        self.assertIn("<li><b>Bold</b> item continued</li>", out)
        self.assertIn("<code>code</code> &amp; more", out)
        self.assertIn("<p>A paragraph.</p>", out)

    def test_appcast_is_valid_xml(self):
        version = (ROOT / "VERSION").read_text().strip()
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "appcast.xml"
            subprocess.run([sys.executable, str(ROOT / "scripts/release_tools.py"), "appcast",
                            "--version", version, "--build", "202601010000",
                            "--url", "https://example.invalid/a.zip", "--length", "123",
                            "--signature", "abc==", "--link", "https://example.invalid/",
                            "--out", str(out)], check=True, capture_output=True)
            root = ET.parse(out).getroot()
            ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
            item = root.find("channel/item")
            self.assertEqual(item.find("sparkle:shortVersionString", ns).text, version)
            enclosure = item.find("enclosure")
            self.assertEqual(enclosure.get("length"), "123")
            self.assertEqual(enclosure.get("{%s}edSignature" % ns["sparkle"]), "abc==")


class BundledDataTests(unittest.TestCase):
    def test_character_library(self):
        folder = ROOT / "SpiderNotch/Resources/Characters"
        library = json.loads((folder / "Library.json").read_text())
        categories = {c["id"] for c in library["categories"]}
        ids = set()
        for character in library["characters"]:
            self.assertNotIn(character["id"], ids, "duplicate character id")
            ids.add(character["id"])
            self.assertIn(character["category"], categories, character["id"])
            self.assertTrue((folder / character["image"]).is_file(), f"missing {character['image']}")
            self.assertTrue(character.get("faces"), character["id"])
        self.assertIn("spider", ids)

    def test_no_secrets_committed(self):
        pattern = re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----")
        for path in ROOT.rglob("*"):
            if any(part in {".git", "build", "dist", "vendor"} for part in path.parts) or not path.is_file():
                continue
            if path.suffix.lower() in {".png", ".icns", ".zip", ".dmg"}:
                continue
            text = path.read_text(errors="ignore")
            self.assertIsNone(pattern.search(text), f"private key in {path}")
        for bad in ("*.p12", "*.cer", "*.mobileprovision"):
            found = [p for p in ROOT.rglob(bad) if not {"build", "dist", "vendor"} & set(p.parts)]
            self.assertEqual(found, [], f"{bad} files must not be in the repository")


if __name__ == "__main__":
    unittest.main()
