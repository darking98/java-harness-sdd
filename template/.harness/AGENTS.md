# AGENTS.md — Mapa de navegación para agentes de IA

> Punto de entrada para cualquier agente que trabaje en este repositorio.
> NO es una biblia de reglas: es un **mapa**. Leé solo lo que necesites
> cuando lo necesites (divulgación progresiva).
>
> Todo el harness vive en `.harness/` y en `CLAUDE.local.md`. Ninguno de
> los dos se commitea: están listados en `.git/info/exclude`. El código del
> repo es del equipo; el harness es una herramienta local de quien lo usa.

---

## 1. Antes de empezar (obligatorio)

1. El leader y el implementer ejecutan `bash .harness/init.sh` y verifican
   que termina sin errores; si falla, **paran** y resuelven el entorno antes
   de tocar código (el leader tiene una excepción para retomar una feature
   cortada, ver la skill `deliver`). El spec-author no tiene Bash y lo omite.
2. Leé `.harness/progress/current.md` para entender en qué estado quedó la
   última sesión.
3. Leé `.harness/feature-list.json`. Cada feature es un ticket de Jira
   (`name` = clave del ticket, ej. `B2B-130`). Toda feature con
   `"sdd": true` pasa por **Spec Driven Development** — ver
   `.harness/docs/specs.md` y §4 de este archivo.

## 2. Mapa

| Archivo / carpeta | Qué contiene | Cuándo leerlo |
|---|---|---|
| `.harness/feature-list.json` | Tickets con estado (`pending` / `spec_ready` / `in_progress` / `done` / `blocked`) | Siempre, al empezar |
| `.harness/progress/current.md` | Estado de la feature en curso | Siempre, al empezar |
| `.harness/progress/history.md` | Bitácora append-only de features cerradas | Si necesitás contexto histórico |
| `.harness/specs/<TICKET>/` | `approval.md` (para aprobar) + `requirements.md` + `design.md` + `tasks.md` | Antes de implementar una feature `"sdd": true` |
| `.harness/docs/architecture.md` | Arquitectura hexagonal + **perfil de este repo** | Antes de diseñar o implementar |
| `.harness/docs/profile-facts.md` | Hechos del repo extraídos por script (clases por paquete, contenedores, clases base, `@Bean`, ArchUnit); mandan sobre el perfil | Antes de diseñar, implementar o revisar |
| `.harness/docs/conventions.md` | Nombres, estilo Java, errores, configuración | Antes de escribir código |
| `.harness/docs/specs.md` | Proceso SDD, estados, **quién escribe qué** | Antes de redactar o leer un spec |
| `.harness/docs/verification.md` | Niveles de test, trazabilidad `R<n>` ↔ test | Antes de dar algo por terminado |
| `.harness/CHECKPOINTS.md` | Criterios objetivos de "estado final correcto" | Para revisar / cerrar |
| `.harness/harness.conf` | Comandos de compilación y test de este repo | Si un comando de verificación falla raro |
| `src/**` | Código de aplicación y tests | Para implementar / verificar |

## 3. Reglas duras (no negociables)

- **Una sola feature a la vez.** No mezcles cambios de varios tickets en la
  misma sesión ni en la misma rama.
- **Nada se da por terminado sin verificación completa verde**
  (`bash .harness/init.sh --full`, el build entero con Testcontainers).
- **No saltes la fase de spec** ni la **puerta de aprobación humana**.
- **Cada rol escribe solo sus archivos** (tabla en `docs/specs.md`). El
  estado de `feature-list.json` lo cambia solo el leader.
- **Los commits son del humano.** Ningún agente commitea, stashea,
  pushea, crea ramas ni abre PRs. El leader propone un commit al cerrar;
  el humano decide.
- **El harness nunca entra en git.** Nadie hace `git add` de `.harness/` ni
  de `CLAUDE.local.md`, ni los menciona en código, commits o PRs.
- **Documentá lo que hacés** en `.harness/progress/current.md` mientras
  trabajás, no al final.
- **Si no sabés algo, buscalo en `.harness/docs/`** o en el código existente
  antes de inventarlo.

## 4. Flujo de trabajo (SDD)

```
pending → [spec-author] → spec_ready → ⏸ HUMANO (spec_approved=true) → in_progress → [implementer ⇄ reviewer] → cierre → done
```

El leader es la sesión principal, con el protocolo de la fase cargado por
su comando: `/java-harness-sdd:spec` (pasos 1-3) y, en otra sesión limpia,
`/java-harness-sdd:deliver` (pasos 4-7). Una feature `"sdd": false` salta
directo al paso 4.

1. El leader lanza al spec-author, que escribe `.harness/specs/<TICKET>/`
   y devuelve `spec_ready -> ...`. El leader cambia el estado y valida la
   consistencia del spec con `init.sh`.
2. El leader le muestra al humano `approval.md`.
3. **Pausa.** El humano aprueba o pide cambios. Al aprobar, el leader
   persiste `"spec_approved": true` de inmediato.
4. El leader registra `base_commit`, pasa a `in_progress` y lanza al
   implementer.
5. El implementer ejecuta `tasks.md` una a una, marcándolas `[x]`, corre
   `init.sh --full` y devuelve `done -> ...`.
6. El reviewer (solo lectura) revisa el diff contra `base_commit` y
   devuelve su veredicto; un hook lo guarda en
   `progress/review-<TICKET>.md`.
7. Si aprueba, el leader cierra: `done`, `history.md`, `current.md` en
   plantilla y una propuesta de commit para el humano.

## 5. Al terminar una sesión

1. `bash .harness/init.sh` en verde (y `--full` si se cerró una feature).
2. `progress/current.md` refleja dónde quedó la feature en curso. **No se
   vacía al cerrar la sesión**: se vacía solo en el cierre de la feature.
3. Sin archivos temporales, `System.out.println` de debug ni TODOs sin
   contexto.
4. `git status` no muestra nada de `.harness/` ni `CLAUDE.local.md`. Si
   aparecen, falta la entrada en `.git/info/exclude`.

## 6. Si te bloqueás

- Releé la sección relevante de `.harness/docs/`.
- Si una herramienta no hace lo que esperás, **no inventes un workaround**:
  dejá el motivo en tu archivo (`progress/spec-<TICKET>.md` o
  `progress/impl-<TICKET>.md`) y terminá con `blocked -> <archivo>`. El
  leader cambia el estado.
