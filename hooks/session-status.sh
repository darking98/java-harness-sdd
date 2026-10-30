#!/usr/bin/env bash
# SessionStart — tells the session (stdout reaches its context on this event) when
# the installed harness is older or newer than the plugin, and which command resumes
# a feature in progress. Silent otherwise.
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cat >/dev/null
load_harness || exit 0

if has_feature_in_progress; then
  FEATURE=$(current_feature)
  [ -n "$FEATURE" ] && echo "[java-harness-sdd] $FEATURE está in_progress. Si el humano quiere seguirla: /java-harness-sdd:deliver $FEATURE."
fi

INSTALLED=$(cat "$HARNESS_DIR/VERSION" 2>/dev/null)
PLUGIN=$(json_string_field "$(cat "${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json" 2>/dev/null)" version)
[ -n "$PLUGIN" ] || exit 0

if [ "$INSTALLED" != "$PLUGIN" ]; then
  echo "[java-harness-sdd] El harness de este repo es la versión ${INSTALLED:-desconocida} y el plugin es la $PLUGIN. Avisale al humano: los docs de .harness/ pueden estar desactualizados (ver el CHANGELOG del plugin)."
fi
exit 0
