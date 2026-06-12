#!/usr/bin/env bash
# Polls apache/airflow for new PRs labeled translation:ko and posts each
# unseen one to a Discord webhook. State (last created_at + seen PR numbers)
# lives in state.json, committed back by the workflow.
set -euo pipefail

STATE_FILE="state.json"
LAST_CREATED=$(jq -r .last_created "$STATE_FILE")
SEEN=$(jq -c .seen "$STATE_FILE")

QUERY="repo:apache/airflow is:pr label:\"translation:ko\" created:>${LAST_CREATED}"

RESULTS=$(gh api -X GET search/issues \
  -f q="$QUERY" -f advanced_search=true \
  -f sort=created -f order=asc -f per_page=50 \
  --jq '.items')

COUNT=$(jq length <<<"$RESULTS")
echo "Found $COUNT new PR(s) created after $LAST_CREATED"
[ "$COUNT" -eq 0 ] && exit 0

while read -r pr; do
  NUMBER=$(jq .number <<<"$pr")
  if jq -e "index($NUMBER)" <<<"$SEEN" >/dev/null; then
    echo "PR #$NUMBER already notified, skipping"
    continue
  fi

  PAYLOAD=$(jq -n \
    --arg title "$(jq -r '"#\(.number) \(.title)"' <<<"$pr")" \
    --arg url "$(jq -r .html_url <<<"$pr")" \
    --arg author "$(jq -r .user.login <<<"$pr")" \
    --arg created "$(jq -r .created_at <<<"$pr")" \
    '{
      embeds: [{
        title: $title,
        url: $url,
        description: ("새 한국어 번역 PR이 올라왔습니다 — by **" + $author + "**"),
        color: 1752220,
        timestamp: $created,
        footer: { text: "apache/airflow · label:translation:ko" }
      }]
    }')

  curl -sf -H "Content-Type: application/json" -d "$PAYLOAD" "$DISCORD_WEBHOOK_URL" >/dev/null
  echo "Notified Discord about PR #$NUMBER"
  sleep 1
done < <(jq -c '.[]' <<<"$RESULTS")

NEW_LAST=$(jq -r 'map(.created_at) | max' <<<"$RESULTS")
NEW_NUMBERS=$(jq '[.[].number]' <<<"$RESULTS")
jq --arg last "$NEW_LAST" --argjson nums "$NEW_NUMBERS" \
  '.last_created = $last | .seen = ((.seen + $nums) | unique | sort | .[-200:])' \
  "$STATE_FILE" > state.tmp && mv state.tmp "$STATE_FILE"
echo "State updated: last_created=$NEW_LAST"
