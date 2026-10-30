#!/usr/bin/env bash
# Stop / SubagentStop (implementer) — if application code changed since the last
# check, runs the fast verification (FAST_TEST_CMD: compile + domain, application
# and ArchUnit tests). On failure, exit 2 keeps the agent working and stderr tells
# it why.
#
# SubagentStop: up to MAX_RETRIES blocking rounds per broken state, counted in
#   .state/verify-retries; after that the implementer is let through and is expected
#   to report blocked (stop_hook_active would allow a single retry only).
# Stop: fires at the end of EVERY main-session response. It only acts while a
#   feature is in_progress (otherwise the changes are the human's own) and warns once
#   per broken state (.state/last-failed, written only by Stop: a state the
#   implementer left broken still reaches the leader once).
# The full build (Testcontainers) is never run here: `.harness/init.sh --full` is
# mandatory before the review.
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MAX_RETRIES=3

INPUT=$(cat)
load_harness || exit 0

EVENT=$(json_string_field "$INPUT" hook_event_name)
AGENT_TYPE=$(json_string_field "$INPUT" agent_type)

case "$EVENT" in
  SubagentStop)
    [ "$AGENT_TYPE" = "${PLUGIN_AGENT_PREFIX}implementer" ] || exit 0
    ;;
  Stop)
    json_true_field "$INPUT" stop_hook_active && exit 0
    has_feature_in_progress || exit 0
    ;;
  *)
    exit 0
    ;;
esac

cd "$CLAUDE_PROJECT_DIR" || exit 0
[ -f .harness/bin/fingerprint.sh ] || exit 0
. .harness/bin/fingerprint.sh

STATE_DIR="$HARNESS_DIR/.state"
mkdir -p "$STATE_DIR"
RETRIES_FILE="$STATE_DIR/verify-retries"

FINGERPRINT=$(harness_fingerprint)
if [ -z "$FINGERPRINT" ] || [ "$FINGERPRINT" = "$(cat "$STATE_DIR/last-verified" 2>/dev/null)" ]; then
  rm -f "$RETRIES_FILE"
  exit 0
fi
if [ "$EVENT" = "Stop" ] && [ "$FINGERPRINT" = "$(cat "$STATE_DIR/last-failed" 2>/dev/null)" ]; then
  exit 0
fi

LOG="$STATE_DIR/verify.log"
if eval "$FAST_TEST_CMD" >"$LOG" 2>&1; then
  printf '%s' "$FINGERPRINT" >"$STATE_DIR/last-verified"
  rm -f "$STATE_DIR/last-failed" "$RETRIES_FILE"
  exit 0
fi
# Only Stop records the failure: if the implementer leaves the code broken, the
# leader's next Stop must still warn once.
[ "$EVENT" = "Stop" ] && printf '%s' "$FINGERPRINT" >"$STATE_DIR/last-failed"

report_failure() {
  echo "[java-harness-sdd] La verificación rápida falla con los cambios actuales en el código ($FAST_TEST_CMD)."
  echo "$1"
  echo "Log completo: .harness/.state/verify.log — últimas líneas:"
  tail -40 "$LOG"
}

if [ "$EVENT" = "SubagentStop" ]; then
  RETRIES=$(cat "$RETRIES_FILE" 2>/dev/null || echo 0)
  if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    rm -f "$RETRIES_FILE"
    exit 0
  fi
  RETRIES=$((RETRIES + 1))
  printf '%s' "$RETRIES" >"$RETRIES_FILE"
  if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    report_failure "Último intento ($RETRIES/$MAX_RETRIES). Si no lo resolvés ahora, dejá el motivo en .harness/progress/impl-<TICKET>.md y terminá con 'blocked -> .harness/progress/impl-<TICKET>.md'." >&2
  else
    report_failure "Corregilo antes de terminar (intento $RETRIES/$MAX_RETRIES)." >&2
  fi
  exit 2
fi

report_failure "Sos el leader: no lo arregles vos. Relanzá al implementer con este error o reportáselo al humano. Este estado no se vuelve a avisar hasta que cambie el código." >&2
exit 2
