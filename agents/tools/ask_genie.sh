#!/usr/bin/env bash
# ask_genie.sh — ask a Genie space a natural-language question from the
# terminal (Genie Conversation API). Prints the generated SQL, the result
# table, and Genie's text answer.
#
# Usage:
#   ./agents/tools/ask_genie.sh <space_id> "Why did the last run fail the gate?"
#   ./agents/tools/ask_genie.sh <space_id> "..." --conversation <id>  # follow-up
#
# Env: DATABRICKS_HOST / DATABRICKS_TOKEN (sourced from .env if present).
# Requires jq + curl.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

SPACE_ID="${1:?usage: ask_genie.sh <space_id> \"question\" [--conversation <id>]}"
QUESTION="${2:?usage: ask_genie.sh <space_id> \"question\" [--conversation <id>]}"
CONV_ID=""
if [ "${3:-}" = "--conversation" ]; then
  CONV_ID="${4:?--conversation needs an id}"
fi

for tool in jq curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "[genie] $tool is required" >&2; exit 1; }
done

API="${DATABRICKS_HOST%/}/api/2.0/genie/spaces/${SPACE_ID}"
AUTH="Authorization: Bearer ${DATABRICKS_TOKEN}"

if [ -z "$CONV_ID" ]; then
  RESP="$(curl -sS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg q "$QUESTION" '{content: $q}')" \
    "${API}/start-conversation")"
  CONV_ID="$(jq -r '.conversation_id // .id // empty' <<<"$RESP")"
  MSG_ID="$(jq -r '.message_id // empty' <<<"$RESP")"
else
  RESP="$(curl -sS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg q "$QUESTION" '{content: $q}')" \
    "${API}/conversations/${CONV_ID}/messages")"
  MSG_ID="$(jq -r '.message_id // .id // empty' <<<"$RESP")"
fi

if [ -z "$CONV_ID" ] || [ -z "$MSG_ID" ]; then
  echo "[genie] failed to start conversation:" >&2
  echo "$RESP" >&2
  exit 1
fi

echo "[genie] waiting for answer (conversation ${CONV_ID}) ..." >&2
STATUS="IN_PROGRESS"
POLL=0
while [ "$STATUS" != "COMPLETED" ] && [ "$STATUS" != "FAILED" ]; do
  POLL=$((POLL + 1))
  if [ "$POLL" -gt 40 ]; then
    echo "[genie] timed out waiting for message ${MSG_ID}" >&2
    exit 1
  fi
  sleep 3
  MSG="$(curl -sS -H "$AUTH" "${API}/conversations/${CONV_ID}/messages/${MSG_ID}")"
  STATUS="$(jq -r '.status // "FAILED"' <<<"$MSG")"
done

if [ "$STATUS" != "COMPLETED" ]; then
  echo "[genie] message FAILED:" >&2
  echo "$MSG" | jq -r '.error // .' >&2
  exit 1
fi

SQL="$(jq -r '[.attachments[]?.query.query] | map(select(. != null)) | .[0] // empty' <<<"$MSG")"
if [ -n "$SQL" ]; then
  echo "--- generated SQL ---"
  echo "$SQL"
  echo "--- result ---"
  # Result rows are not on the message; fetch via the statement id.
  STMT_ID="$(jq -r '[.attachments[]?.query.statement_id] | map(select(. != null)) | .[0] // empty' <<<"$MSG")"
  if [ -n "$STMT_ID" ]; then
    RES="$(curl -sS -H "$AUTH" "${DATABRICKS_HOST%/}/api/2.0/sql/statements/${STMT_ID}")"
    jq -r '
      (.manifest.schema.columns // [] | map(.name)) as $cols
      | ($cols | @tsv),
        ((.result.data_array // [])[] | map(. // "") | @tsv)
    ' <<<"$RES"
  else
    echo "(no result statement on the message)"
  fi
fi
echo "--- answer ---"
jq -r '[.attachments[]?.text.content] | map(select(. != null)) | .[0] // "(no text answer)"' <<<"$MSG"
echo "[genie] conversation_id=${CONV_ID}" >&2
