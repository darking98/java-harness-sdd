# Changelog

## 0.4.2

### Corregido

- **El spec-author no podía escribir `summary.md`:** Claude Code no deja
  que un subagente escriba un archivo con ese nombre ("Subagents should
  return findings as text, not write report files"). El spec quedaba sin
  resumen y `spec_ready` no pasaba el validador. Ahora se llama
  `approval.md` (verificado: con ese nombre el subagente lo escribe). Cambian
  las skills, el spec-author, `docs/specs.md`, `AGENTS.md` y
  `bin/FeatureListCheck.java`.

## 0.4.1

Solo cambian skills: un harness 0.4.0 instalado sigue sirviendo (alcanza
con actualizar `.harness/VERSION`).

### Agregado

- `add-feature` lee el ticket con el CLI `twg` de Atlassian si está
  instalado, incluidas las páginas de Confluence que enlaza (donde suelen
  vivir la historia y los criterios). El login lo hace el humano con
  `! twg login`. Guarda el texto literal en
  `progress/research-<TICKET>.md`, que `spec` le pasa al spec-author.
  Sin `twg`, usa el conector de Atlassian o pide pegar el ticket.

## 0.4.0

El piloto de B2B-130 costó USD 22, y más de la mitad fue releer el contexto
de una sesión de leader que vivió toda la feature. Esta versión cambia la
estructura: cada fase arranca limpia y el estado vive en disco, como en el
harness de larga duración de Anthropic o el Task Runner de Kiro.

### Cambiado

- **Una sesión por fase, con su comando:**
  - `/java-harness-sdd:spec <TICKET>` termina en la aprobación del spec.
  - `/java-harness-sdd:deliver <TICKET>` hace en automático implementer,
    reviewer, una vuelta de cambios y el cierre, y retoma una entrega
    cortada.
  - Entre las dos va un `/clear`, en la pausa en la que el humano igual
    tiene que leer y decidir. «trabajá <TICKET>» deja de ser el punto de
    entrada.
- **Leader delgado:** pasa rutas y lee solo la línea de salida de cada
  subagente (y del review, solo la línea de veredicto). Al retomar se
  orienta con `git diff --stat` y las tasks sin marcar, no con la
  conversación. Si el hook no guarda el veredicto, lo detecta por la fecha
  del archivo.
- **`CLAUDE.local.md` sin imports:** ya no carga `LEADER.md` y `AGENTS.md`
  en cada sesión del repo. Quedan las reglas duras y los comandos; el
  protocolo lo carga cada skill al invocarla.
- **Spec breve:** regla de brevedad en `docs/specs.md` (cada cosa una vez,
  código referenciado y no copiado, secciones de `design.md` solo si
  aplican).
- `install-harness` y `add-feature` indican los comandos nuevos.

### Agregado

- `specs/<TICKET>/summary.md`: hasta 15 líneas con qué cambia, decisiones,
  riesgos, preguntas abiertas y tamaño. Es lo que se muestra para aprobar.
  El validador lo exige en `spec_ready`.
- `SessionStart` indica el comando para retomar una feature `in_progress`.
- `init.sh` falla si `CLAUDE.local.md` todavía importa `LEADER.md`.

### Quitado

- `.harness/LEADER.md`: su contenido está en las skills `spec` y `deliver`.

### Migración desde 0.3.x

Reinstalá el harness (`/java-harness-sdd:install-harness` sobre un repo sin
`.harness/`) o, para conservar el estado, reemplazá `CLAUDE.local.md` por el
del template, borrá `.harness/LEADER.md` y copiá `VERSION`,
`AGENTS.md`, `docs/specs.md`, `init.sh` y `bin/FeatureListCheck.java`.

## 0.3.0

Cambios surgidos del primer piloto real (B2B-130 en conecta-bank-transfer-gateway).

### Corregido

- **El veredicto del reviewer no se guardaba si el reviewer corría en segundo
  plano.** Un subagente en segundo plano entrega su resultado con la
  herramienta `SubagentHandback`, así que su último texto es una nota de
  progreso, no el veredicto. `persist-review.sh` ahora lo toma también de
  `PreToolUse` sobre `SubagentHandback` (en la entrega) y, en `SubagentStop`,
  del último `SubagentHandback` de su transcript (`agent_transcript_path`).
  Escribir dos veces el mismo veredicto ya no lo rota.

### Cambiado

- **Modelo por agente:** spec-author y reviewer fijos en `opus` (ya no
  heredan el de la sesión), implementer en `sonnet`. La investigación previa y
  la verificación de la instalación usan `Explore` con `sonnet`.
- **Leader con contexto corto:** lee estados y rutas, no specs ni
  investigaciones enteras; edita los archivos del harness con Edit/Write,
  nunca por Bash; recomienda `/clear` al dejar un spec listo, al persistir la
  aprobación y al cerrar una feature.
- **Investigación previa con reglas:** solo si falta información fuera del
  repo, preguntas cerradas, un `Explore` en `sonnet`, salida con fuentes y
  persistencia literal en `progress/research-<TICKET>.md`, que el leader le
  pasa al spec-author. Si el humano trae investigación propia, va al mismo
  archivo.
- **Review:** una vuelta de cambios incluida; la segunda la decide el humano.
- **`init.sh`:** la salida del build va a `.harness/.state/build-<modo>.log`.
  En verde imprime una línea; en rojo, las últimas 40.
- `install-harness` recomienda `/clear` al terminar.

### Agregado

- `BASE_BRANCH` en `harness.conf`: `init.sh` avisa si la rama tiene commits de
  `origin/<BASE_BRANCH>` sin incorporar, según el último fetch (no hace fetch).
  El leader se lo dice al humano antes de lanzar al spec-author o al
  implementer. `install-harness` lo detecta de los workflows y el README.
- Tests para el reviewer en segundo plano, la salida del build y la rama
  atrasada.

## 0.2.3

### Cambiado

- `install-harness`: la segunda verificación del perfil revisa solo las
  líneas corregidas o agregadas, y no hay tercera. Revisar de nuevo el
  perfil entero costaba casi lo mismo que la primera pasada sin encontrar
  más.
- Los agentes consultan `profile-facts.md` con grep cuando necesitan un
  dato, en vez de leerlo entero al arrancar.

### Agregado

- `profile-facts.sh` lista cada `SecurityFilterChain` con su `@Order`, su
  `securityMatcher` (o "sin securityMatcher: cubre todo lo demás"),
  `permitAll`, `anyRequest()` y `httpBasic`: era el dato que el perfil
  describía mal una y otra vez.

## 0.2.2

### Corregido

- El perfil del repo podía mezclar datos ciertos en una conclusión falsa
  (p. ej. atribuir a la clase base contenedores que levanta otro test),
  porque se escribía resumiendo dependencias del build en vez de leer las
  clases.

### Agregado

- `bin/profile-facts.sh`: extrae del código, con find/grep y citando el
  archivo de cada dato, los hechos que usa el perfil (paquetes y clases,
  imports de Spring en el núcleo, `@Bean`, `@Profile`, reglas ArchUnit,
  contenedores por archivo, clases base y quién las extiende, pureza del
  filtro rápido, migraciones). Salida determinista en
  `docs/profile-facts.md`, que **manda sobre el perfil** si se contradicen.
- `install-harness` arma el perfil en tres pasos: hechos, interpretación
  con fuente en cada línea, y verificación por un subagente `Explore` con
  contexto limpio.
- El leader regenera los hechos al empezar cada feature y actualiza el
  perfil si hubo un cambio estructural.
- `tests/profile.sh`.
- `install-harness`: lo que hace una clase se lee en su código, no en su javadoc; sin generalizaciones no comprobadas.

## 0.2.1

### Corregido

- **Autoaprobación:** el leader podía escribir `review-*.md`, y un reviewer
  que copiaba la línea de plantilla `APPROVED | CHANGES_REQUESTED` dejaba un
  `done` válido. Ahora solo el hook escribe el veredicto, solo para el
  ticket en curso y con exactamente una línea de veredicto bien formada; el
  validador aplica la misma regla. El ejemplo del reviewer ya no trae la
  línea ambigua.
- **El leader podía apagar el harness con Write:** crear `.direct-edit` o
  editar `harness.conf`, `init.sh`, `bin/` y `.state/`. El mensaje del guard
  además le sugería el atajo.
- **El guard se esquivaba con `..`** (`<repo>/foo/../src/...`,
  `.harness/specs/../../src/...`): las rutas se resuelven antes de decidir.
- El implementer podía escribir el `tasks.md` y el `impl-*.md` de cualquier
  ticket; ahora solo los del ticket en curso.
- `init.sh` salteaba el build si fallaba el validador por otra feature;
  ahora solo lo saltea un error de entorno.
- El leader no podía retomar una feature cortada: el rojo de los tests lo
  frenaba antes del Caso D.
- `blocked` era un estado sin salida: ahora guarda `blocked_from` y existe
  el Caso E.
- Si el implementer terminaba con el código roto, el `Stop` del leader
  nunca avisaba.
- Validador: un `Criterio:` bajo otro encabezado contaba como cobertura;
  una `T<n>` duplicada pisaba a la anterior; `Cubre: R1 y R2` tomaba solo
  `R1`.
- Los hooks seguían corriendo si `bin/fingerprint.sh` venía trackeado.

### Cambiado

- El reviewer verifica que `base_commit` siga siendo ancestro de `HEAD`
  antes de diffear (rebase o amend).
- El spec-author también corrige specs en `spec_ready` cuando el leader lo
  relanza.
- Docs alineados: claves de ticket en tests, quién corre `init.sh`, orden
  de `spec_ready` y validación, cuándo verifica el `Stop`.

### Agregado

- `FeatureListCheck.java --current <harnessDir>`: la feature en curso,
  para los hooks.
- `tests/validator.sh` y `tests/init.sh`; casos nuevos en `tests/hooks.sh`.

## 0.2.0

### Corregido

- La verificación al terminar el implementer nunca corría: el matcher de
  `SubagentStop` era `implementer` y el `agent_type` real es
  `java-harness-sdd:implementer`.
- `install-harness` abortaba en Git Bash (comparaba `C:/...` con `/c/...`).
- El guard no reconocía rutas de Windows con otras mayúsculas.
- El checkpoint C5 no se podía cumplir durante el review.
- `current.md` se vaciaba en cada cierre de sesión y el leader no podía
  retomar una feature cortada.

### Cambiado

- **El reviewer es de solo lectura** y devuelve su veredicto como respuesta
  final; el hook `persist-review.sh` lo guarda literal en
  `progress/review-<TICKET>.md`.
- **El leader es el único que escribe `feature-list.json`** y hace el
  cierre de la feature (`done`, `history.md`, propuesta de commit). Los
  subagentes reportan con su línea de salida.
- El guard aplica permisos de escritura por rol también dentro de
  `.harness/`, y compara rutas relativas al proyecto.
- `PROTECTED_PATHS` cubre `src` entero, `buildSrc`, `gradle/`,
  `gradle.properties` y `.mvn`.
- El reviewer diffea contra `base_commit` (registrado al pasar a
  `in_progress`) y busca rastros del harness solo en las líneas agregadas.
  Las claves de ticket en comentarios dejan de considerarse rastro.
- `Stop` solo verifica con una feature en curso y avisa una vez por estado
  roto; `SubagentStop` da hasta 3 intentos al implementer.
- Se quitó el bloque `rules` de `feature-list.json`.

### Agregado

- Validaciones: `sdd` obligatorio, aprobación imposible en `pending`,
  `base_commit` en `in_progress`/`done`, review APPROVED para `done`, y
  consistencia del spec (`Criterio: A<k>` en requirements, `Cubre: R<n>` en
  tasks).
- Los hooks no ejecutan un `.harness/harness.conf` trackeado por git.
- `VERSION` en el template y hook `SessionStart` que avisa si difiere del
  plugin.
- `init.sh` verifica el import de `CLAUDE.local.md` y comparte el
  fingerprint con los hooks (`bin/fingerprint.sh`).
- `tests/hooks.sh`.

## 0.1.0

- Versión inicial.
