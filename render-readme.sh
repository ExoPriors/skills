#!/bin/sh
# Rewrite the skills table in README.md (between the skills:begin / skills:end
# markers) from every skills/*/SKILL.md frontmatter: name and description.
# The core `scry` skill leads; specializations follow alphabetically.
set -e
cd "$(dirname "$0")"
tmp=$(mktemp)
{
  echo '| Skill | Use when |'
  echo '|-------|----------|'
  for f in skills/scry/SKILL.md $(ls skills/*/SKILL.md | grep -v '^skills/scry/SKILL.md$' | sort); do
    awk '
      NR == 1 && $0 != "---" { exit }
      NR > 1 && $0 == "---" { exit }
      /^name:/ { name = $2; next }
      /^description:/ { sub(/^description:[ ]*>?-?[ ]*/, ""); d = $0; indesc = 1; next }
      indesc && /^[A-Za-z_-]+:/ { indesc = 0 }
      indesc { gsub(/^[ ]+/, ""); d = d (d == "" ? "" : " ") $0 }
      END { gsub(/\|/, "\\|", d); printf "| **%s** | %s |\n", name, d }
    ' "$f"
  done
} > "$tmp"
awk -v t="$tmp" '
  /<!-- skills:begin -->/ { print; while ((getline l < t) > 0) print l; skip = 1; next }
  /<!-- skills:end -->/ { skip = 0 }
  !skip { print }
' README.md > README.md.new
mv README.md.new README.md
rm -f "$tmp"
