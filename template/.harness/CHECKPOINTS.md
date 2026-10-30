# CHECKPOINTS — Evaluación del estado final

> En sistemas multi-agente no se evalúa el camino, se evalúa el destino.
>
> - **C1-C4 y C6** los recorre el `reviewer`: rechaza si queda alguno
>   vacío sin justificación en `progress/impl-<TICKET>.md`.
> - **C5** es el chequeo de cierre: lo recorre el `leader` después del
>   `APPROVED`, porque describe cosas que recién existen en el cierre.

## C1 — El harness está sano y fuera del repo

- [ ] `bash .harness/init.sh` termina con exit 0.
- [ ] El perfil de `docs/architecture.md` está completo (sin `<completar>`).
- [ ] `git status --porcelain --ignored -- .harness CLAUDE.local.md` los
      muestra como ignorados (`!!`), nunca como untracked (`??`) ni staged.
- [ ] Las líneas agregadas del diff de la feature no mencionan `.harness`,
      `CLAUDE.local.md` ni ids `R<n>` del spec.

## C2 — El estado es coherente

- [ ] Como mucho una feature en `in_progress`, con `base_commit`.
- [ ] La feature en curso tiene `spec_approved: true` (si es `sdd`).
- [ ] `progress/current.md` describe la feature en curso.
- [ ] La rama actual corresponde al ticket de la feature en curso.

## C3 — El código respeta la arquitectura hexagonal

- [ ] Los tests ArchUnit del repo pasan y **no fueron modificados para
      relajarse** (el diff sobre el test de arquitectura está vacío o solo
      agrega reglas).
- [ ] `domain/` y `application/` no importan Spring, Jakarta ni nada de
      `infra/`.
- [ ] Todo sistema externo nuevo entra por un `port/out` + un paquete en
      `infra/adapters/out/<sistema>/`.
- [ ] Ningún DTO de un adaptador llega a `application/` ni `domain/`.
- [ ] Sin dependencias nuevas en el build sin justificación en `design.md`.
- [ ] Sin `System.out`, `printStackTrace`, `catch` vacíos, `@Disabled`
      nuevos ni TODOs sin contexto.

## C4 — La verificación es real

- [ ] Cada clase nueva con lógica tiene test en el paquete espejo.
- [ ] Persistencia probada contra el motor real (Testcontainers), no H2.
- [ ] Cada adaptador de salida nuevo tiene tests de sus fallas (timeout,
      error del sistema externo), no solo del camino feliz.
- [ ] `bash .harness/init.sh --full` verde.

## C5 — Cierre (leader, después del APPROVED)

- [ ] La feature quedó en `done` y `init.sh` pasa (el validador exige el
      review APPROVED).
- [ ] `progress/history.md` tiene la entrada de la feature.
- [ ] `progress/current.md` volvió a la plantilla.
- [ ] Sin archivos temporales ni de debug sin trackear en el repo.
- [ ] El humano recibió la propuesta de commit; nada se commiteó por él.

## C6 — Spec Driven Development

- [ ] La feature `sdd` tiene `specs/<TICKET>/` con los 3 archivos y pasa el
      chequeo de consistencia de `init.sh`.
- [ ] `requirements.md` usa EARS estricto, con requirements "no deseados"
      para cada dependencia externa que toca la feature.
- [ ] Todas las tasks de `tasks.md` están `[x]` o justificadas.
- [ ] Cada `R<n>` está mapeado en `progress/impl-<TICKET>.md` a un test
      `Clase#método` que existe, corre y verifica ese comportamiento.
