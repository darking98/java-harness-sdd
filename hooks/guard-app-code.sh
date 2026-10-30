#!/usr/bin/env bash
# PreToolUse (Write|Edit|MultiEdit) — enforces who may write what.
#
#   application code (PROTECTED_PATHS)  only java-harness-sdd:implementer, only while
#                                       a feature is in_progress
#   .harness/ and CLAUDE.local.md       the main session (leader) all but the files
#                                       that would switch the harness off or forge a
#                                       verdict; each subagent only its own files
#   anything else                       not this hook's business
#
# Tool calls made inside a subagent carry its agent_type; calls from the main
# session carry none. Exit 2 blocks the call and stderr goes back to the caller.
#
# Known limit: Bash writes (sed -i, redirections, touch) do not go through these
# tools and are not intercepted. The agents' rules forbid them; this hook does not
# enforce it.
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INPUT=$(cat)
load_harness || exit 0

FILE=$(json_string_field "$INPUT" file_path)
[ -n "$FILE" ] || exit 0
REL=$(project_relative_path "$FILE")
[ -n "$REL" ] || exit 0

AGENT_TYPE=$(json_string_field "$INPUT" agent_type)

deny() {
  echo "[java-harness-sdd] $1" >&2
  exit 2
}

if is_protected_path "$REL"; then
  case "$AGENT_TYPE" in
    "${PLUGIN_AGENT_PREFIX}implementer")
      has_feature_in_progress && exit 0
      deny "No hay ninguna feature en in_progress en .harness/feature-list.json: no se puede editar código de aplicación. Pará y devolvé el control al leader."
      ;;
    "")
      deny "La sesión principal (leader) no edita código de aplicación ($REL). Lanzá java-harness-sdd:implementer para la feature en curso. Si el humano quiere trabajar sin el harness, pedile que cree él mismo .harness/.direct-edit; vos no lo creás."
      ;;
    *)
      deny "El agente $AGENT_TYPE no puede editar código de aplicación ($REL); solo java-harness-sdd:implementer."
      ;;
  esac
fi

REL_LC=$(lowercase "$REL")
case "$REL_LC" in
  .harness/*|claude.local.md) ;;
  *) exit 0 ;;
esac

# Ownership inside the harness. feature-list.json and history.md belong to the
# leader alone: every state transition goes through the orchestrator. review-*.md is
# written only by persist-review.sh from the reviewer's own final message, so nobody
# can approve on the reviewer's behalf.
case "$AGENT_TYPE" in
  "")
    case "$REL_LC" in
      .harness/.direct-edit|.harness/init.sh|.harness/bin/*|.harness/.state/*)
        deny "El leader no puede escribir $REL: es parte de lo que verifica su trabajo. Si el humano quiere trabajar sin el harness, pedile que cree él mismo .harness/.direct-edit."
        ;;
      .harness/progress/review-*.md)
        deny "El leader no escribe veredictos: review-*.md lo guarda el hook a partir de la respuesta del reviewer. Si no apareció, relanzá al reviewer recordándole el formato."
        ;;
      .harness/harness.conf)
        has_feature_in_progress && deny "No se puede cambiar .harness/harness.conf con una feature en in_progress: cambiaría cómo se verifica ese trabajo. Si hace falta, decíselo al humano."
        ;;
    esac
    exit 0
    ;;
  "${PLUGIN_AGENT_PREFIX}spec-author")
    case "$REL_LC" in
      .harness/specs/*|.harness/progress/spec-*.md) exit 0 ;;
    esac
    ;;
  "${PLUGIN_AGENT_PREFIX}implementer")
    case "$REL_LC" in
      .harness/progress/current.md) exit 0 ;;
      .harness/specs/*/tasks.md|.harness/progress/impl-*.md)
        CURRENT=$(lowercase "$(current_feature)")
        case "$REL_LC" in
          ".harness/specs/$CURRENT/tasks.md"|".harness/progress/impl-$CURRENT.md")
            [ -n "$CURRENT" ] && exit 0
            ;;
        esac
        deny "El implementer solo escribe el tasks.md y el impl-*.md de la feature en in_progress (${CURRENT:-ninguna}), no $REL."
        ;;
    esac
    ;;
esac

deny "El agente ${AGENT_TYPE} no puede escribir $REL. Cada rol escribe solo sus archivos (ver .harness/docs/specs.md, \"Quién escribe qué\"); los cambios de estado los aplica el leader a partir de tu línea de salida."
