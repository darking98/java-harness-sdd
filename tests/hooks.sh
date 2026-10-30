#!/usr/bin/env bash
# Tests for the plugin hooks: builds a throwaway git repo with a minimal .harness/,
# feeds each hook a JSON fixture on stdin and checks exit codes and side effects.
#
#   bash tests/hooks.sh
#
# FAST_TEST_CMD is faked: it passes or fails depending on .harness/fake-result, so
# no build tool is needed. What this cannot test is Claude Code itself (matchers in
# hooks.json, the agent_type it sends): that needs a real session.
set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$PLUGIN_DIR/hooks"
PASS=0
FAIL=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s (esperado %s, obtenido %s)\n' "$1" "$2" "$3"
  fi
}

new_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  git -C "$dir" config core.autocrlf false
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  mkdir -p "$dir/src/main/java" "$dir/.harness/bin" "$dir/.harness/progress" "$dir/.harness/specs"
  echo 'class A {}' >"$dir/src/main/java/A.java"
  git -C "$dir" add src && git -C "$dir" commit -qm init
  printf '.harness/\nCLAUDE.local.md\n' >>"$dir/.git/info/exclude"
  cp "$PLUGIN_DIR/template/.harness/bin/fingerprint.sh" "$PLUGIN_DIR/template/.harness/bin/FeatureListCheck.java" "$dir/.harness/bin/"
  cp "$PLUGIN_DIR/template/.harness/VERSION" "$dir/.harness/"
  cat >"$dir/.harness/harness.conf" <<'EOF'
FAST_TEST_CMD="grep -q pass .harness/fake-result"
JIRA_KEY_PATTERN='^[A-Z][A-Z0-9]+-[0-9]+$'
PROTECTED_PATHS="src buildSrc build.gradle pom.xml"
EOF
  echo pass >"$dir/.harness/fake-result"
  set_status "$dir" pending
  printf '%s' "$dir"
}

set_status() { # dir status
  printf '{"features": [{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "%s"}]}\n' "$2" >"$1/.harness/feature-list.json"
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'
}

pre_tool() { # agent_type file_path(raw)
  local agent=""
  [ -n "$1" ] && agent=",\"agent_id\":\"a1\",\"agent_type\":\"$1\""
  printf '{"session_id":"s","hook_event_name":"PreToolUse"%s,"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' \
    "$agent" "$(json_escape "$2")"
}

stop_event() { # event agent_type stop_hook_active
  local agent=""
  [ -n "$2" ] && agent=",\"agent_id\":\"a1\",\"agent_type\":\"$2\""
  printf '{"session_id":"s","hook_event_name":"%s"%s,"stop_hook_active":%s}' "$1" "$agent" "$3"
}

run_hook() { # dir script  (stdin: fixture) -> prints exit code
  CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOKS/$2" >/dev/null 2>&1
  printf '%s' "$?"
}

IMPL="java-harness-sdd:implementer"
SPEC="java-harness-sdd:spec-author"
REV="java-harness-sdd:reviewer"

# ── guard-app-code.sh ────────────────────────────────────────────────────────
R=$(new_repo)
SRC="$R/src/main/java/B.java"

check "guard: leader → src" 2 "$(pre_tool "" "$SRC" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer sin in_progress" 2 "$(pre_tool "$IMPL" "$SRC" | run_hook "$R" guard-app-code.sh)"
set_status "$R" in_progress
check "guard: implementer con in_progress" 0 "$(pre_tool "$IMPL" "$SRC" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer con sufijo falso" 2 "$(pre_tool "evil-implementer" "$SRC" | run_hook "$R" guard-app-code.sh)"
check "guard: reviewer → src" 2 "$(pre_tool "$REV" "$SRC" | run_hook "$R" guard-app-code.sh)"
check "guard: leader → README" 0 "$(pre_tool "" "$R/README.md" | run_hook "$R" guard-app-code.sh)"
check "guard: ruta fuera del proyecto" 0 "$(pre_tool "" "/elsewhere/src/main/java/X.java" | run_hook "$R" guard-app-code.sh)"
check "guard: ruta relativa protegida" 2 "$(pre_tool "" "src/main/java/X.java" | run_hook "$R" guard-app-code.sh)"
check "guard: leader → feature-list" 0 "$(pre_tool "" "$R/.harness/feature-list.json" | run_hook "$R" guard-app-code.sh)"
check "guard: spec-author → spec" 0 "$(pre_tool "$SPEC" "$R/.harness/specs/B2B-1/design.md" | run_hook "$R" guard-app-code.sh)"
check "guard: spec-author → feature-list" 2 "$(pre_tool "$SPEC" "$R/.harness/feature-list.json" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer → tasks.md" 0 "$(pre_tool "$IMPL" "$R/.harness/specs/B2B-1/tasks.md" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer → design.md" 2 "$(pre_tool "$IMPL" "$R/.harness/specs/B2B-1/design.md" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer → impl report" 0 "$(pre_tool "$IMPL" "$R/.harness/progress/impl-B2B-1.md" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer → review" 2 "$(pre_tool "$IMPL" "$R/.harness/progress/review-B2B-1.md" | run_hook "$R" guard-app-code.sh)"
check "guard: Explore → current.md" 2 "$(pre_tool "Explore" "$R/.harness/progress/current.md" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer → tasks.md de otro ticket" 2 "$(pre_tool "$IMPL" "$R/.harness/specs/OTRO-9/tasks.md" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer → impl de otro ticket" 2 "$(pre_tool "$IMPL" "$R/.harness/progress/impl-OTRO-9.md" | run_hook "$R" guard-app-code.sh)"

# Dots must be resolved before deciding: none of these may slip past the guard.
check "guard: leader con .." 2 "$(pre_tool "" "$R/foo/../src/main/java/X.java" | run_hook "$R" guard-app-code.sh)"
check "guard: spec-author con specs/../../src" 2 "$(pre_tool "$SPEC" "$R/.harness/specs/../../src/main/X.java" | run_hook "$R" guard-app-code.sh)"
check "guard: spec-author con specs/../feature-list" 2 "$(pre_tool "$SPEC" "$R/.harness/specs/../feature-list.json" | run_hook "$R" guard-app-code.sh)"
check "guard: relativa con .. que sale del proyecto" 0 "$(pre_tool "" "../otro/src/main/X.java" | run_hook "$R" guard-app-code.sh)"
check "guard: absoluta con .. que sale del proyecto" 0 "$(pre_tool "" "$R/../otro/src/main/X.java" | run_hook "$R" guard-app-code.sh)"

# What would switch the harness off or forge a verdict is off limits for the leader.
for f in .direct-edit bin/x.sh init.sh .state/last-verified progress/review-B2B-1.md; do
  check "guard: leader → .harness/$f" 2 "$(pre_tool "" "$R/.harness/$f" | run_hook "$R" guard-app-code.sh)"
done
check "guard: leader → harness.conf con feature en curso" 2 "$(pre_tool "" "$R/.harness/harness.conf" | run_hook "$R" guard-app-code.sh)"
set_status "$R" pending
check "guard: leader → harness.conf sin feature en curso" 0 "$(pre_tool "" "$R/.harness/harness.conf" | run_hook "$R" guard-app-code.sh)"
check "guard: implementer → tasks.md sin feature en curso" 2 "$(pre_tool "$IMPL" "$R/.harness/specs/B2B-1/tasks.md" | run_hook "$R" guard-app-code.sh)"
set_status "$R" in_progress

# Claude Code on Windows sends C:\... paths (JSON-escaped as C:\\...); Git Bash may
# expose the project dir as /c/.... Only meaningful where cygpath exists.
if command -v cygpath >/dev/null 2>&1; then
  WIN_ROOT=$(cygpath -w "$R")
  MIXED_ROOT=$(cygpath -m "$R")
  POSIX_ROOT="/$(printf '%s' "${MIXED_ROOT:0:1}" | tr '[:upper:]' '[:lower:]')${MIXED_ROOT:2}"
  WIN_SRC="$WIN_ROOT\\src\\main\\java\\B.java"
  UPPER_SRC=$(printf '%s' "$WIN_SRC" | tr '[:lower:]' '[:upper:]')
  check "guard: ruta Windows con \\\\" 2 "$(pre_tool "" "$WIN_SRC" | run_hook "$WIN_ROOT" guard-app-code.sh)"
  check "guard: ruta Windows en mayúsculas" 2 "$(pre_tool "" "$UPPER_SRC" | run_hook "$WIN_ROOT" guard-app-code.sh)"
  check "guard: proyecto /c/..., ruta C:\\..." 2 "$(pre_tool "" "$WIN_SRC" | run_hook "$POSIX_ROOT" guard-app-code.sh)"
  check "guard: Windows, implementer → tasks.md" 0 "$(pre_tool "$IMPL" "$WIN_ROOT\\.harness\\specs\\B2B-1\\tasks.md" | run_hook "$WIN_ROOT" guard-app-code.sh)"
  check "guard: Windows con .." 2 "$(pre_tool "" "$WIN_ROOT\\foo\\..\\src\\main\\java\\X.java" | run_hook "$WIN_ROOT" guard-app-code.sh)"
  check "guard: Windows, spec-author specs\\..\\..\\src" 2 "$(pre_tool "$SPEC" "$WIN_ROOT\\.harness\\specs\\..\\..\\src\\X.java" | run_hook "$WIN_ROOT" guard-app-code.sh)"
  check "guard: Windows, leader → .direct-edit" 2 "$(pre_tool "" "$WIN_ROOT\\.harness\\.direct-edit" | run_hook "$WIN_ROOT" guard-app-code.sh)"
fi

touch "$R/.harness/.direct-edit"
check "guard: .direct-edit" 0 "$(pre_tool "" "$SRC" | run_hook "$R" guard-app-code.sh)"
rm "$R/.harness/.direct-edit"

T=$(new_repo)
git -C "$T" add -f .harness/harness.conf
check "guard: harness.conf trackeado" 0 "$(pre_tool "" "$T/src/main/java/B.java" | run_hook "$T" guard-app-code.sh)"
check "guard: harness.conf trackeado avisa" 1 "$(pre_tool "" "$T/src/main/java/B.java" | CLAUDE_PROJECT_DIR="$T" bash "$HOOKS/guard-app-code.sh" 2>&1 >/dev/null | grep -c trackeado)"
check "session: harness trackeado, silencio" "" "$(echo '{}' | CLAUDE_PROJECT_DIR="$T" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOKS/session-status.sh" 2>/dev/null)"
T2=$(new_repo)
git -C "$T2" add -f .harness/bin/fingerprint.sh
check "guard: otro archivo de .harness trackeado" 0 "$(pre_tool "" "$T2/src/main/java/B.java" | run_hook "$T2" guard-app-code.sh)"

# ── verify-on-stop.sh — Stop ─────────────────────────────────────────────────
V=$(new_repo)
echo 'class C {}' >"$V/src/main/java/C.java"
check "stop: sin feature in_progress" 0 "$(stop_event Stop "" false | run_hook "$V" verify-on-stop.sh)"
set_status "$V" in_progress
echo fail >"$V/.harness/fake-result"
check "stop: cambios y test rojo" 2 "$(stop_event Stop "" false | run_hook "$V" verify-on-stop.sh)"
check "stop: mismo estado roto no re-avisa" 0 "$(stop_event Stop "" false | run_hook "$V" verify-on-stop.sh)"
echo 'class D {}' >"$V/src/main/java/D.java"
check "stop: stop_hook_active" 0 "$(stop_event Stop "" true | run_hook "$V" verify-on-stop.sh)"
echo pass >"$V/.harness/fake-result"
check "stop: estado nuevo verde" 0 "$(stop_event Stop "" false | run_hook "$V" verify-on-stop.sh)"
check "stop: guarda last-verified" 1 "$([ -s "$V/.harness/.state/last-verified" ] && echo 1 || echo 0)"
echo fail >"$V/.harness/fake-result"
check "stop: estado verificado no re-corre" 0 "$(stop_event Stop "" false | run_hook "$V" verify-on-stop.sh)"

N=$(new_repo)
set_status "$N" in_progress
echo fail >"$N/.harness/fake-result"
check "stop: sin cambios" 0 "$(stop_event Stop "" false | run_hook "$N" verify-on-stop.sh)"

# ── verify-on-stop.sh — SubagentStop ─────────────────────────────────────────
S=$(new_repo)
set_status "$S" in_progress
echo 'class E {}' >"$S/src/main/java/E.java"
echo fail >"$S/.harness/fake-result"
check "subagent: otro agente" 0 "$(stop_event SubagentStop "$REV" false | run_hook "$S" verify-on-stop.sh)"
check "subagent: intento 1" 2 "$(stop_event SubagentStop "$IMPL" false | run_hook "$S" verify-on-stop.sh)"
check "subagent: intento 2 (stop_hook_active)" 2 "$(stop_event SubagentStop "$IMPL" true | run_hook "$S" verify-on-stop.sh)"
LAST_MSG=$(stop_event SubagentStop "$IMPL" true | CLAUDE_PROJECT_DIR="$S" bash "$HOOKS/verify-on-stop.sh" 2>&1 >/dev/null)
check "subagent: intento 3 pide blocked" 1 "$(printf '%s' "$LAST_MSG" | grep -c 'Último intento')"
check "subagent: intento 4 deja pasar" 0 "$(stop_event SubagentStop "$IMPL" true | run_hook "$S" verify-on-stop.sh)"
check "subagent: contador reseteado" 0 "$([ -f "$S/.harness/.state/verify-retries" ] && echo 1 || echo 0)"
# The implementer left the code broken: the leader's next Stop still warns, once.
check "subagent → stop: el leader se entera" 2 "$(stop_event Stop "" false | run_hook "$S" verify-on-stop.sh)"
check "subagent → stop: una sola vez" 0 "$(stop_event Stop "" false | run_hook "$S" verify-on-stop.sh)"
echo pass >"$S/.harness/fake-result"
echo 'class F {}' >"$S/src/main/java/F.java"
check "subagent: verde" 0 "$(stop_event SubagentStop "$IMPL" false | run_hook "$S" verify-on-stop.sh)"

# ── persist-review.sh ────────────────────────────────────────────────────────
P=$(new_repo)
set_status "$P" in_progress
VERDICT='# Review — B2B-1

**Veredicto:** APPROVED

## Trazabilidad
- R1: [x] Foo#bar — dice "hola", ruta C:\code y ñ'
review_event() { # agent message
  printf '{"session_id":"s","hook_event_name":"SubagentStop","agent_id":"a1","agent_type":"%s","stop_hook_active":false,"last_assistant_message":"%s"}' \
    "$1" "$(json_escape "$2")"
}
check "review: otro agente no escribe" 0 "$(review_event "$IMPL" "$VERDICT" | run_hook "$P" persist-review.sh)"
check "review: otro agente, sin archivo" 0 "$([ -f "$P/.harness/progress/review-B2B-1.md" ] && echo 1 || echo 0)"
check "review: reviewer" 0 "$(review_event "$REV" "$VERDICT" | run_hook "$P" persist-review.sh)"
check "review: contenido literal" "$VERDICT" "$(cat "$P/.harness/progress/review-B2B-1.md" 2>/dev/null)"
review_event "$REV" "${VERDICT/APPROVED/CHANGES_REQUESTED}" | run_hook "$P" persist-review.sh >/dev/null
check "review: rota el anterior" 1 "$(grep -c APPROVED "$P/.harness/progress/review-B2B-1.previous.md" 2>/dev/null)"
rm -f "$P/.harness/progress/review-B2B-1"*.md
review_event "$REV" "no pude terminar" | run_hook "$P" persist-review.sh >/dev/null
check "review: sin veredicto no escribe" 0 "$([ -f "$P/.harness/progress/review-B2B-1.md" ] && echo 1 || echo 0)"

review_written() { # message -> 1 if the hook wrote review-B2B-1.md
  rm -f "$P/.harness/progress/review-B2B-1"*.md
  review_event "$REV" "$1" | run_hook "$P" persist-review.sh >/dev/null
  [ -f "$P/.harness/progress/review-B2B-1.md" ] && echo 1 || echo 0
}
check "review: con preámbulo, guarda" 1 "$(review_written "Listo, este es el veredicto:

$VERDICT")"
check "review: preámbulo descartado" "$VERDICT" "$(cat "$P/.harness/progress/review-B2B-1.md" 2>/dev/null)"
check "review: dentro de cerca de código, guarda sin la cerca" 1 "$(review_written "\`\`\`markdown
$VERDICT
\`\`\`")"
check "review: cerca descartada" "$VERDICT" "$(cat "$P/.harness/progress/review-B2B-1.md" 2>/dev/null)"
check "review: línea de plantilla copiada" 0 "$(review_written "${VERDICT/APPROVED/APPROVED | CHANGES_REQUESTED}")"
check "review: dos líneas de veredicto" 0 "$(review_written "$VERDICT
**Veredicto:** CHANGES_REQUESTED")"
check "review: veredicto válido + línea inválida" 0 "$(review_written "$VERDICT
**Veredicto:** quizás")"
check "review: ticket que no está en curso" 0 "$(review_written "${VERDICT/B2B-1/B2B-77}")"
set_status "$P" pending
check "review: sin feature en curso" 0 "$(review_written "$VERDICT")"
printf '{"features": [{"name": "core_12", "acceptance": ["a"], "sdd": false, "status": "in_progress"}]}\n' >"$P/.harness/feature-list.json"
sed -i "s/^JIRA_KEY_PATTERN=.*/JIRA_KEY_PATTERN='^[a-z]+_[0-9]+\$'/" "$P/.harness/harness.conf"
rm -f "$P/.harness/progress/review-core_12.md"
review_event "$REV" "${VERDICT/B2B-1/core_12}" | run_hook "$P" persist-review.sh >/dev/null
check "review: JIRA_KEY_PATTERN personalizado" 1 "$([ -f "$P/.harness/progress/review-core_12.md" ] && echo 1 || echo 0)"

# A background reviewer delivers through SubagentHandback: its last text is a progress
# note. The verdict has to be found in its transcript, or caught at delivery.
B=$(new_repo)
set_status "$B" in_progress
TRANSCRIPT="$B/agent.jsonl"
{
  printf '{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"init.sh --full is still running in the background."}]}}\n'
  printf '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"SubagentHandback","input":{"message":"%s"}}]}}\n' "$(json_escape "$VERDICT")"
} >"$TRANSCRIPT"
background_stop() {
  printf '{"session_id":"s","hook_event_name":"SubagentStop","agent_id":"a1","agent_type":"%s","stop_hook_active":false,"agent_transcript_path":"%s","last_assistant_message":"init.sh --full is still running in the background."}' \
    "$REV" "$(json_escape "$TRANSCRIPT")"
}
background_stop | run_hook "$B" persist-review.sh >/dev/null
check "review en segundo plano: lo saca del transcript" "$VERDICT" "$(cat "$B/.harness/progress/review-B2B-1.md" 2>/dev/null)"
background_stop | run_hook "$B" persist-review.sh >/dev/null
check "review en segundo plano: el mismo veredicto no rota" 0 "$([ -f "$B/.harness/progress/review-B2B-1.previous.md" ] && echo 1 || echo 0)"
rm -f "$B/.harness/progress/review-B2B-1.md"
printf '{"session_id":"s","hook_event_name":"PreToolUse","agent_id":"a1","agent_type":"%s","tool_name":"SubagentHandback","tool_input":{"message":"%s"}}' \
  "$REV" "$(json_escape "$VERDICT")" | run_hook "$B" persist-review.sh >/dev/null
check "review en la entrega (PreToolUse SubagentHandback)" "$VERDICT" "$(cat "$B/.harness/progress/review-B2B-1.md" 2>/dev/null)"
rm -f "$B/.harness/progress/review-B2B-1.md"
printf '{"session_id":"s","hook_event_name":"PreToolUse","agent_id":"a1","agent_type":"%s","tool_name":"SubagentHandback","tool_input":{"message":"%s"}}' \
  "$IMPL" "$(json_escape "$VERDICT")" | run_hook "$B" persist-review.sh >/dev/null
check "entrega de otro agente no escribe" 0 "$([ -f "$B/.harness/progress/review-B2B-1.md" ] && echo 1 || echo 0)"

# ── session-status.sh ────────────────────────────────────────────────────────
check "session: feature en curso, sugiere deliver" 1 "$(echo '{}' | CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOKS/session-status.sh" | grep -c 'deliver core_12')"
set_status "$P" pending
check "session: misma versión, silencio" "" "$(echo '{}' | CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOKS/session-status.sh")"
echo 0.0.1 >"$P/.harness/VERSION"
check "session: versión distinta avisa" 1 "$(echo '{}' | CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOKS/session-status.sh" | grep -c '0.0.1')"

rm -rf "$R" "$T" "$T2" "$V" "$N" "$S" "$P" "$B"

echo ""
echo "hooks: $PASS ok, $FAIL fallidos"
[ "$FAIL" -eq 0 ]
