# Arquitectura — Qué significa "hacer un buen trabajo"

> Estándar contra el que el `reviewer` evalúa el código. Si no está acá ni
> en el código existente, no es un requisito.
>
> La primera sección es el **perfil de este repo**: la completa
> `/java-harness-sdd:install-harness` inspeccionando el código real. El
> resto son los principios hexagonales comunes a los servicios Java/Spring.
> Cuando el perfil y los principios difieren, **gana el perfil**: el
> harness se adapta al repo, no al revés.
>
> Los hechos crudos (paquetes y clases, contenedores por archivo, clases
> base y quién las extiende, `@Bean`, reglas ArchUnit) están en
> `profile-facts.md`, que se regenera con un script al empezar cada
> feature. **Si este perfil y `profile-facts.md` se contradicen, manda
> `profile-facts.md`**, y el perfil se corrige.

## Perfil de este repo

<!-- PROFILE:START — generado por install-harness; cada línea con su fuente -->
- **Paquete base:** `<completar>` (fuente: `<archivo>`)
- **Build:** `<gradle | maven>` — comandos en `.harness/harness.conf`
- **Java / framework:** `<versión de Java>` · `<Spring Boot x.y>` (fuente: `<archivo>`)
- **Adaptadores de entrada (`infra/adapters/in/`):** `<un ítem por subpaquete, con fuente>`
- **Adaptadores de salida (`infra/adapters/out/`):** `<un ítem por sistema externo, con fuente>`
- **Persistencia:** `<motor, migraciones, ddl-auto, con fuente>`
- **Reglas de arquitectura ejecutables:** `<ruta del test ArchUnit y qué reglas tiene>`
- **Tests de integración:** `<un ítem por contenedor o stub: imagen, quién lo levanta, quién lo usa; y qué extender para un test nuevo>`
- **Particularidades:** `<lo que se aparte de los principios de abajo, con fuente>`
<!-- PROFILE:END -->

## Capas y dirección de dependencias

```
infra (adapters in/out, config)  ──►  application (ports, use cases)  ──►  domain
```

Las dependencias apuntan **solo hacia adentro**. Si el repo tiene tests
ArchUnit, son la versión ejecutable de esta regla: una feature que los
rompe está mal diseñada, no se "arregla" relajando la regla.

| Paquete | Contiene | Puede depender de | No puede depender de |
|---|---|---|---|
| `domain/model` | Entidades, value objects (preferentemente `record`), invariantes validadas en el constructor | JDK | Spring, Jakarta, `application`, `infra` |
| `domain/exception` | Excepciones de negocio / categorías de falla | `domain` | Todo lo demás |
| `application/port/in` | Interfaces de casos de uso (`<Accion><Entidad>UseCase`) | `domain` | `infra` |
| `application/port/out` | Interfaces hacia afuera (`<Algo>Port` / `<Algo>Provider`) — siempre `interface` | `domain` | `infra` |
| `application/usecase` | Implementaciones de `port/in` (`<Accion><Entidad>Service`) y su configuración | `domain`, `application/port` | `infra`, clientes HTTP, repositorios JPA |
| `application/exception` | Fallas propias de la orquestación (conflictos, indisponibilidad de un puerto) | `domain` | `infra` |
| `infra/adapters/in/<canal>` | Controllers, DTOs de request/response, filtros, manejo de errores HTTP | `application/port/in`, `domain` | `infra/adapters/out` |
| `infra/adapters/out/<sistema>` | Un paquete por sistema externo; implementa un `port/out` | `application/port/out`, `domain` | `infra/adapters/in` |
| `infra/config` | Wiring de beans, `@ConfigurationProperties`, seguridad, observabilidad | Todo | — |

## Principios

1. **El dominio no sabe que existe Spring.** Sin anotaciones de framework
   en `domain/` ni en `application/`. Los casos de uso se instancian como
   beans desde `infra/config`, no con `@Service` en `application/` —
   salvo que el perfil diga que el repo lo hace distinto.
2. **Un sistema externo nuevo = un `port/out` + un paquete en
   `infra/adapters/out/<sistema>/`.** Nunca se llama a un cliente HTTP,
   SDK o repositorio desde un caso de uso.
3. **Los DTOs no cruzan la frontera.** El adaptador de entrada mapea
   request → modelo de dominio antes de llamar al `port/in`, y resultado →
   response al volver. El adaptador de salida mapea dominio ↔ formato
   externo. Ningún DTO llega a `application/` ni a `domain/`.
4. **Validación en los bordes.** Bean Validation (`@Valid`, constraints)
   en los DTOs de entrada; invariantes de negocio en los constructores del
   dominio. Ambas: una no reemplaza a la otra.
5. **Las fallas se modelan, no se filtran.** Los adaptadores traducen
   excepciones técnicas (timeouts, 5xx, errores de conexión) a excepciones
   de `domain/` o `application/`. Un único manejador en el adaptador de
   entrada las traduce a la respuesta HTTP. Nunca se expone un stack trace
   ni un mensaje de un sistema externo.
6. **Configuración externalizada.** Todo valor que cambia entre ambientes
   va en `application-<perfil>.yml` / variables de entorno, tipado con
   `@ConfigurationProperties` y validado al arrancar. El artefacto es el
   mismo en todos los ambientes.
7. **Sin dependencias ni capas nuevas sin justificar.** Toda dependencia
   nueva en `build.gradle`/`pom.xml` se justifica en el `design.md` del
   spec, con la alternativa descartada.

## Persistencia y migraciones

- El esquema evoluciona **solo** con migraciones versionadas (Flyway/
  Liquibase según el perfil). Una migración ya aplicada en algún ambiente
  **no se edita nunca**: se agrega una nueva.
- Las entidades de persistencia viven en el adaptador de salida, separadas
  del modelo de dominio. El adaptador mapea entre ambos.

## Qué NO hacer

- No poner lógica de negocio en controllers, filtros ni adaptadores de
  salida.
- No inyectar un adaptador concreto en un caso de uso: siempre el puerto.
- No relajar ni borrar reglas ArchUnit para que una feature pase.
- No agregar `@Transactional`, caché ni reintentos en `domain/`.
- No crear paquetes `utils`/`common`/`helpers` genéricos: lo compartido
  tiene un dueño y un nombre de dominio.
