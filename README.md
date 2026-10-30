# java-harness-sdd

Plugin de Claude Code que instala un harness de **Spec Driven Development**
multi-agente en servicios Java/Spring con **arquitectura hexagonal**.

Es la variante backend de
[frontend-harness-sdd](https://github.com/darking98/frontend-harness-sdd)
(misma metodología: spec EARS → aprobación humana → implementer →
reviewer), con dos diferencias de fondo:

- **El harness nunca entra en el repo del equipo.** Todo vive en
  `.harness/` y `CLAUDE.local.md`, excluidos vía `.git/info/exclude`.
- **Los commits son siempre del humano.** Ningún agente commitea, stashea
  ni pushea; al cerrar una feature el leader propone el commit y el humano
  decide.

## Qué trae

| Componente | Dónde | Qué hace |
|---|---|---|
| Agentes | `agents/` | `spec-author`, `implementer`, `reviewer` (solo lectura). Se invocan como `java-harness-sdd:<nombre>`. El leader es la sesión principal. |
| Hooks | `hooks/` | Ver abajo. No hacen nada en repos sin `.harness/` local. |
| `/java-harness-sdd:install-harness` | `skills/install-harness/` | Copia `template/` al repo, lo excluye de git y genera el perfil del repo: hechos extraídos por script (`profile-facts.md`), interpretación con fuente en cada línea y verificación independiente. |
| `/java-harness-sdd:add-feature <TICKET>` | `skills/add-feature/` | Carga un ticket de Jira como feature `pending`. Lo lee con el CLI `twg` de Atlassian (ticket y páginas de Confluence enlazadas) si está instalado; si no, con un conector o pegado a mano. |
| `/java-harness-sdd:spec <TICKET>` | `skills/spec/` | Fase de spec: spec-author, chequeo de consistencia y resumen para aprobar. Termina en la aprobación. |
| `/java-harness-sdd:deliver <TICKET>` | `skills/deliver/` | Fase de entrega, en automático: implementer → reviewer → una vuelta de cambios → cierre con propuesta de commit. Retoma una entrega cortada. |
| Template | `template/` | `.harness/` (docs, estado, `init.sh`, validador) + `CLAUDE.local.md` mínimo. |

### Hooks

| Evento | Script | Qué hace |
|---|---|---|
| `PreToolUse` (Write/Edit/MultiEdit) | `guard-app-code.sh` | Permisos por rol: solo el implementer edita código, y solo con una feature `in_progress`; dentro de `.harness/` cada subagente escribe solo sus archivos (el implementer, solo los del ticket en curso); `feature-list.json` es del leader, que no puede tocar lo que lo verifica a él. Las rutas se resuelven (`..`) antes de decidir. |
| `SubagentStop` (implementer) | `verify-on-stop.sh` | Si cambió el código, compila y corre los tests rápidos. Si fallan, el implementer sigue (hasta 3 intentos; después reporta `blocked`). |
| `SubagentStop` (reviewer) y `PreToolUse` (`SubagentHandback`) | `persist-review.sh` | Guarda literal el veredicto del reviewer en `progress/review-<TICKET>.md`, solo si es del ticket en curso y tiene una única línea de veredicto válida. Si el reviewer corre en segundo plano, toma el veredicto de su `SubagentHandback` (en la entrega, o de su transcript). |
| `Stop` | `verify-on-stop.sh` | Con una feature en curso y código cambiado, corre los tests rápidos y avisa una vez por estado roto. |
| `SessionStart` | `session-status.sh` | Avisa si el harness instalado es de otra versión que el plugin, y qué comando retoma una feature `in_progress`. |

El guard identifica a cada agente por el `agent_type` que Claude Code pasa a
los hooks (`java-harness-sdd:implementer`, ...); la sesión principal no
tiene `agent_type`. Si el repo trae cualquier archivo de `.harness/`
commiteado, los hooks no hacen nada: un plugin de usuario no corre código
que viene con un repo clonado.

### Modelos y costo

| Agente | Modelo | Por qué |
|---|---|---|
| spec-author | `opus` | El diseño es donde un error cuesta más. |
| implementer | `sonnet` | Con un spec detallado, implementar es mayormente ejecutar. Es el que más consume. Para volver a Opus, `model: opus` en `agents/implementer.md`. |
| reviewer | `opus` | Es la red de calidad. |
| `Explore` (investigación, verificación de la instalación) | `sonnet`, indicado al lanzarlo | Buscar y comparar contra fuentes. |
| leader (sesión principal) | el de la sesión (`/model`) | Orquesta; las decisiones de fondo las toma el humano. |

En un piloto real (un ticket de 27 requirements, todo en Opus, USD 22) más
de la mitad del costo fue releer el contexto de una sesión de leader que
vivió toda la feature. Desde 0.4.0, como en el harness de larga duración de
Anthropic o el Task Runner de Kiro, cada fase arranca limpia y el estado
vive en disco:

- **Dos sesiones por ticket**, cortadas en la aprobación del spec, donde
  el humano igual tiene que leer y decidir.
- **Leader delgado:** pasa rutas y lee una línea de cada subagente; nunca
  el spec, el diff ni el reporte entero.
- **Nada importado en cada sesión:** el protocolo lo carga el comando de
  la fase; `CLAUDE.local.md` tiene solo las reglas duras.
- **Spec breve:** cada cosa dicha una vez, código referenciado y no
  copiado, y un `approval.md` de 15 líneas para aprobar.

Con 0.4.x, un ticket chico (9 requirements, 5 tasks) costó unos USD 4.60
de punta a punta (ticket, spec, implementación, review aprobado en la
primera vuelta y cierre), estimado a precio de lista de la API.

## Requisitos

- **JDK 17 o más** en el PATH (el validador de `feature-list.json` corre
  con el source launcher de Java: no hace falta Node, jq ni Python). Es
  independiente de la versión con la que compila el proyecto.
- `bash` (en Windows, Git Bash) y `git`.
- Docker para la verificación completa si el repo usa Testcontainers.
- Opcional: el CLI [`twg`](https://developer.atlassian.com/cloud/twg-cli/getting-started/installation/)
  de Atlassian, autenticado (`twg login`), para que `add-feature` lea el
  ticket de Jira y sus páginas de Confluence. Sin él, se pega el ticket.

## Uso

Instalá el plugin con scope **user** (o `local`): con scope `project`,
Claude Code lo registra en `.claude/settings.json` del repo, que sí se
commitea.

```text
/plugin marketplace add <ruta-o-repo-de-este-plugin>
/plugin install java-harness-sdd@java-harness-sdd

# en la raíz del servicio:
/java-harness-sdd:install-harness
/java-harness-sdd:add-feature B2B-130
/java-harness-sdd:spec B2B-130      # leés approval.md y decís "aprobado"
/clear
/java-harness-sdd:deliver B2B-130   # implementación, review y cierre
```

Flujo:

```
         sesión 1: spec                              sesión 2: deliver
pending → [spec-author] → spec_ready → ⏸ "aprobado" │ /clear │ in_progress → [implementer ⇄ reviewer] → cierre → done
```

Una feature `"sdd": false` va directo a `deliver`. Para cambiar un spec:
`/java-harness-sdd:spec B2B-130 <cambios>`.

### Actualizar

`/plugin` solo ofrece actualizar si cambió `version` en `plugin.json`. Con
un marketplace de carpeta local: Marketplaces → `java-harness-sdd` →
**Update marketplace**, después Update del plugin y `/reload-plugins`. Si
el CHANGELOG no dice otra cosa, el `.harness/` instalado sigue sirviendo:
basta con actualizar `.harness/VERSION` y los archivos que la entrada
nombre.

## Verificación

| | Qué | Quién / cuándo |
|---|---|---|
| Rápida | compilación + tests de `domain`, `application` y ArchUnit (sin Spring ni contenedores) | Hooks al terminar el implementer o la respuesta, si cambió el código; `bash .harness/init.sh` |
| Completa | el build de CI (Testcontainers incluido) | `bash .harness/init.sh --full`, obligatorio antes del review |
| Estado y spec | invariantes de `feature-list.json`, review APPROVED para `done`, cobertura acceptance → requirements → tasks | `init.sh`, siempre |

Los comandos de cada repo están en `.harness/harness.conf`.

## Garantías y límites

- **Nadie aprueba en nombre del reviewer.** `review-*.md` lo escribe solo
  el hook, a partir de la respuesta final del reviewer; el leader no puede
  escribirlo, y el validador exige exactamente una línea
  `**Veredicto:** APPROVED` para `done`.
- **El leader no puede apagar el harness con Write/Edit**: no puede crear
  `.direct-edit` ni tocar `bin/`, `init.sh`, `.state/`, ni `harness.conf`
  con una feature en curso. Desactivarlo es decisión del humano.
- Los permisos por rol aplican a Write/Edit/MultiEdit. Escrituras por Bash
  (`sed -i`, redirecciones, `touch`) no pasan por esas herramientas y el
  guard no las ve, **incluido crear `.direct-edit`**: las prohíben las
  reglas de los agentes, y el reviewer revisa el diff completo contra el
  commit base de la feature.
- El hook no puede controlar qué campo de `feature-list.json` cambia el
  leader; el validador sí detecta estados imposibles (aprobado en
  `pending`, `done` sin review APPROVED, `in_progress` sin commit base,
  `blocked` sin `blocked_from`).
- Un cambio del spec después de aprobado no se detecta mecánicamente: lo
  cubre la regla de que el spec cambiado vuelve a `spec_ready`.
- La trazabilidad `R<n> → test` vive en `.harness/progress/`, nunca en el
  código: los tests se commitean y el harness no.
- Desactivar temporalmente: `touch .harness/.direct-edit` (y borrarlo).
- Desinstalar: borrar `.harness/` y `CLAUDE.local.md`, y sus líneas de
  `.git/info/exclude`.

## Desarrollo del plugin

```bash
bash tests/hooks.sh      # hooks: repo git temporal + fixtures JSON por stdin
bash tests/validator.sh  # FeatureListCheck.java: fixtures de feature-list, specs y reviews
bash tests/init.sh       # init.sh con comandos de build falsos
bash tests/profile.sh    # profile-facts.sh contra un repo fixture con hechos conocidos
```

Los tests cubren los scripts, no la configuración de `hooks.json` ni lo que
manda Claude Code: eso se prueba con una sesión real
(`claude -p --plugin-dir <este-directorio> ...` en un clon descartable).

## Estructura

```
java-harness-sdd/
├── .claude-plugin/        plugin.json, marketplace.json
├── agents/                spec-author, implementer, reviewer
├── hooks/                 hooks.json + scripts (bash puro)
├── skills/                install-harness, add-feature, spec, deliver
├── tests/                 hooks.sh, validator.sh, init.sh, profile.sh
└── template/              lo que se instala en el repo
    ├── CLAUDE.local.md    reglas duras y comandos (sin imports)
    └── .harness/
        ├── VERSION  AGENTS.md  CHECKPOINTS.md
        ├── harness.conf   init.sh
        ├── bin/           FeatureListCheck.java, fingerprint.sh, profile-facts.sh
        ├── feature-list.json
        ├── docs/          architecture (+ perfil), conventions, specs, verification
        ├── progress/      current, history
        └── specs/         <TICKET>/{approval,requirements,design,tasks}.md
```
