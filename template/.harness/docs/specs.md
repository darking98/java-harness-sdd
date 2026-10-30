# Spec Driven Development (SDD)

> Flujo Kiro-style: requirements → design → tasks → code. El código no se
> escribe hasta que un humano aprueba el spec.

## Estructura

Cada feature con `"sdd": true` en `.harness/feature-list.json` tiene su
carpeta en cuanto deja `pending`:

```
.harness/specs/<TICKET>/
├── approval.md        # PARA APROBAR (≤ 15 líneas)
├── requirements.md   # QUÉ (EARS)
├── design.md         # CÓMO (decisiones técnicas)
└── tasks.md          # PASOS (checklist)
```

`<TICKET>` es el `name` de la feature: la clave de Jira (`B2B-130`).

## Brevedad (regla dura)

Un spec largo no es más seguro: es más caro de escribir, de aprobar y de
releer en cada fase, y el humano termina aprobándolo sin leerlo. La
crítica habitual a SDD (Böckeler, Thoughtworks) es justamente esa.

- Cada cosa se dice **una vez**, en el archivo que le corresponde: el
  comportamiento en `requirements.md`, el cómo en `design.md`, el orden en
  `tasks.md`. No se repite el ticket ni el contexto del repo.
- No se copia código del repo: se referencia (`PreAuthorizeController.java:42`).
- `design.md` lleva solo las secciones que aplican. Una sección sin
  cambios es una línea ("Persistencia: ninguna"), no un párrafo.
- Un `R<n>` por comportamiento verificable. Si dos requirements los cubre
  el mismo test con el mismo setup, probablemente son uno.

## approval.md — lo que lee el humano para aprobar

Máximo 15 líneas, sin repetir el spec:

```markdown
# <TICKET> — <título>

**Qué cambia:** <1-2 líneas, en términos del comportamiento>
**Diseño:** <las 2-4 decisiones que importan, con la alternativa descartada>
**Riesgos:** <lo que puede salir mal o roza la arquitectura; "ninguno" si no hay>
**Para decidir:** <preguntas abiertas que bloquean la aprobación; "nada" si no hay>
**Supuestos:** <lo que no sabía y asumió: "sin el contrato, asumí X"; "ninguno" si no hay>
**Tamaño:** <n> requirements, <m> tasks, <archivos aprox.>
```

"Para decidir" incluye, sí o sí, todo punto del alcance del ticket (o de
`research-<TICKET>.md`) que el spec no cubre: dejar algo afuera es una
decisión del humano, no del spec-author.

El validador exige que exista mientras la feature está en `spec_ready`.

No se llama `summary.md` a propósito: Claude Code no deja que un subagente
escriba un archivo con ese nombre ("Subagents should return findings as
text, not write report files"), y el spec-author es un subagente.

## Estados

Todas las transiciones las aplica el **leader**, que es el único que
escribe `feature-list.json`. Los subagentes reportan con su línea de
salida y el leader cambia el estado.

| Estado | Significado | Lo aplica el leader cuando… |
|---|---|---|
| `pending` | Sin spec. | carga el ticket (`add-feature`) |
| `spec_ready` | Spec redactado, esperando al humano. No se toca código. | el spec-author devuelve `spec_ready -> ...`; recién después corre `init.sh`, porque el validador solo mira specs en `spec_ready` o más. Si falla, el spec vuelve al spec-author |
| `in_progress` | Spec aprobado. Trabaja el implementer. | el humano aprobó: setea `spec_approved: true`, `base_commit` y el estado |
| `done` | Verificación completa verde, reviewer aprobó, cierre hecho. | `progress/review-<TICKET>.md` tiene **exactamente una** línea `**Veredicto:** APPROVED` (el validador lo exige) |
| `blocked` | Atascado. | un subagente devuelve `blocked -> <archivo>`; guarda el estado anterior en `blocked_from` |

Campos de cada feature:

| Campo | Quién lo escribe | Regla |
|---|---|---|
| `name`, `title`, `description`, `acceptance`, `notes`, `sdd` | leader (`add-feature`) | `acceptance` se copia del ticket; su orden define `A1`, `A2`, ... |
| `status` | leader | según la tabla de arriba |
| `spec_approved` | leader | solo `true` tras el "aprobado" del humano; vuelve a `false` si el spec cambia |
| `base_commit` | leader | `git rev-parse HEAD` al pasar a `in_progress`; el reviewer diffea contra él |
| `blocked_from` | leader | solo en `blocked`: el estado al que se vuelve al destrabar (`pending`, `spec_ready` o `in_progress`); se borra al salir de `blocked` |

## Quién escribe qué

El hook `guard-app-code.sh` hace cumplir esta tabla para Write/Edit. Lo que
haga un agente por Bash no lo ve: ahí rige la regla escrita.

| Archivo | leader | spec-author | implementer | reviewer |
|---|---|---|---|---|
| Código (`PROTECTED_PATHS`) | ❌ | ❌ | ✅ con feature `in_progress` | ❌ |
| `feature-list.json`, `progress/history.md` | ✅ | ❌ | ❌ | ❌ |
| `specs/<TICKET>/approval.md`, `requirements.md`, `design.md` | ✅ | ✅ | ❌ | ❌ |
| `specs/<TICKET>/tasks.md` | ✅ | ✅ | ✅ solo el del ticket en curso, y solo marcar `[x]` | ❌ |
| `progress/research-<TICKET>.md` (investigación previa, literal y con fuentes) | ✅ | ❌ (la lee) | ❌ | ❌ |
| `progress/spec-<TICKET>.md` (bloqueos y preguntas del spec-author) | ✅ | ✅ | ❌ | ❌ |
| `progress/current.md` | ✅ | ❌ | ✅ | ❌ |
| `progress/impl-<TICKET>.md` | ✅ | ❌ | ✅ solo el del ticket en curso | ❌ |
| `progress/review-<TICKET>.md` | ❌ | ❌ | ❌ | lo escribe el hook `persist-review.sh` con su veredicto literal (respuesta final o `SubagentHandback`, si corre en segundo plano) |
| `harness.conf` | ✅ solo sin feature en curso | ❌ | ❌ | ❌ |
| `.direct-edit`, `init.sh`, `bin/`, `.state/` | ❌ (solo el humano) | ❌ | ❌ | ❌ |

El reviewer es de solo lectura, como es estándar para un revisor: no tiene
Write ni Edit, devuelve el veredicto como respuesta final y el hook lo
guarda sin intermediarios, solo si es el ticket en curso y tiene una sola
línea de veredicto bien formada. Si el archivo no aparece, el leader
relanza al reviewer; nunca lo escribe él.

## La puerta de aprobación humana

El flujo se detiene **una vez**: cuando la feature queda en `spec_ready`.
El humano lee `approval.md` (y el resto del spec si algo le hace ruido) y
dice "aprobado" o pide cambios. Es el corte entre las dos sesiones: la de
`/java-harness-sdd:spec` termina acá y la de `/java-harness-sdd:deliver`
arranca limpia, con todo el estado en disco.

### Persistencia de la aprobación

La aprobación nunca vive solo en el chat. Cuando el humano dice
"aprobado", el leader setea `"spec_approved": true` **antes de cualquier
otra cosa**. `init.sh` falla si una feature `sdd` está en `in_progress` o
`done` sin ese campo, o si una `pending` lo tiene en `true`.

Si el spec cambia después de aprobado (por pedido del humano o porque el
implementer encontró un hueco), `spec_approved` vuelve a `false` y la
feature a `spec_ready`.

## Fuente de los requirements

El `acceptance` de la feature se copia de los criterios de aceptación del
ticket de Jira, en orden: el primero es `A1`, el segundo `A2`. El
spec-author **no inventa** requirements que el ticket no soporta: si el
ticket es ambiguo, escribe las preguntas en `progress/spec-<TICKET>.md` y
devuelve `blocked`.

## requirements.md — EARS estricto

| Patrón | Plantilla |
|---|---|
| **Ubicuo** | `El sistema DEBE <acción>.` |
| **Evento** | `CUANDO <disparador>, el sistema DEBE <acción>.` |
| **Estado** | `MIENTRAS <estado>, el sistema DEBE <acción>.` |
| **Opcional** | `DONDE <feature opcional>, el sistema DEBE <acción>.` |
| **No deseado** | `SI <evento no deseado> ENTONCES el sistema DEBE <acción>.` |

Reglas:

- Encabezado `## R<n>` por requirement, con id estable. No se renumera: si
  se borra uno, su número queda libre.
- Debajo del texto, una línea `Criterio: A<k>` con los criterios de
  aceptación que cubre. Los requirements "no deseados" que no salen de un
  criterio explícito se atan al criterio cuyo comportamiento protegen.
- Un solo `DEBE` por requirement. Si hay más, se parte.
- Sin verbos blandos ("podría", "soporta"). Solo `DEBE` / `NO DEBE`.
- Cada requirement es verificable por al menos un test concreto.
- En un servicio, los requirements "no deseados" son la mitad del trabajo:
  timeouts, indisponibilidad de cada dependencia, reintentos, duplicados,
  input inválido. Cubrilos explícitamente.

Ejemplo:

```markdown
## R1
CUANDO llega un POST /v2/transfer/pre-authorize válido con un
Idempotency-Key no visto, el sistema DEBE responder 201 con el resultado
de la preautorización.
Criterio: A1

## R2
SI llega un segundo request con el mismo Idempotency-Key y un body
distinto ENTONCES el sistema DEBE responder 409 sin invocar al validador.
Criterio: A2

## R3
SI el almacén de idempotencia no responde dentro del timeout configurado
ENTONCES el sistema DEBE responder 503 con categoría de falla
`DEPENDENCY_UNAVAILABLE`.
Criterio: A2
```

## design.md — decisiones técnicas

Captura **antes** de tocar código, una sección por punto que aplique (los
que no, en una línea: "Persistencia: ninguna"):

- **Capas afectadas**: qué clases nuevas o modificadas hay en `domain/`,
  `application/port/in|out`, `application/usecase`, `infra/adapters/in|out`,
  `infra/config`. Con paquete completo.
- **Firmas nuevas**: puertos (interfaces), casos de uso, records de
  dominio, endpoints (método + path + status codes).
- **Fallas**: qué excepciones se reutilizan o se agregan y a qué respuesta
  HTTP / categoría se traducen.
- **Configuración**: propiedades nuevas y en qué perfiles.
- **Persistencia**: migraciones nuevas (nombre del archivo) o "ninguna".
- **Dependencias nuevas**: cuál y por qué, o "ninguna".
- **Documentación**: qué hay que actualizar en el repo (README, contrato
  de la API, ejemplos de configuración) y una task que lo haga, o
  "ninguna".
- **Alternativa descartada** y por qué (mínimo una).
- **Impacto en ArchUnit**: "ninguno" o qué regla nueva conviene agregar.

No es ingeniería desde cero: se apoya en `architecture.md`,
`conventions.md` y en las clases vecinas. El design documenta dónde la
feature roza esas reglas.

## tasks.md — checklist ejecutable

Pasos discretos, en orden **de adentro hacia afuera** (dominio → puertos →
caso de uso → adaptadores → config → tests de integración). Cada task es un
ítem `- [ ] T<n>` con `Cubre: R<n>` y lleva su test. El formato canónico
separa con comas (`Cubre: R1, R2`); el validador también acepta `y` y `/`. Si un ítem ocupa
varias líneas, van seguidas, sin línea en blanco en el medio.

```markdown
- [ ] T1 — `domain/model/IdempotencyRecord` (record + invariantes) y su test unitario. Cubre: R2.
- [ ] T2 — `application/port/out/IdempotencyStorePort` (interface). Cubre: R2, R3.
- [ ] T3 — Lógica de conflicto en `PreAuthorizeTransferService` + test unitario con un fake del puerto. Cubre: R2.
- [ ] T4 — `infra/adapters/out/redis/RedisIdempotencyStore` + test con Testcontainers. Cubre: R2, R3.
- [ ] T5 — Traducción de la falla a 503 en el manejador HTTP + test MockMvc. Cubre: R3.
- [ ] T6 — Test end-to-end del endpoint. Cubre: R1, R2.
```

El implementer marca `[x]` al completar cada una. El reviewer rechaza si
queda alguna `[ ]` sin justificación en `progress/impl-<TICKET>.md`.

## Consistencia del spec (chequeo mecánico)

`init.sh` valida todo spec en `spec_ready` o más (el "analyze" de Spec Kit):

- cada criterio `A1..An` del `acceptance` está cubierto por algún `R<n>`;
- cada `R<n>` tiene su línea `Criterio:` y referencia criterios que existen;
- cada task tiene `Cubre:` y solo referencia requirements que existen;
- cada `R<n>` está cubierto por alguna task.

El leader corre `init.sh` antes de pedirle la aprobación al humano: un spec
inconsistente vuelve al spec-author, no llega a la puerta.

## Trazabilidad (regla dura)

- Cada `R<n>` tiene al menos un test concreto, y cada test nuevo cubre al
  menos un `R<n>`.
- El vínculo vive en `progress/impl-<TICKET>.md` (`R<n> → Clase#método`),
  **nunca en el código**: ni ids `R<n>` en nombres, `@DisplayName` o
  comentarios de tests (ver `verification.md`).

## Commits

Ningún agente commitea, pushea, stashea ni crea ramas. El humano decide
qué entra en cada commit y cuándo. Al cerrar una feature, el leader le
deja una **propuesta**: archivos del cambio y un mensaje con la convención
del repo (ver el cierre de la skill `deliver`). Commitear o no es decisión
del humano.

## Cuándo NO aplica SDD

Features con `"sdd": false`: bumps de dependencias, cambios de
configuración, fixes de una línea con su test. Van directo a
`/java-harness-sdd:deliver`, con el `acceptance` como contrato. Igual pasan
por el reviewer.
