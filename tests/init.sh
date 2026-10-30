#!/usr/bin/env bash
# Tests for template/.harness/init.sh in a throwaway repo with fake build commands.
#
#   bash tests/init.sh
set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

R=$(mktemp -d)
git -C "$R" init -q
git -C "$R" config core.autocrlf false
cp -R "$PLUGIN_DIR/template/.harness" "$R/.harness"
cp "$PLUGIN_DIR/template/CLAUDE.local.md" "$R/"
printf '.harness/\nCLAUDE.local.md\n' >>"$R/.git/info/exclude"
printf '#!/bin/sh\n' >"$R/gradlew"
sed -i \
  -e 's/^FAST_TEST_CMD=.*/FAST_TEST_CMD="touch .harness\/fast-ran"/' \
  -e 's/^FULL_VERIFY_CMD=.*/FULL_VERIFY_CMD="touch .harness\/full-ran"/' \
  -e 's/^REQUIRES_DOCKER_FOR_FULL=.*/REQUIRES_DOCKER_FOR_FULL="false"/' \
  -e 's/^JAVA_MIN_VERSION=.*/JAVA_MIN_VERSION="17"/' \
  "$R/.harness/harness.conf"

ran() { [ -f "$R/.harness/$1" ] && echo 1 || echo 0; }

bash "$R/.harness/init.sh" >/dev/null 2>&1
check "verde: exit 0" 0 "$?"
check "verde: corre los tests rápidos" 1 "$(ran fast-ran)"

# State error in an unrelated feature: still reported, still fails, build still runs.
printf '{"features": [{"name": "B2B-9", "acceptance": ["a"], "sdd": true, "status": "spec_ready"}]}\n' >"$R/.harness/feature-list.json"
rm -f "$R/.harness/fast-ran" "$R/.harness/full-ran"
bash "$R/.harness/init.sh" --full >/dev/null 2>&1
check "estado roto: exit != 0" 1 "$?"
check "estado roto: --full corre el build igual" 1 "$(ran full-ran)"
bash "$R/.harness/init.sh" >/dev/null 2>&1
check "estado roto: rápido corre los tests igual" 1 "$(ran fast-ran)"

# Build output goes to the log, not to the agent's context; a failure shows the tail.
printf '{"features": []}\n' >"$R/.harness/feature-list.json"
sed -i 's/^FAST_TEST_CMD=.*/FAST_TEST_CMD="echo RUIDO-DEL-BUILD; touch .harness\/fast-ran"/' "$R/.harness/harness.conf"
OUT=$(bash "$R/.harness/init.sh" 2>&1)
check "salida: el ruido del build no se imprime" 0 "$(printf '%s' "$OUT" | grep -c '^RUIDO-DEL-BUILD$')"
check "salida: el ruido queda en el log" 1 "$(grep -c RUIDO-DEL-BUILD "$R/.harness/.state/build-fast.log")"
sed -i 's/^FAST_TEST_CMD=.*/FAST_TEST_CMD="echo ERROR-VISIBLE; false"/' "$R/.harness/harness.conf"
OUT=$(bash "$R/.harness/init.sh" 2>&1)
check "salida: en rojo muestra la cola del log" 1 "$(printf '%s' "$OUT" | grep -c '^ERROR-VISIBLE$')"
sed -i 's/^FAST_TEST_CMD=.*/FAST_TEST_CMD="touch .harness\/fast-ran"/' "$R/.harness/harness.conf"

# Branch behind origin/<BASE_BRANCH> (as of the last fetch): warned, not fatal.
git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$R" checkout -q -b ahead
git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "from the team"
git -C "$R" update-ref refs/remotes/origin/dev HEAD
git -C "$R" checkout -q -
sed -i 's/^BASE_BRANCH=.*/BASE_BRANCH="dev"/' "$R/.harness/harness.conf"
OUT=$(bash "$R/.harness/init.sh" 2>&1)
check "base: avisa la rama atrasada" 1 "$(printf '%s' "$OUT" | grep -c '1 commit(s) de origin/dev')"
check "base: el aviso no hace fallar" 0 "$(bash "$R/.harness/init.sh" >/dev/null 2>&1; echo $?)"
git -C "$R" merge -q --ff-only ahead
check "base: al día" 1 "$(bash "$R/.harness/init.sh" 2>&1 | grep -c 'al día con origin/dev')"

# A CLAUDE.local.md from 0.3.x still imports the protocol on every session.
cp "$R/CLAUDE.local.md" "$R/CLAUDE.local.md.bak"
printf '@.harness/LEADER.md\n' >>"$R/CLAUDE.local.md"
check "CLAUDE.local.md viejo: falla" 1 "$(bash "$R/.harness/init.sh" 2>&1 | grep -c 'versión anterior')"
mv "$R/CLAUDE.local.md.bak" "$R/CLAUDE.local.md"

# Environment error (no wrapper): the build is skipped.
rm -f "$R/gradlew" "$R/.harness/full-ran"
bash "$R/.harness/init.sh" --full >/dev/null 2>&1
check "entorno roto: saltea el build" 0 "$(ran full-ran)"

rm -rf "$R"
echo ""
echo "init: $PASS ok, $FAIL fallidos"
[ "$FAIL" -eq 0 ]
