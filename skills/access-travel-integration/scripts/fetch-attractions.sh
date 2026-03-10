#!/usr/bin/env bash
# Fetch the latest attractions & identifiers list from Access Development
# Downloads the HTML source and extracts a JSON lookup file for agent use.
# Usage: bash scripts/fetch-attractions.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
REF_DIR="$SKILL_DIR/references"
JSON_FILE="$REF_DIR/attractions-and-identifiers.json"
URL="https://static.accessdevelopment.com/attraction_assets/attractions_and_identifiers.html"

mkdir -p "$REF_DIR"

echo "Fetching attractions list from Access Development..."
HTML=$(curl -sfL "$URL")

# Extract name/id pairs from HTML table rows and produce JSON
echo "$HTML" \
  | sed -n 's/.*<td><span>\(.*\)<\/span><\/td>/\1/p' \
  | paste - - \
  | awk -F'\t' 'BEGIN { print "[" }
      NR > 1 { print "," }
      {
        gsub(/&amp;/, "\\&", $1)
        printf "  { \"name\": \"%s\", \"attraction_id\": \"%s\" }", $1, $2
      }
      END { print "\n]" }' \
  > "$JSON_FILE"

COUNT=$(grep -c '"attraction_id"' "$JSON_FILE")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Saved: $JSON_FILE"
echo "  Attractions: $COUNT"
echo "  Fetched at:  $TIMESTAMP"
