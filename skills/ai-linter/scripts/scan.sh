#!/usr/bin/env bash
# First-pass detector for a subset of smells.md:
#   process-aside, changelog-sentence, deletion-residue, rewrite-narration,
#   ghost-text (orphan "as mentioned above"), context carry-over,
#   throat-clearing, stock-diction.
# Does not cover correction-aside, most ghost-text, or pass 3.
# Prints candidate lines. Does not rewrite. Hits are hints.
# Exit 0 after a completed scan (hits or not). Exit 2 for usage errors.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  echo "usage: $0 <file-or-dir> [file-or-dir...]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage

files=()
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  # Intentional "before" text in this skill. History files are out of scope.
  case "$f" in
    "$SKILL_DIR/references/examples.md"|"$SKILL_DIR/scripts/scan.sh") continue ;;
    */CHANGELOG|*/CHANGELOG.md|*/CHANGELOG.*|*/ADR-*|*/adr-*) continue ;;
  esac
  case "$base" in
    CHANGELOG|CHANGELOG.md|CHANGELOG.*) continue ;;
  esac
  files+=("$f")
done < <(find "$@" -type f \
  ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' ! -name '*.gif' \
  ! -name '*.webp' ! -name '*.pdf' ! -name '*.zip' ! -name '*.woff*' \
  ! -path '*/.git/*' ! -path '*/node_modules/*' \
  -print0)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "no files to scan" >&2
  exit 2
fi

# name|regex
patterns=(
  'process-aside|(there is no |\(previously |\(formerly |\(was |\(now |\(updated\)|\(revised\)|\(new\))'
  'changelog-sentence|[Pp]reviously .{0,80} now |[Ww]e used to |[Tt]his used to |[Nn]o longer includes |[Rr]eplaced .+ with '
  'deletion-residue|[Ww]as removed|[Ww]e (dropped|removed|deleted) |[Dd]o not use the previous |[Cc]onsidered and rejected'
  'rewrite-narration|[Ii]('\''ve| have) (updated|revised|changed|rewritten)|[Aa]s requested|[Pp]er your feedback|[Tt]his revision'
  'ghost-text|[Aa]s mentioned above'
  'carry-over|[Yy]our earlier (point|question|comment)|[Aa]s discussed'
  'throat-clearing|[Ii]t'\''s important to note|[Ll]et'\''s dive|[Ww]hen it comes to |[Ii]n this document, we will|[Ii]n conclusion'
  'stock-diction|\bdelve\b|\btapestry\b|\bembark\b|\butilize\b|\bcutting-edge\b|\bunlock [a-z]+ potential\b'
)

hits=0
for entry in "${patterns[@]}"; do
  name="${entry%%|*}"
  regex="${entry#*|}"
  while IFS= read -r line; do
    printf '%s  %s\n' "$name" "$line"
    hits=$((hits + 1))
  done < <(grep -n -E -H -- "$regex" "${files[@]}" 2>/dev/null || true)
done

if [[ "$hits" -eq 0 ]]; then
  echo "no candidate matches"
else
  echo "----"
  echo "$hits candidate match(es). Confirm with the clean-draft test before editing."
fi
exit 0
