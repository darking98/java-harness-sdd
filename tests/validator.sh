#!/usr/bin/env bash
# Tests for template/.harness/bin/FeatureListCheck.java: each case writes a fixture
# harness in a temp dir, runs the validator and checks exit code and message.
#
#   bash tests/validator.sh
set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$PLUGIN_DIR/template/.harness/bin/FeatureListCheck.java"
KEY='^[A-Z][A-Z0-9]+-[0-9]+$'
PASS=0
FAIL=0
H=$(mktemp -d)

run() { # name expected_exit expected_text features_json
  rm -rf "$H/progress" && mkdir -p "$H/progress"
  [ -n "${REVIEW:-}" ] && printf '%s\n' "$REVIEW" >"$H/progress/review-B2B-1.md"
  printf '{"features": [%s]}\n' "$4" >"$H/feature-list.json"
  local out code
  out=$(java "$CHECK" "$H" "$KEY" 2>&1)
  code=$?
  if [ "$code" = "$2" ] && printf '%s' "$out" | grep -qF -- "$3"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s (exit %s, esperado %s con "%s")\n%s\n' "$1" "$code" "$2" "$3" "$out"
  fi
}

spec() { # requirements tasks
  mkdir -p "$H/specs/B2B-1"
  printf '%s\n' "$1" >"$H/specs/B2B-1/requirements.md"
  printf '%s\n' "$2" >"$H/specs/B2B-1/tasks.md"
  touch "$H/specs/B2B-1/design.md" "$H/specs/B2B-1/approval.md"
}

REQS='## R1
CUANDO x, el sistema DEBE y.
Criterio: A1

## R2
SI falla ENTONCES el sistema DEBE z.
Criterio: A2'
TASKS='- [x] T1 — dominio. Cubre: R1.
- [x] T2 — adaptador. Cubre: R2.'
spec "$REQS" "$TASKS"

DONE='"name": "B2B-1", "acceptance": ["a", "b"], "sdd": true, "status": "done", "spec_approved": true, "base_commit": "044d7b7"'
APPROVED='# Review — B2B-1

**Veredicto:** APPROVED'

REVIEW="$APPROVED" run "done con APPROVED válido" 0 "válido" "{$DONE}"
REVIEW="" run "done sin review" 1 "no existe" "{$DONE}"
REVIEW="${APPROVED/APPROVED/APPROVED | CHANGES_REQUESTED}" run "done con plantilla copiada" 1 "línea de veredicto inválida" "{$DONE}"
REVIEW="$APPROVED
**Veredicto:** CHANGES_REQUESTED" run "done con dos veredictos" 1 "2 líneas de veredicto" "{$DONE}"
REVIEW="${APPROVED/APPROVED/CHANGES_REQUESTED}" run "done con CHANGES_REQUESTED" 1 "no es APPROVED" "{$DONE}"

REVIEW="" run "sdd ausente" 1 '"sdd" tiene que estar presente' '{"name": "B2B-1", "acceptance": ["a"], "status": "pending"}'
run "spec_approved en pending" 1 "con status pending" '{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "pending", "spec_approved": true}'
run "in_progress sin base_commit" 1 'sin "base_commit"' '{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "in_progress"}'
run "base_commit inválido" 1 'sin "base_commit"' '{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "in_progress", "base_commit": "HEAD"}'

run "blocked sin blocked_from" 1 'sin "blocked_from"' '{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "blocked"}'
run "blocked_from inválido" 1 'sin "blocked_from"' '{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "blocked", "blocked_from": "done"}'
run "blocked con blocked_from" 0 "válido" '{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "blocked", "blocked_from": "pending"}'
run "blocked_from fuera de blocked" 1 "solo puede existir en status blocked" '{"name": "B2B-1", "acceptance": ["a"], "sdd": false, "status": "pending", "blocked_from": "pending"}'

READY='"name": "B2B-1", "acceptance": ["a", "b"], "sdd": true, "status": "spec_ready"'
run "spec válido completo" 0 "válido" "{$READY}"
mv "$H/specs/B2B-1/approval.md" "$H/approval.bak"
run "spec_ready sin approval.md" 1 "approval.md" "{$READY}"
REVIEW="$APPROVED" run "done sin approval.md (specs anteriores)" 0 "válido" "{$DONE}"
REVIEW=""
mv "$H/approval.bak" "$H/specs/B2B-1/approval.md"

spec "## R1
CUANDO x, el sistema DEBE y.
Criterio: A1

## Preguntas abiertas
Criterio: A2" "- [ ] T1 — a. Cubre: R1."
run "encabezado corta el requirement" 1 "A2 no está cubierto" "{$READY}"

spec "$REQS" "- [ ] T1 — a. Cubre: R1.
- [ ] T1 — b. Cubre: R2."
run "T duplicada" 1 "T1 duplicada" "{$READY}"

spec "$REQS" "- [ ] T1 — a. Cubre: R1 y R2."
run "Cubre con y" 0 "válido" "{$READY}"
spec "$REQS" "- [ ] T1 — a. Cubre: R1/R2."
run "Cubre con /" 0 "válido" "{$READY}"

spec "## R1
CUANDO x, el sistema DEBE y.
Criterio: A1" "- [ ] T1 — a. Cubre: R1."
run "criterio sin cubrir" 1 "A2 no está cubierto" "{$READY}"

# --current: the hooks' way to know the feature in progress, whatever the layout.
cat >"$H/feature-list.json" <<'EOF'
{
  "features": [
    { "name": "B2B-1", "status": "done" },
    {
      "status":
        "in_progress",
      "name": "B2B-2"
    }
  ]
}
EOF
CURRENT=$(java "$CHECK" --current "$H")
if [ "$CURRENT" = "B2B-2" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL  --current (obtenido '$CURRENT')"; fi
printf '{"features": [{"name": "B2B-1", "status": "pending"}]}' >"$H/feature-list.json"
if ! java "$CHECK" --current "$H" >/dev/null; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL  --current sin feature en curso"; fi

rm -rf "$H"
echo ""
echo "validator: $PASS ok, $FAIL fallidos"
[ "$FAIL" -eq 0 ]
