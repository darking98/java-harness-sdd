#!/usr/bin/env bash
# init.sh — Verificación del entorno y del estado del harness.
#
#   bash .harness/init.sh          entorno + estado + tests rápidos
#   bash .harness/init.sh --full   lo anterior + build completo (como CI)
#
# Si termina con exit != 0, la sesión no avanza. Salida en bloques [OK]/[FAIL]; la
# salida del build va a .harness/.state/build-<modo>.log y solo se muestra si falla.

set -u

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
cd "$REPO_DIR" || exit 1

MODE="fast"
[ "${1:-}" = "--full" ] && MODE="full"

ok()   { printf '[OK]    %s\n' "$1"; }
warn() { printf '[WARN]  %s\n' "$1"; }
fail() { printf '[FAIL]  %s\n' "$1"; EXIT_CODE=1; }

EXIT_CODE=0

if [ ! -f "$HARNESS_DIR/harness.conf" ]; then
  echo "[FAIL]  Falta .harness/harness.conf — reinstalá con /java-harness-sdd:install-harness"
  exit 1
fi
# shellcheck source=/dev/null
. "$HARNESS_DIR/harness.conf"

echo "── 1. Entorno ─────────────────────────────────────────"

if ! command -v java >/dev/null 2>&1; then
  fail "java no está en el PATH"
  exit 1
fi
JAVA_VERSION_LINE=$(java -version 2>&1 | head -1)
JAVA_MAJOR=$(printf '%s' "$JAVA_VERSION_LINE" | sed -E 's/.*version "([0-9]+)(\.[0-9]+)?.*/\1/')
if [ "$JAVA_MAJOR" = "1" ]; then
  JAVA_MAJOR=$(printf '%s' "$JAVA_VERSION_LINE" | sed -E 's/.*version "1\.([0-9]+).*/\1/')
fi
if [ "$JAVA_MAJOR" -lt 17 ] 2>/dev/null; then
  fail "java $JAVA_MAJOR en el PATH: el validador del harness necesita JDK 17 o más"
  exit 1
fi
if [ "$JAVA_MAJOR" -ge "$JAVA_MIN_VERSION" ] 2>/dev/null; then
  ok "java $JAVA_MAJOR (mínimo del proyecto $JAVA_MIN_VERSION)"
else
  warn "java en el PATH es $JAVA_MAJOR, el proyecto espera >= $JAVA_MIN_VERSION (ok si el build usa toolchain)"
fi

case "$BUILD_TOOL" in
  gradle) WRAPPER="./gradlew" ;;
  maven)  WRAPPER="./mvnw" ;;
  *)      fail "BUILD_TOOL desconocido en harness.conf: $BUILD_TOOL"; WRAPPER="" ;;
esac
if [ -n "$WRAPPER" ]; then
  if [ -f "$WRAPPER" ]; then ok "wrapper $WRAPPER presente"; else fail "falta $WRAPPER en la raíz del repo"; fi
fi

if ! command -v git >/dev/null 2>&1; then
  fail "git no está en el PATH"
fi

if [ "$MODE" = "full" ] && [ "$REQUIRES_DOCKER_FOR_FULL" = "true" ]; then
  if docker info >/dev/null 2>&1; then
    ok "docker disponible (Testcontainers)"
  else
    fail "docker no responde: la verificación completa necesita Testcontainers. Levantá Docker o reportá la feature como blocked."
  fi
fi

# Only an environment failure skips the build in step 5. A state error (for instance
# another feature with an inconsistent spec) is still reported and still fails the
# run, but must not keep the feature in progress from being verified.
ENV_EXIT_CODE=$EXIT_CODE

echo ""
echo "── 2. Archivos del harness ────────────────────────────"

for f in VERSION AGENTS.md CHECKPOINTS.md feature-list.json progress/current.md progress/history.md \
         docs/architecture.md docs/conventions.md docs/specs.md docs/verification.md \
         bin/FeatureListCheck.java bin/fingerprint.sh bin/profile-facts.sh; do
  if [ -f "$HARNESS_DIR/$f" ]; then ok ".harness/$f"; else fail "falta .harness/$f"; fi
done
if [ ! -f "$HARNESS_DIR/docs/profile-facts.md" ]; then
  warn "falta .harness/docs/profile-facts.md: generalo con bash .harness/bin/profile-facts.sh > .harness/docs/profile-facts.md"
fi

if [ ! -f "CLAUDE.local.md" ]; then
  fail "falta CLAUDE.local.md (sin él las sesiones no conocen las reglas del harness)"
elif grep -q '^@\.harness/LEADER\.md' CLAUDE.local.md; then
  fail "CLAUDE.local.md es de una versión anterior (importa .harness/LEADER.md, que ya no existe): reemplazalo por el del template del plugin"
else
  ok "CLAUDE.local.md"
fi

if grep -q '<completar>' "$HARNESS_DIR/docs/architecture.md"; then
  warn "el perfil de .harness/docs/architecture.md tiene campos <completar>"
fi

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
  PLUGIN_VERSION=$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" | head -1)
  INSTALLED_VERSION=$(cat "$HARNESS_DIR/VERSION" 2>/dev/null)
  if [ "$PLUGIN_VERSION" != "$INSTALLED_VERSION" ]; then
    warn "harness instalado ${INSTALLED_VERSION:-?}, plugin $PLUGIN_VERSION: revisá el CHANGELOG del plugin"
  fi
fi

echo ""
echo "── 3. El harness queda fuera de git ───────────────────"

for p in .harness CLAUDE.local.md; do
  if git ls-files --error-unmatch "$p" >/dev/null 2>&1; then
    fail "$p está TRACKEADO por git. Sacalo del índice (git rm -r --cached $p) sin commitear y revisá .git/info/exclude"
  elif git check-ignore -q "$p"; then
    ok "$p ignorado localmente"
  else
    fail "$p no está ignorado: agregalo a .git/info/exclude (no a .gitignore, que se commitea)"
  fi
done

# Behind the base branch = designing on code the team already changed. Checked against
# the last fetch only: fetching is the human's call, like every other git operation.
if [ -n "${BASE_BRANCH:-}" ]; then
  if git rev-parse --verify -q "origin/$BASE_BRANCH" >/dev/null; then
    BEHIND=$(git rev-list --count "HEAD..origin/$BASE_BRANCH" 2>/dev/null || echo 0)
    if [ "$BEHIND" -gt 0 ]; then
      warn "la rama tiene $BEHIND commit(s) de origin/$BASE_BRANCH sin incorporar (según el último fetch): conviene que el humano la actualice antes de diseñar o implementar"
    else
      ok "al día con origin/$BASE_BRANCH (según el último fetch)"
    fi
  else
    warn "no existe origin/$BASE_BRANCH localmente: no se puede chequear si la rama está al día"
  fi
fi

echo ""
echo "── 4. feature-list.json y specs ───────────────────────"

if ! java "$HARNESS_DIR/bin/FeatureListCheck.java" "$HARNESS_DIR" "$JIRA_KEY_PATTERN"; then
  EXIT_CODE=1
fi

echo ""
if [ "$MODE" = "full" ]; then
  VERIFY_CMD="$FULL_VERIFY_CMD"
  echo "── 5. Verificación completa: $VERIFY_CMD"
else
  VERIFY_CMD="$FAST_TEST_CMD"
  echo "── 5. Tests rápidos: $VERIFY_CMD"
fi
# The build output goes to a log, not to the agent's context: hundreds of lines read
# once and then re-read on every later call. Green prints one line; red, the tail.
mkdir -p "$HARNESS_DIR/.state"
BUILD_LOG="$HARNESS_DIR/.state/build-$MODE.log"
if [ "$ENV_EXIT_CODE" -ne 0 ]; then
  warn "salteado: el entorno (paso 1) tiene errores"
elif eval "$VERIFY_CMD" >"$BUILD_LOG" 2>&1; then
  ok "verificación $MODE verde (salida completa en .harness/.state/build-$MODE.log)"
  # Both levels include the fast tests, so the hooks need not repeat them for this state.
  # shellcheck source=/dev/null
  . "$HARNESS_DIR/bin/fingerprint.sh"
  FINGERPRINT=$(harness_fingerprint)
  if [ -n "$FINGERPRINT" ]; then
    mkdir -p "$HARNESS_DIR/.state"
    printf '%s' "$FINGERPRINT" >"$HARNESS_DIR/.state/last-verified"
    rm -f "$HARNESS_DIR/.state/last-failed" "$HARNESS_DIR/.state/verify-retries"
  fi
else
  fail "verificación $MODE en rojo — últimas 40 líneas (completa en .harness/.state/build-$MODE.log):"
  tail -40 "$BUILD_LOG"
fi

echo ""
echo "── Resumen ($MODE) ────────────────────────────────────"
if [ "$EXIT_CODE" -eq 0 ]; then
  ok "Entorno listo."
else
  echo "[FAIL]  Entorno NO está listo. Resolvé los errores antes de avanzar."
fi
exit "$EXIT_CODE"
