# Verificación — Cómo demostrar que el trabajo funciona

> Regla de oro: **el agente no dice "funciona", lo demuestra**. Toda
> feature termina con evidencia ejecutable.

## Dos niveles de verificación automática

| Comando | Qué corre | Cuándo |
|---|---|---|
| `bash .harness/init.sh` | Entorno + `feature-list.json` + **tests rápidos** (`FAST_TEST_CMD`: dominio, aplicación, ArchUnit) | Al arrancar. Los hooks corren los mismos tests rápidos al terminar el implementer, y al terminar cada respuesta del leader solo si hay una feature `in_progress` y cambió el código |
| `bash .harness/init.sh --full` | Lo anterior + **build completo** (`FULL_VERIFY_CMD`: todos los tests, incluidos Testcontainers) | Antes de pasar al reviewer y antes de marcar `done` |

Los comandos concretos de este repo están en `.harness/harness.conf`.
`--full` necesita Docker corriendo si el repo usa Testcontainers. Si Docker
no está disponible, el resultado es `blocked`, **no** "lo salteo".

## Qué test escribir según la capa

| Capa | Tipo de test | Herramientas | Regla |
|---|---|---|---|
| `domain/` | Unitario puro | JUnit 5 + AssertJ | Sin Spring, sin mocks. Invariantes del constructor: un caso válido y uno inválido por invariante. |
| `application/usecase` | Unitario | JUnit 5 + fakes de los `port/out` | Preferí **fakes** (implementaciones en memoria del puerto) a Mockito. Cubrí cada rama de falla de cada puerto. |
| `infra/adapters/in/web` | Slice o end-to-end | MockMvc / `@SpringBootTest` | Verificá status, body y headers reales; no solo "no lanza excepción". |
| `infra/adapters/out/<sistema>` HTTP | Integración | WireMock (o lo que use el repo) | Camino feliz + cada falla relevante: timeout, 4xx, 5xx, body malformado. |
| `infra/adapters/out/<sistema>` datos | Integración | Testcontainers con el motor real | **Nunca** H2 ni sustitutos en memoria para probar persistencia. |
| Migraciones | Integración | Testcontainers | La migración aplica sobre una base vacía y sobre el esquema anterior. |
| Arquitectura | ArchUnit | Tests existentes | No se modifican para que pase una feature. Si la feature introduce una capa o paquete nuevo, se agrega la regla correspondiente. |

Los tests viven en `src/test/java` **espejando el paquete** de la clase que
prueban. Reutilizá las clases de soporte y la clase base de contenedores
que ya tenga el repo (ver el perfil de `architecture.md`) en vez de crear
otras.

## Trazabilidad requirement ↔ test (features `sdd: true`)

Los tests se commitean con la feature y el harness no, así que **el código
de test no menciona ids `R<n>` ni nada del harness**. Un test se nombra por
el comportamiento que verifica, como cualquier otro test del repo. Las
claves de ticket en comentarios siguen la convención del repo.

La trazabilidad vive en `.harness/progress/impl-<TICKET>.md`, con
referencias `Clase#método` exactas:

```markdown
## Trazabilidad B2B-130
- R1 → PreAuthorizeEndToEndTest#createsPreAuthorization
- R2 → PreAuthorizeIdempotencyTest#conflictingReplayIsRejected
- R3 → RedisUnavailableTest#storeTimeoutReturns503
```

El reviewer verifica cada línea: que el método exista, que sea un `@Test`
que esté corriendo (no `@Disabled`) y que sus asserts comprueben de verdad
lo que dice el requirement — no alcanza con que el nombre suene parecido.

## Anti-patrones (el reviewer rechaza)

- ❌ "Agregué la clase, debería funcionar." → falta test ejecutable.
- ❌ Test que solo verifica que el contexto levanta o que no lanza
  excepción.
- ❌ Mockear la clase bajo prueba, o mockear el dominio.
- ❌ H2/embebidos en lugar del motor real para persistencia.
- ❌ `Thread.sleep` para esperar asincronía → usar el reloj inyectado o
  Awaitility si el repo ya lo tiene.
- ❌ `@Disabled` o borrar un test que falla.
- ❌ Modificar o relajar una regla ArchUnit para que pase la feature.
- ❌ Marcar `done` sin `init.sh --full` verde.

## Verificación manual (opcional, recomendada para endpoints)

Levantar el servicio con el perfil local y probar el endpoint con `curl`
contra el contrato. Anotá el comando y la respuesta en
`progress/impl-<TICKET>.md`.
