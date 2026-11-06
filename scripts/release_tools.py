#!/usr/bin/env python3
"""Small release helpers for SpiderNotch (Python 3 standard library only).

  release_tools.py notes VERSION            -> prints that version's CHANGELOG.md section (Markdown)
  release_tools.py check-version VERSION    -> fails unless VERSION is MAJOR.MINOR.PATCH[-pre]
                                               and CHANGELOG.md has a section for it
  release_tools.py appcast --version V --build B --url URL --length N --signature SIG
                           --min-macos 14.0 --out appcast.xml
                                            -> writes the Sparkle update feed for one release
"""
import argparse
import datetime
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$")


def changelog_section(version: str) -> str:
    """Returns the body of '## <version> ...' up to the next '## '."""
    text = CHANGELOG.read_text(encoding="utf-8")
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^##\s+" + re.escape(version) + r"(\s|$)", line):
            start = i + 1
            break
    if start is None:
        return ""
    body = []
    for line in lines[start:]:
        if line.startswith("## "):
            break
        body.append(line)
    return "\n".join(body).strip()


def markdown_to_html(md: str) -> str:
    """Just enough Markdown for release notes: bullets, paragraphs, **bold**, `code`, links."""
    def inline(s: str) -> str:
        s = html.escape(s, quote=False)
        s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
        s = re.sub(r"`(.+?)`", r"<code>\1</code>", s)
        s = re.sub(r"\[(.+?)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', s)
        return s

    out, para, items = [], [], []

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join("<li>" + inline(i) + "</li>" for i in items) + "</ul>")
            items.clear()

    for raw in md.splitlines():
        line = raw.rstrip()
        if not line.strip():
            flush()
        elif re.match(r"^\s*[-*]\s+", line):
            if para:
                flush()
            items.append(re.sub(r"^\s*[-*]\s+", "", line))
        elif items and raw.startswith("  "):
            items[-1] += " " + line.strip()
        elif line.startswith("#"):
            flush()
            out.append("<h3>" + inline(line.lstrip("#").strip()) + "</h3>")
        else:
            para.append(line.strip())
    flush()
    return "\n".join(out)


def cmd_notes(args):
    notes = changelog_section(args.version)
    if not notes:
        sys.exit(f"CHANGELOG.md has no '## {args.version}' section.")
    print(notes)


def cmd_check_version(args):
    if not VERSION_RE.match(args.version):
        sys.exit(f"'{args.version}' isn't a version like 1.2.3 or 1.3.0-beta.1.")
    if not changelog_section(args.version):
        sys.exit(f"Add a '## {args.version} (date)' section to the top of CHANGELOG.md first.")
    print(f"Version {args.version} looks good.")


def cmd_appcast(args):
    notes_html = markdown_to_html(changelog_section(args.version) or "Bug fixes and improvements.")
    pub = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    channel = ""
    if "-" in args.version:  # pre-releases go to the beta channel only
        channel = "\n      <sparkle:channel>beta</sparkle:channel>"
    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>SpiderNotch</title>
    <link>{html.escape(args.link)}</link>
    <description>SpiderNotch updates</description>
    <language>en</language>
    <item>
      <title>Version {html.escape(args.version)}</title>
      <pubDate>{pub}</pubDate>
      <sparkle:version>{html.escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(args.min_macos)}</sparkle:minimumSystemVersion>{channel}
      <sparkle:fullReleaseNotesLink>{html.escape(args.link)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
{notes_html}
      ]]></description>
      <enclosure url="{html.escape(args.url)}" length="{int(args.length)}" type="application/octet-stream" sparkle:edSignature="{html.escape(args.signature)}" />
    </item>
  </channel>
</rss>
"""
    pathlib.Path(args.out).write_text(xml, encoding="utf-8")
    print(f"Wrote {args.out}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("notes"); p.add_argument("version"); p.set_defaults(func=cmd_notes)
    p = sub.add_parser("check-version"); p.add_argument("version"); p.set_defaults(func=cmd_check_version)
    p = sub.add_parser("appcast")
    for name in ("--version", "--build", "--url", "--length", "--signature", "--out", "--link"):
        p.add_argument(name, required=True)
    p.add_argument("--min-macos", default="14.0")
    p.set_defaults(func=cmd_appcast)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
