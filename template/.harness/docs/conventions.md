# Convenciones de código

> Homogeneidad extrema: la IA predice mejor cuando el repo se parece a sí
> mismo en todas partes. **La primera fuente de verdad es el código
> existente**: antes de escribir una clase, mirá dos o tres vecinas del
> mismo paquete y copiá su forma. Esto documenta lo que hay que mantener.
>
> Para dónde vive cada cosa, ver `architecture.md`.

## Idioma

- **Código, identificadores, comentarios, logs y mensajes de error de la
  API: inglés.**
- Specs, docs del harness y descripciones de PR: español.
- Los nombres de dominio usan el vocabulario del negocio en inglés tal como
  ya aparece en el código (no traducir de nuevo algo que ya tiene nombre).

## Nombres

| Tipo | Convención | Ejemplo |
|---|---|---|
| Puerto de entrada | `<Accion><Entidad>UseCase` | `PreAuthorizeTransferUseCase` |
| Implementación del caso de uso | `<Accion><Entidad>Service` | `PreAuthorizeTransferService` |
| Puerto de salida | `<Capacidad>Port` o `<Recurso>Provider` | `IdempotencyStorePort` |
| Adaptador de salida | `<Tecnologia><Capacidad>Adapter` / `<Sistema><Rol>Client` | `SecretsManagerCredentialsAdapter` |
| Controller | `<Accion>Controller` | `PreAuthorizeController` |
| DTOs | `<Accion>Request` / `<Accion>Response` en `.../dto/` | `PreAuthorizeRequest` |
| Excepciones | `<Situacion>Exception` | `CredentialsUnavailableException` |
| Propiedades tipadas | `<Area>Properties` | `CredicomerProperties` |
| Tests | `<ClaseProbada>Test`; los de escenario, `<Escenario>Test` | `RedisUnavailableTest` |
| Paquetes | minúscula, una palabra por nivel | `infra.adapters.out.credicomer` |
| Constantes | `UPPER_SNAKE` | `DEFAULT_TIMEOUT` |

Si el repo ya usa otra convención para alguno de estos casos, gana el repo
y se anota en el perfil de `architecture.md`.

## Estilo Java

- **`record`** para value objects, DTOs, comandos y resultados. Las
  invariantes se validan en el constructor compacto.
- **Inmutabilidad por defecto**: campos `final`, colecciones copiadas
  (`List.copyOf`) al construir.
- **Sin `null` como valor de negocio**: `Optional` en retornos que pueden
  no tener valor; nunca `Optional` como parámetro ni como campo.
- **Inyección por constructor**, nunca `@Autowired` en campos.
- **Sin Lombok** salvo que el repo ya lo use.
- **Tiempo**: inyectar `Clock`; nada de `Instant.now()` / `LocalDateTime.now()`
  directo en lógica testeable.
- **Formato**: el del repo (`.editorconfig` si existe). No reformatear
  archivos que no tocás.

## Errores

- Las excepciones de negocio extienden `RuntimeException` y llevan un
  mensaje sin datos sensibles (sin credenciales, tokens ni payloads
  completos).
- Si el repo modela categorías de falla (p. ej. un enum de categoría que
  el manejador HTTP traduce a status), toda excepción nueva declara su
  categoría en vez de agregar un `catch` nuevo en el manejador.
- Nunca `catch (Exception e)` para tragar el error. Si se captura, se
  traduce o se relanza con causa.

## Logs y observabilidad

- Logs estructurados con el logger del repo; sin `System.out.println`.
- Nunca se loguean secretos, credenciales, tokens ni datos personales
  completos.
- Métricas y spans: seguí la política del repo (cardinalidad acotada en
  tags — nada de IDs de transacción como tag).

## Comentarios

Por defecto no se escriben. Cuando hay uno, explica un **por qué** no
obvio (una restricción de un sistema externo, una decisión con ticket,
una versión mínima por un bug): el estilo de los comentarios que ya hay en
`build.gradle` o en el código es la referencia.

## Configuración

- Valores por ambiente en `application-<perfil>.yml`; secretos solo por
  variable de entorno o gestor de secretos, nunca en el repo.
- Toda propiedad nueva se documenta en el README del repo **solo si el
  ticket lo pide** — el harness no edita el README del equipo por su
  cuenta.
