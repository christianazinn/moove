#!/usr/bin/env bash
# Create GitHub labels + one issue per docs/tasks/NN-*.md brief, in order, so issue #N == task N
# on a fresh repo. Idempotent-ish: skips briefs whose title already exists as an issue.
set -euo pipefail
cd "$(dirname "$0")/.."

label() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null; }
label task            "0E8A16" "Claimable unit of work"
label blocked         "B60205" "Blocked - see comments for on what"
label proposal        "5319E7" "Change to shared direction; lazy consensus by deadline"
label needs-decision  "D93F0B" "Humans needed"
label contract-change "FBCA04" "Changes SpacetimeDB tables/reducers"
label help-wanted     "008672" "Anyone can take this"
label stretch         "C5DEF5" "Only after the core demo works"
for l in backend ios-capture ios-newhome commerce; do label "lane:$l" "1D76DB" "Lane: $l"; done

field() { sed -n "s/^$1: //p" "$2" | head -1; }

existing=$(gh issue list --state all --limit 500 --json title --jq '.[].title')
for f in docs/tasks/[0-9][0-9]-*.md; do
  title=$(field title "$f"); lane=$(field lane "$f");
  deps=$(field depends "$f"); tracks=$(field tracks "$f"); stretch=$(field stretch "$f")
  if grep -Fxq "$title" <<<"$existing"; then echo "skip (exists): $title"; continue; fi
  labels="task,lane:$lane"; [ "$stretch" = "true" ] && labels="$labels,stretch"
  body=$(mktemp)
  {
    echo "**Lane:** $lane · **Depends on:** $deps · **Tracks:** $tracks"
    echo
    echo "Brief: [\`$f\`](../blob/main/$f)"
    echo
    awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$f"
  } >"$body"
  gh issue create --title "$title" --label "$labels" --body-file "$body"
  rm -f "$body"
done
