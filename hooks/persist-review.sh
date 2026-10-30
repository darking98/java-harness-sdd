#!/usr/bin/env bash
# Persists the reviewer's verdict to .harness/progress/review-<TICKET>.md, verbatim.
#
# The reviewer is read-only (no Write/Edit), as is standard for reviewer subagents;
# writing its verdict here, mechanically, keeps it from passing through anyone's
# paraphrase. It only writes a well-formed verdict for the feature in_progress:
# exactly one "**Veredicto:** APPROVED|CHANGES_REQUESTED" line (a copied template line
# "APPROVED | CHANGES_REQUESTED" is not a verdict). Never blocks: on anything else it
# exits 0 and the leader relaunches the reviewer.
#
# Where the verdict comes from depends on how the reviewer ran:
#   - foreground: its final text, last_assistant_message in SubagentStop;
#   - background: it delivers through the SubagentHandback tool, so its last text is
#     a progress note. SubagentStop then falls back to the last SubagentHandback
#     message in its own transcript (agent_transcript_path), and PreToolUse on
#     SubagentHandback catches it at delivery, straight from tool_input.message.
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERDICT_LINE='^\*\*Veredicto:\*\*[[:space:]]+(APPROVED|CHANGES_REQUESTED)[[:space:]]*$'

INPUT=$(cat)
load_harness || exit 0
[ "$(json_string_field "$INPUT" agent_type)" = "${PLUGIN_AGENT_PREFIX}reviewer" ] || exit 0

has_verdict() {
  printf '%s' "$1" | grep -qE "$VERDICT_LINE"
}

case "$(json_string_field "$INPUT" hook_event_name)" in
  PreToolUse)
    RAW=$(json_text_field "$INPUT" message)
    ;;
  SubagentStop)
    RAW=$(json_text_field "$INPUT" last_assistant_message)
    if ! has_verdict "$RAW"; then
      TRANSCRIPT=$(normalize_path "$(json_string_field "$INPUT" agent_transcript_path)")
      if [ -f "$TRANSCRIPT" ]; then
        RAW=$(grep '"SubagentHandback"' "$TRANSCRIPT" | tail -1)
        RAW=$(json_text_field "$RAW" message)
      fi
    fi
    ;;
  *)
    exit 0
    ;;
esac

# From the "# Review" heading on: a preamble before it is dropped, and so are code
# fence lines if the reviewer wrapped the block in one.
MESSAGE=$(printf '%s\n' "$RAW" \
  | sed -n '/^# Review/,$p' \
  | grep -vE '^```[a-z]*[[:space:]]*$')
[ -n "$MESSAGE" ] || exit 0

[ "$(printf '%s\n' "$MESSAGE" | grep -cE "$VERDICT_LINE")" -eq 1 ] || exit 0
printf '%s\n' "$MESSAGE" | grep -E '^\*\*Veredicto:\*\*' | grep -vqE "$VERDICT_LINE" && exit 0

TICKET=$(printf '%s\n' "$MESSAGE" | head -1 | sed -nE 's/^# Review[[:space:]]*[^[:alnum:][:space:]]*[[:space:]]*([^[:space:]]+).*/\1/p')
[ -n "$TICKET" ] || exit 0
printf '%s' "$TICKET" | grep -Eq "$JIRA_KEY_PATTERN" || exit 0
[ "$TICKET" = "$(current_feature)" ] || exit 0

TARGET="$HARNESS_DIR/progress/review-$TICKET.md"
# Both events may deliver the same verdict: writing it twice must not rotate it away.
if [ -f "$TARGET" ] && [ "$(cat "$TARGET")" = "$MESSAGE" ]; then
  exit 0
fi
[ -f "$TARGET" ] && mv -f "$TARGET" "$HARNESS_DIR/progress/review-$TICKET.previous.md"
printf '%s\n' "$MESSAGE" >"$TARGET"
exit 0
