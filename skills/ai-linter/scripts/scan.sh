#!/usr/bin/env bash
# First-pass detector for AI process residue and stock diction.
# Prints candidate lines. Does not rewrite. Hits are hints; apply SKILL.md
# before cutting (false positives are expected).
set -euo pipefail

usage() {
  echo "usage: $0 <file-or-dir> [file-or-dir...]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage

# Collect regular files. Skip binaries and this skill's own examples
# (they contain "before" text on purpose).
files=()
while IFS= read -r -d '' f; do
  case "$f" in
    */skills/ai-linter/*) continue ;;
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
  'carry-over|[Yy]our earlier (point|question|comment)|[Aa]s mentioned above|[Aa]s discussed'
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
  exit 0
fi

echo "----"
echo "$hits candidate match(es). Confirm with the clean-draft test before editing."
exit 1
