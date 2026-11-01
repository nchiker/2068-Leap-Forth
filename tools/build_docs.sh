#!/usr/bin/env bash
# Render the user-facing Markdown docs to PDF, and the manual to Word, into build/docs/.
#
#   PDF path:  pandoc (GitHub-flavored Markdown -> standalone HTML with
#              the images embedded) -> WeasyPrint (HTML+CSS -> PDF),
#              styled by tools/pdf/style.css. No LaTeX needed. The manual's
#              eight parts (docs/manual/) are joined into one document first,
#              their links to each other made links within it.
#   DOCX path: tools/build_manual_docx.py (make manual), after 2068-Leap-C's.
#
# Requires: pandoc, and Python 3 with the `weasyprint` and `python-docx`
# packages (pip install -r tools/requirements-docs.txt). WeasyPrint needs
# the system Pango/Cairo libraries; on Debian/Ubuntu:
#   apt-get install pandoc fonts-dejavu-core libpango-1.0-0 libpangoft2-1.0-0
# on macOS with Homebrew:  brew install pandoc pango
#
# Usage:  tools/build_docs.sh            # writes build/docs/*.pdf, *.docx
#
# To add another document to the PDF set, append a "src|out|title|resource path" line
# to the DOCS list below.
set -euo pipefail

cd "$(dirname "$0")/.."
out=build/docs
mkdir -p "$out"

# the manual as one Markdown file: docs/manual/0N_part.md#anchor -> #anchor, a part alone -> the top
manual="$out/leap_forth_manual.md"
for part in docs/manual/0[1-8]_*.md; do
  sed -E 's/\]\(0[1-8]_[a-z_]+\.md#/](#/g; s/\]\(0[1-8]_[a-z_]+\.md\)/](#)/g' "$part"
  printf '\n\n'
done > "$manual"

# src markdown | output basename | <title> for the PDF metadata | resource path (images)
DOCS=(
  "$manual|leap_forth_manual|Leap-Forth User's Manual|docs/manual"
  "README.md|README|2068-Forth README|."
)

for entry in "${DOCS[@]}"; do
  IFS='|' read -r src base title res <<<"$entry"
  html="$out/$base.html"
  pdf="$out/$base.pdf"
  echo "== $src -> $pdf"
  # --embed-resources inlines the PNGs so the HTML (and PDF) is
  # self-contained; --resource-path makes the docs' relative image
  # links resolve. pagetitle sets <title> without adding a title block
  # (each document already starts with its own H1).
  # The README's Actions status badge is a remote image; drop it so the
  # render never touches the network.
  grep -v 'actions/workflows/build.yml/badge.svg' "$src" | \
  pandoc -f gfm -t html5 --standalone --embed-resources \
    --resource-path="$res" \
    --css tools/pdf/style.css \
    --metadata pagetitle="$title" \
    -o "$html"
  python3 -m weasyprint --quiet "$html" "$pdf"
  rm -f "$html"
done

rm -f "$manual"
echo "== docs/manual -> $out/leap_forth_manual.docx"
python3 tools/build_manual_docx.py "$out/leap_forth_manual.docx"

ls -la "$out"
