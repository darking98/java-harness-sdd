---
name: spec
description: Fase de spec del harness java-harness-sdd para un ticket — lanza al spec-author, valida la consistencia y deja el spec esperando la aprobación del humano. También aplica cambios pedidos al spec y persiste la aprobación.
argument-hint: "<TICKET> [aprobado | cambios a aplicar]"
disable-model-invocation: true
---

# Fase de spec

Argumentos: `$ARGUMENTS` — la clave del ticket y, opcionalmente, `aprobado`
o los cambios que el humano pide sobre un spec existente.

Sos el **leader** de esta fase: coordinás y llevás el estado. No escribís
el spec (es del spec-author) ni código (un hook lo bloquea). Esta sesión
termina en la puerta de aprobación: implementar es otra sesión
(`/java-harness-sdd:deliver`), con contexto limpio.

## Contexto corto

Cada llamada tuya relee toda la conversación: es lo que más cuesta.

- No leas `requirements.md`, `design.md`, `tasks.md` ni investigaciones
  enteras. Del spec, al humano le mostrás solo `approval.md`.
- De `feature-list.json` leé solo la entrada del ticket
  (`grep -n -A15 '"name": *"<TICKET>"'`) y editala con Edit.
- Los archivos del harness se editan con Edit/Write, nunca por Bash.
- A los subagentes les pasás rutas, no contenido.

## Arranque

1. Si no existe `.harness/feature-list.json`: que corra
   `/java-harness-sdd:install-harness`, y parás.
2. Si el ticket no está en `feature-list.json`: que lo cargue con
   `/java-harness-sdd:add-feature <TICKET>`, y parás.
3. `bash .harness/init.sh`. Si falla por algo que no sea este ticket,
   parás y lo reportás.
4. Si la rama actual (`git branch --show-current`) no contiene la clave
   del ticket, o `init.sh` avisó que está atrasada respecto de
   `BASE_BRANCH`, decíselo **antes** de lanzar al spec-author: diseñar
   sobre código viejo cuesta un spec rehecho. Cambiar o actualizar la rama
   lo hace él.

## Según el estado del ticket

### `pending` con `"sdd": false`

No lleva spec. Decile que siga con `/java-harness-sdd:deliver <TICKET>` y
parás.

### `pending` con `"sdd": true`

1. **Hechos del repo al día:**
   ```bash
   PREV="${TMPDIR:-/tmp}/profile-facts.prev.md"
   cp .harness/docs/profile-facts.md "$PREV" 2>/dev/null
   bash .harness/bin/profile-facts.sh > .harness/docs/profile-facts.md
   diff "$PREV" .harness/docs/profile-facts.md
   ```
   Si el diff muestra un cambio **estructural** (adaptador, contenedor,
   clase base, regla ArchUnit, `@Profile` o migración nuevos o que
   desaparecieron), actualizá esa línea del perfil en
   `docs/architecture.md` con su fuente y contáselo al humano en una línea.
   Una clase nueva en un paquete existente no es estructural.
2. **Investigación previa, solo si el spec necesita algo que no está en el
   repo** (Jira, Confluence, contratos de otros servicios). Lo que se
   responde leyendo el código lo resuelve el spec-author.
   - Escribí antes preguntas cerradas ("¿qué endpoint resuelve una cuenta
     virtual y qué devuelve?"), no temas.
   - Un `Explore` con `model: "sonnet"` (dos solo si son fuentes
     independientes). Pedile cada respuesta con su fuente (link, archivo y
     línea) y "no definido" cuando ninguna fuente lo responde.
   - Guardá lo que devuelva, literal, en
     `.harness/progress/research-<TICKET>.md` (que puede traer ya el
     ticket, de `add-feature`: agregá abajo, no lo pises). Tus inferencias
     van aparte, marcadas como tales. Si el humano trae investigación
     propia, va al mismo archivo con su origen.
   - Lo que falte de Jira o Confluence se puede leer con `twg` si está
     instalado (ver `add-feature`), antes que con un `Explore`.
3. Lanzá **1 `java-harness-sdd:spec-author`** con el `name` exacto del
   ticket y, si existe, la ruta de `research-<TICKET>.md`.
4. Seguí en **Resultado del spec-author**.

### `spec_ready`

- Si los argumentos (o la respuesta del humano en esta sesión) dicen
  **aprobado**: seteá `"spec_approved": true` **antes de cualquier otra
  cosa** y cerrá con:
  > "Aprobación guardada. Hacé `/clear` y después
  > `/java-harness-sdd:deliver <TICKET>`."
- Si piden **cambios**: seteá `"spec_approved": false` si estaba en
  `true`, relanzá al spec-author con el ticket y los cambios tal como los
  pidió el humano, y seguí en **Resultado del spec-author**.
- Si no dicen nada y ya está aprobado: que siga con
  `/java-harness-sdd:deliver <TICKET>`.
- Si no dicen nada y no está aprobado: mostrale `approval.md` y recordale
  que le toca aprobar o pedir cambios.

### `in_progress` o `done`

El spec ya pasó. Para seguir: `/java-harness-sdd:deliver <TICKET>`.
Cambiar un spec aprobado lo devuelve a `spec_ready` y descarta su
aprobación: hacelo solo si el humano lo pide explícitamente.

### `blocked`

- Si el humano dice que ya está destrabado: volvé `status` a
  `blocked_from`, borrá ese campo y seguí por el estado que corresponda.
- Si no: recordale el motivo (el archivo anotado en
  `progress/current.md`) y qué necesitás de él.

## Resultado del spec-author

- `spec_ready -> ...`: cambiá `status` a `spec_ready` y corré
  `bash .harness/init.sh`. Si el chequeo de consistencia del spec falla,
  relanzá al spec-author con los errores: un spec inconsistente no llega
  al humano.
- `blocked -> <archivo>`: guardá el estado actual en `"blocked_from"`,
  cambiá `status` a `blocked`, anotá el archivo en `progress/current.md` y
  contale el bloqueo en dos líneas. No lo destrabes inventando.

Con el spec consistente, actualizá `progress/current.md` (ticket, rama,
fase `spec_ready`, próximo paso) y **parás**. Mensaje al humano:

1. El contenido de `.harness/specs/<TICKET>/approval.md`, tal cual.
2. > "Spec en `.harness/specs/<TICKET>/`. Si algo del resumen te hace
   > ruido, el detalle está en `design.md` y `requirements.md`. Decí
   > **'aprobado'** o pedime cambios. Cuando lo apruebes, `/clear` y
   > `/java-harness-sdd:deliver <TICKET>`."

## Reglas duras

- ❌ No apruebes por el humano ni asumas aprobado algo que no quedó
  persistido en `feature-list.json`.
- ❌ No edites el spec vos: los cambios van por el spec-author.
- ❌ No lances al implementer: eso es `deliver`, en otra sesión.
- ❌ No crees `.harness/.direct-edit` ni toques `.harness/bin/`, `init.sh`,
  `.state/` ni `harness.conf` con una feature en curso.
- ❌ Nada de `git add`, `commit`, `stash`, `push`, ramas ni PRs.
