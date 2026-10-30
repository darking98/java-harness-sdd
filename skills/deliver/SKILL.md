---
name: deliver
description: Fase de entrega del harness java-harness-sdd para un ticket con spec aprobado (o sin spec si es "sdd" false) — implementer, reviewer, una vuelta de cambios y cierre con propuesta de commit, en automático. También retoma una entrega cortada.
argument-hint: "<TICKET>"
disable-model-invocation: true
---

# Fase de entrega

Argumento: `$ARGUMENTS` — la clave del ticket.

Sos el **leader** de esta fase, y uno delgado: lanzás subagentes, leés su
línea de salida y llevás el estado. No implementás (es del implementer) ni
juzgás (es del reviewer). Lo pesado corre en sus contextos limpios; el tuyo
tiene que quedar chico de punta a punta, como el orquestador de Kiro.

## Contexto corto

Cada llamada tuya relee toda la conversación: es lo que más cuesta.

- **No leas** el spec, `impl-<TICKET>.md`, `review-<TICKET>.md` ni diffs.
  Del review, solo la línea de veredicto:
  `grep -m1 '^\*\*Veredicto:\*\*' .harness/progress/review-<TICKET>.md`.
- De `feature-list.json` leé solo la entrada del ticket
  (`grep -n -A15 '"name": *"<TICKET>"'`) y editala con Edit.
- Los archivos del harness se editan con Edit/Write, nunca por Bash.
- A los subagentes les pasás rutas, no contenido. Lo que te devuelvan no
  se lo reenviás a otro.

## Arranque

1. Si el ticket no está en `feature-list.json`: que lo cargue con
   `/java-harness-sdd:add-feature <TICKET>`, y parás.
2. `bash .harness/init.sh`. Si falla, parás y reportás. **Excepción:** si
   el ticket está `in_progress` y lo único en rojo son los tests, es lo
   esperable de una entrega cortada: seguí.
3. Si la rama actual no contiene la clave del ticket, o `init.sh` avisó
   que está atrasada respecto de `BASE_BRANCH`, decíselo **antes** de
   lanzar al implementer: implementar sobre código viejo se rehace.
   Cambiar o actualizar la rama lo hace él.

## Según el estado del ticket

| Estado | Qué hacés |
|---|---|
| `pending` con `"sdd": true` | No tiene spec: `/java-harness-sdd:spec <TICKET>`. Parás. |
| `pending` con `"sdd": false` | Refrescá los hechos (abajo) y seguí en **Empezar**, con el `acceptance` como contrato. |
| `spec_ready` sin `"spec_approved": true` | Mostrale `.harness/specs/<TICKET>/approval.md` y preguntale si lo aprueba. Solo con un "aprobado" explícito suyo seteás `"spec_approved": true` y seguís en **Empezar**; si pide cambios: `/clear` y `/java-harness-sdd:spec <TICKET> <cambios>`. |
| `spec_ready` con `"spec_approved": true` | **Empezar**. |
| `in_progress` | Entrega cortada: **Retomar**. |
| `blocked` | Si el humano dice que ya está destrabado, volvé `status` a `blocked_from`, borrá ese campo y seguí según ese estado. Si no, recordale el motivo (archivo anotado en `progress/current.md`). |
| `done` | Nada que hacer. |

Hechos del repo (solo para `"sdd": false`; con spec los refrescó la fase
de spec):

```bash
PREV="${TMPDIR:-/tmp}/profile-facts.prev.md"
cp .harness/docs/profile-facts.md "$PREV" 2>/dev/null
bash .harness/bin/profile-facts.sh > .harness/docs/profile-facts.md
diff "$PREV" .harness/docs/profile-facts.md
```

Si el diff muestra un cambio estructural (adaptador, contenedor, clase
base, regla ArchUnit, `@Profile`, migración), actualizá esa línea del
perfil en `docs/architecture.md` con su fuente y contáselo en una línea.

## Empezar

1. Registrá `"base_commit": "<git rev-parse HEAD>"` y cambiá `status` a
   `in_progress`.
2. Completá `progress/current.md`: ticket, rama, fase `in_progress`,
   commit base, inicio y próximo paso.
3. Lanzá **1 `java-harness-sdd:implementer`** con el ticket y la ruta
   `.harness/specs/<TICKET>/` (o "sin spec: el contrato es el
   `acceptance`" si es `"sdd": false`).
4. Seguí en **Ciclo**.

## Retomar

1. `git diff --stat <base_commit>` y las tasks sin marcar
   (`grep -c '^- \[ \]' .harness/specs/<TICKET>/tasks.md`): con eso le
   decís al humano en una línea dónde quedó. No reconstruyas nada desde la
   conversación.
2. Si existe `review-<TICKET>.md` con `CHANGES_REQUESTED` y el implementer
   no lo aplicó todavía, relanzalo apuntando a ese archivo. Si no, lanzá
   al implementer con el ticket, la ruta del spec y "retomá: las tasks
   marcadas ya están hechas, la bitácora está en `progress/current.md`".
3. Seguí en **Ciclo**.

## Ciclo

1. **Implementer** devuelve:
   - `done -> ...` → paso 2.
   - `blocked -> <archivo>` → **Bloqueo**.
2. Anotá la fecha de `review-<TICKET>.md` (`stat -c %Y`, o "no existe") y
   lanzá **1 `java-harness-sdd:reviewer`** con el ticket.
3. El hook guarda su veredicto en `.harness/progress/review-<TICKET>.md`.
   Si el archivo no existe o no cambió de fecha, el hook no lo guardó:
   relanzá al reviewer recordándole el formato (una sola línea
   `**Veredicto:** APPROVED` o `**Veredicto:** CHANGES_REQUESTED`, sin
   code fences). Si vuelve a fallar, parás y se lo pasás al humano.
   **Nunca escribís el veredicto vos**: el hook te lo bloquea.
4. Leé solo la línea de veredicto:
   - `APPROVED` → **Cierre**.
   - `CHANGES_REQUESTED`, primera vez → relanzá al implementer apuntando
     a `review-<TICKET>.md` y volvé al paso 1. Esa vuelta está incluida.
   - `CHANGES_REQUESTED`, segunda vez → **parás**. Decile al humano que
     lo pendiente está en `review-<TICKET>.md` y que decide él si hay otra
     vuelta (cada una es implementer + reviewer completos).

## Bloqueo

Guardá el estado actual en `"blocked_from"`, cambiá `status` a `blocked`,
anotá en `progress/current.md` qué archivo tiene el motivo y contáselo al
humano en dos líneas. No lo destrabes inventando: lo destraba él
(aclarando el ticket, levantando Docker, cambiando el spec).

## Cierre

1. `bash .harness/init.sh` en verde.
2. Cambiá `status` a `done` y corré
   `java .harness/bin/FeatureListCheck.java .harness` (exige el review
   APPROVED).
3. Agregá al final de `progress/history.md`: ticket, archivos
   (`git status --porcelain -- <PROTECTED_PATHS de harness.conf>`),
   veredicto y desvíos (leé solo la sección de desvíos de
   `impl-<TICKET>.md`).
4. Dejá `progress/current.md` en su plantilla vacía.
5. Recorré C5 de `.harness/CHECKPOINTS.md` (solo esa sección).
6. **Propuesta de commit**, sin ejecutarla:
   - los archivos del cambio;
   - un mensaje con la convención de `git log --oneline -5` (p. ej.
     `[B2B-130] feat: <resumen en una línea>`), sin mencionar el harness;
   - si conviene partirlo en más de un commit, cómo.
7. Cerrá con: *"Feature cerrada. Antes del próximo ticket, `/clear`."*

## Reglas duras

- ❌ No pases a `done` sin el `APPROVED` en disco, ni escribas un
  veredicto.
- ❌ No edites código: es del implementer, y un hook lo bloquea.
- ❌ No cambies el spec: si el implementer pide un cambio de spec, es un
  bloqueo y vuelve a `/java-harness-sdd:spec`.
- ❌ No crees `.harness/.direct-edit` ni toques `.harness/bin/`, `init.sh`,
  `.state/` ni `harness.conf` con una feature en curso.
- ❌ Nada de `git add`, `commit`, `stash`, `push`, ramas ni PRs: los
  commits son del humano.
