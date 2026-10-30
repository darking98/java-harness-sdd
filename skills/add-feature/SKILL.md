---
name: add-feature
description: Agrega un ticket de Jira como feature pending en .harness/feature-list.json del harness java-harness-sdd (clave, título, descripción, criterios de aceptación). Usar cuando el humano quiere cargar o registrar un ticket en el harness.
argument-hint: "<TICKET> (ej. B2B-130)"
allowed-tools: [Read, Write, Edit, Bash]
---

# Agregar un ticket al harness

Argumento: `$ARGUMENTS` — la clave del ticket (ej. `B2B-130`).

## Protocolo

1. Verificá que existe `.harness/feature-list.json`. Si no, decile al
   humano que primero corra `/java-harness-sdd:install-harness` y pará.
2. Validá la clave contra `JIRA_KEY_PATTERN` de `.harness/harness.conf`.
   Si ya hay una feature con ese `name`, mostrala y pará.
3. Conseguí el contenido del ticket, en este orden:
   - **`twg`** (CLI de Atlassian; por Bash, sin cargar herramientas en
     cada llamada como un conector):
     1. `command -v twg` (en Windows también
        `$LOCALAPPDATA/Programs/twg/bin/twg`). Si no está, pasá a la
        siguiente opción.
     2. `twg whoami`. Si no hay sesión, el login es interactivo (abre el
        navegador) y lo hace el humano: pedile que corra `! twg login` en
        el prompt de Claude Code y avise. No lo corras vos.
     3. `twg jira workitem get <TICKET> -o json`: título (`summary`),
        estado, asignado y descripción.
     4. Si la descripción enlaza páginas de Confluence (URLs `/wiki/` en
        `embedCard` o `inlineCard`), leelas, porque es común que la
        historia y los criterios vivan ahí:
        `twg confluence content get <url> --detail full --format md --body-only`.
     5. Si el ticket está asignado a otra persona o en un estado avanzado,
        avisale al humano antes de seguir: puede ser trabajo de otro.
   - Si no hay `twg` pero hay un conector de Jira/Atlassian autenticado en
     la sesión, usalo para lo mismo.
   - Si no, pedile al humano que pegue el título, la descripción y los
     criterios de aceptación, literales y en orden.

   Si lo leíste de Jira/Confluence, guardá el texto **literal** (sin
   resumir) en `.harness/progress/research-<TICKET>.md`, bajo
   `## Ticket` con cada fuente (URL). El spec-author no tiene acceso a
   Jira: ese archivo es su contexto del ticket (alcance, fuera de alcance,
   dependencias), más allá de los criterios.
4. Mostrale al humano la entrada propuesta, con los criterios numerados
   `A1`, `A2`, ... en el orden en que van a quedar (el spec los referencia
   por ese número), y preguntale:
   - `"sdd": true` (pasa por spec: default para lógica nueva) o `false`
     (bump de dependencias, config, fix trivial).
   Agregala **solo** cuando confirme:

```json
{
  "name": "B2B-130",
  "title": "<título del ticket>",
  "description": "<una o dos líneas>",
  "acceptance": ["<criterio 1>", "<criterio 2>"],
  "notes": "<opcional: contexto, links, decisiones ya tomadas>",
  "sdd": true,
  "status": "pending",
  "spec_approved": false
}
```

5. Corré `java .harness/bin/FeatureListCheck.java .harness '<JIRA_KEY_PATTERN>'`
   para validar el archivo.
6. Decile el próximo paso: `/java-harness-sdd:spec <TICKET>` si es
   `"sdd": true`, `/java-harness-sdd:deliver <TICKET>` si no.

## Reglas

- ❌ No inventes criterios de aceptación: copiá los del ticket. Si el
  ticket no tiene, pedíselos al humano o dejá la feature con un único
  criterio "Definir criterios con el PO" y avisá que el spec-author se va a
  bloquear.
- ❌ No reordenes los criterios de una feature que ya tiene spec: cambia el
  significado de cada `A<k>`.
- ❌ No cambies el estado de otras features.
- ❌ No lances al spec-author: cargar un ticket no es empezar a trabajarlo.
