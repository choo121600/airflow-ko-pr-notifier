#!/usr/bin/env bash
# Polls apache/airflow and posts to a Discord webhook:
#   1) open PRs labeled translation:ko that have not been notified yet
#   2) new commits on main touching the en locale folder (ko sync needed)
# State (last seen timestamps, PR numbers, commit SHAs) lives in state.json,
# committed back by the workflow.
set -euo pipefail

STATE_FILE="state.json"
EN_PATH="airflow-core/src/airflow/ui/public/i18n/locales/en"

notify() {
  curl -sf -H "Content-Type: application/json" -d "$1" "$DISCORD_WEBHOOK_URL" >/dev/null
  sleep 1
}

### 1) Open translation:ko PRs awaiting review ###############################
# Any currently-open PR not yet notified gets a review-request message.
# This covers brand-new PRs, PRs that existed before this notifier started,
# and PRs that get the label added after creation.

SEEN=$(jq -c .seen "$STATE_FILE")

RESULTS=$(gh api -X GET search/issues \
  -f q='repo:apache/airflow is:pr is:open label:"translation:ko"' \
  -f advanced_search=true \
  -f sort=created -f order=asc -f per_page=100 \
  --jq '.items')

COUNT=$(jq length <<<"$RESULTS")
echo "Found $COUNT open translation:ko PR(s)"

NEW_NUMBERS='[]'
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
        description: ("리뷰를 기다리는 한국어 번역 PR입니다 — by **" + $author + "**"),
        color: 1752220,
        timestamp: $created,
        footer: { text: "apache/airflow · label:translation:ko" }
      }]
    }')

  notify "$PAYLOAD"
  echo "Notified Discord about PR #$NUMBER"
  NEW_NUMBERS=$(jq ". + [$NUMBER]" <<<"$NEW_NUMBERS")
done < <(jq -c '.[]' <<<"$RESULTS")

if [ "$(jq length <<<"$NEW_NUMBERS")" -gt 0 ]; then
  jq --argjson nums "$NEW_NUMBERS" \
    'del(.last_created) | .seen = ((.seen + $nums) | unique | sort | .[-500:])' \
    "$STATE_FILE" > state.tmp && mv state.tmp "$STATE_FILE"
  echo "PR state updated: seen += $(jq -c . <<<"$NEW_NUMBERS")"
fi

### 2) New commits on main touching the en locale folder #####################

LAST_EN=$(jq -r .en_last_commit_date "$STATE_FILE")
SEEN_SHAS=$(jq -c .en_seen_shas "$STATE_FILE")

COMMITS=$(gh api -X GET repos/apache/airflow/commits \
  -f sha=main -f path="$EN_PATH" -f since="$LAST_EN" -f per_page=30 \
  --jq 'reverse')

EN_COUNT=$(jq length <<<"$COMMITS")
echo "Found $EN_COUNT commit(s) touching en locale since $LAST_EN"

if [ "$EN_COUNT" -gt 0 ]; then
  while read -r commit; do
    SHA=$(jq -r .sha <<<"$commit")
    if jq -e --arg sha "$SHA" 'index($sha)' <<<"$SEEN_SHAS" >/dev/null; then
      echo "Commit ${SHA:0:8} already notified, skipping"
      continue
    fi

    # Fetch commit detail to list which en files changed
    FILES=$(gh api "repos/apache/airflow/commits/$SHA" 2>/dev/null \
      | jq --arg p "$EN_PATH/" '[.files[].filename | select(startswith($p)) | ltrimstr($p)]' \
      || echo '[]')

    FILE_LIST=$(jq -r 'if length == 0 then "(파일 목록 조회 실패)"
      elif length > 15 then (.[:15] | map("`" + . + "`") | join(", ")) + " 외 \(length - 15)개"
      else map("`" + . + "`") | join(", ") end' <<<"$FILES")

    PAYLOAD=$(jq -n \
      --arg title "$(jq -r '"en 변경: " + (.commit.message | split("\n")[0])[0:230]' <<<"$commit")" \
      --arg url "$(jq -r .html_url <<<"$commit")" \
      --arg files "$FILE_LIST" \
      --arg date "$(jq -r .commit.committer.date <<<"$commit")" \
      '{
        embeds: [{
          title: $title,
          url: $url,
          description: ("en 로케일 파일이 변경되었습니다. ko 동기화가 필요할 수 있습니다.\n변경 파일: " + $files),
          color: 15105570,
          timestamp: $date,
          footer: { text: "apache/airflow · locales/en @ main" }
        }]
      }')

    notify "$PAYLOAD"
    echo "Notified Discord about en commit ${SHA:0:8}"
  done < <(jq -c '.[]' <<<"$COMMITS")

  NEW_EN_LAST=$(jq -r 'map(.commit.committer.date) | max' <<<"$COMMITS")
  NEW_SHAS=$(jq '[.[].sha]' <<<"$COMMITS")
  jq --arg last "$NEW_EN_LAST" --argjson shas "$NEW_SHAS" \
    '.en_last_commit_date = $last | .en_seen_shas = ((.en_seen_shas + $shas) | unique | .[-100:])' \
    "$STATE_FILE" > state.tmp && mv state.tmp "$STATE_FILE"
  echo "en state updated: en_last_commit_date=$NEW_EN_LAST"
fi
