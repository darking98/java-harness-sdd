---
name: install-harness
description: Instala el harness SDD local (.harness/ + CLAUDE.local.md) en un servicio Java/Spring existente, lo excluye de git vía .git/info/exclude y genera el perfil del repo (build, paquetes hexagonales, ArchUnit, tests de integración) inspeccionando el código. No toca el código ni nada que se commitee.
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
---

# Instalar el harness en un servicio Java

Instalás el harness como **estado local**: todo queda en `.harness/` y
`CLAUDE.local.md`, excluidos vía `.git/info/exclude`. El repo del equipo no
cambia: ni código, ni `.gitignore`, ni `CLAUDE.md`, ni `README.md`.

## 1. Precondiciones (si alguna falla, parás sin escribir nada)

- El directorio actual es la raíz de un repo git:
  `[ -z "$(git rev-parse --show-prefix)" ]` (no compares `--show-toplevel`
  con `pwd`: en Git Bash uno da `C:/...` y el otro `/c/...`).
- Es un proyecto Java: existe `build.gradle`, `build.gradle.kts` o
  `pom.xml` en la raíz, y `src/main/java` en la raíz **o** en algún módulo
  declarado en `settings.gradle(.kts)` (`include(...)`) o en los
  `<modules>` del `pom.xml`.
- Si ya existe `.harness/`: no lo pisás. Decile al humano que el harness ya
  está instalado y ofrecé solo regenerar el perfil (paso 4) si lo pide.
- El plugin tiene que estar instalado con scope **user** o **local**. Con
  scope `project`, Claude Code lo registra en `.claude/settings.json`
  dentro del repo y eso aparece para commitear: si `git status` muestra
  `.claude/settings.json` modificado por el plugin, avisale al humano.

## 2. Copiar

Resolvé la carpeta del template. `${CLAUDE_PLUGIN_ROOT}` se sustituye en
el cuerpo de las skills de un plugin; si no estuviera, usá la ruta relativa
a esta skill. Verificá que exista antes de copiar:

```bash
TEMPLATE="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR}/../..}/template"
[ -f "$TEMPLATE/.harness/harness.conf" ] || { echo "No encuentro el template del plugin en $TEMPLATE"; exit 1; }
cp -R "$TEMPLATE/.harness" .harness
mkdir -p .harness/specs
```

Si el chequeo falla, parás y le decís al humano la ruta que probaste.

`CLAUDE.local.md`:

- Si no existe: copiá `$TEMPLATE/CLAUDE.local.md`.
- Si existe (son instrucciones personales del humano): mostrale el
  contenido del template y preguntale si lo agregás al final como sección
  `## Harness SDD`. Solo escribí si confirma. Si no confirma, anotalo
  para el resumen: las sesiones no van a conocer las reglas duras del
  harness fuera de sus comandos.
- Si existe y es de una versión anterior (importa `@.harness/LEADER.md`):
  mostrale la diferencia y proponé reemplazar esa sección por el template.
  El protocolo del leader ya no se importa en cada sesión: lo cargan
  `/java-harness-sdd:spec` y `/java-harness-sdd:deliver` al invocarlos.

## 3. Excluir de git (local, nunca `.gitignore`)

```bash
EXCLUDE="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$EXCLUDE")"
grep -qxF '.harness/' "$EXCLUDE" 2>/dev/null || printf '\n# java-harness-sdd (local, never committed)\n.harness/\n' >> "$EXCLUDE"
grep -qxF 'CLAUDE.local.md' "$EXCLUDE" 2>/dev/null || printf 'CLAUDE.local.md\n' >> "$EXCLUDE"
git check-ignore -q .harness && git check-ignore -q CLAUDE.local.md && echo excluded
```

Si `git check-ignore` no confirma ambos, parás y lo reportás: un harness que
puede terminar en un commit es peor que no tenerlo. Verificá además que
`git status --porcelain` no muestre nada de `.harness/` ni `CLAUDE.local.md`.

## 4. Generar el perfil del repo

El perfil es el contexto que leen todos los agentes: un error acá se
propaga a cada spec y a cada implementación. Por eso se arma en tres
pasos, y en ninguno se deduce algo que no se leyó.

### 4.1 Hechos (mecánico)

```bash
bash .harness/bin/profile-facts.sh > .harness/docs/profile-facts.md
```

Leelo entero. Es la fuente de verdad: qué contenedor levanta cada archivo,
quién extiende cada clase base, qué `@Bean`, `@Profile` y reglas ArchUnit
hay, qué tests no son puros. Lo que dice ahí **no** se reinterpreta a
partir de `build.gradle` ni de los comentarios.

### 4.2 Interpretación (vos), con fuente en cada línea

Completá **dos** archivos. Reglas:

- Cada afirmación sale de `profile-facts.md` o de un archivo que **abriste
  y leíste**, y lleva su fuente: `(fuente: <archivo>)`. Si no la podés
  citar, no la escribas.
- Una dependencia en el build **no** dice dónde se usa. Para saber qué
  levanta una clase, abrí la clase.
- Lo que hace una clase se lee en su **código**, no en su javadoc ni en su
  nombre. Si el comentario y el código difieren, manda el código, y vale la
  pena decirlo en el perfil.
- No generalices: "toda falla", "ningún controller", "siempre" solo si lo
  comprobaste en todos los casos. Si no, describí el patrón y sus
  excepciones.
- Nunca inventes: lo que no se puede determinar queda `<completar>` y va
  al resumen.

### `.harness/harness.conf`

| Variable | Cómo determinarla |
|---|---|
| `BUILD_TOOL` | `gradlew` en la raíz → `gradle`; `mvnw` → `maven`. |
| `JAVA_MIN_VERSION` | `toolchain { languageVersion = JavaLanguageVersion.of(N) }`, `sourceCompatibility`, `<maven.compiler.release>` o `.java-version`. |
| `FAST_TEST_CMD` | Ver abajo. |
| `FULL_VERIFY_CMD` | Lo que corre CI (`grep -rE 'gradlew|mvnw' .github/workflows`), si no `./gradlew build` / `./mvnw verify`. |
| `REQUIRES_DOCKER_FOR_FULL` | `true` si el build declara Testcontainers. |
| `BASE_BRANCH` | La rama contra la que van los PRs: las `branches` de `pull_request` en `.github/workflows/*.yml` y el README del repo. Si hay más de una (p. ej. `main` y `dev`), la de integración diaria; si no está claro, preguntale al humano. |
| `PROTECTED_PATHS` | El default. En multi-módulo, sumá `<modulo>/src` y los archivos de build de cada módulo: `git status -- src` solo mira la raíz, y el hook de verificación no detectaría cambios en los módulos. |

**`FAST_TEST_CMD`**: los tests de dominio, aplicación y arquitectura tienen
que ser puros. La sección "Pureza del filtro rápido" de
`profile-facts.md` lista los que no lo son; excluí del filtro cualquier
paquete que aparezca ahí y mencionalo en el resumen.

- Gradle, un módulo: `./gradlew test --tests '*.architecture.*' --tests '*.domain.*' --tests '*.application.*' -q`
- Gradle multi-módulo: `--tests` en la task `test` de la raíz se aplica a
  todos los módulos y falla con "No tests found" en los que no tienen tests
  que matcheen. Armá el comando con tasks por módulo, solo para los
  módulos que tienen esos paquetes: `./gradlew :core:test --tests '*.domain.*' :app:test --tests '*.architecture.*' -q`.
- Maven: `./mvnw -q test -Dtest='**/architecture/**,**/domain/**,**/application/**' -Dsurefire.failIfNoSpecifiedTests=false`

Probá el comando que armaste una vez antes de dejarlo.

### Perfil en `.harness/docs/architecture.md`

Reemplazá el bloque entre `<!-- PROFILE:START` y `<!-- PROFILE:END -->`.
El perfil no repite listas que ya están en `profile-facts.md`: dice qué
significan y cómo se usan. Cada línea con su `(fuente: ...)`:

- **Paquete base**: el de la clase `@SpringBootApplication`.
- **Build / Java / framework**: herramienta, versión de Java, versión de
  Spring Boot; módulos, si hay.
- **Adaptadores de entrada y salida**: un ítem por subpaquete real de
  `infra/adapters/in` y `infra/adapters/out` (o su equivalente), con qué
  hace según **sus clases leídas**, y si se activa condicionalmente
  (`@Profile`, `@ConditionalOn*`).
- **Persistencia**: motor, herramienta de migraciones, carpeta y cuántas
  migraciones hay, `ddl-auto`.
- **Reglas ejecutables**: ruta del test ArchUnit y una línea por regla.
- **Tests de integración**: **un ítem por contenedor y por stub**: qué
  imagen, qué clase lo levanta y qué tests la usan (clase base o propio).
  Después, la regla práctica para un test nuevo: qué clase extender o qué
  patrón copiar según lo que necesite (base de datos, Redis, Secrets
  Manager, un sistema HTTP externo).
- **Particularidades**: todo lo que el código hace distinto de los
  principios del documento (p. ej. casos de uso anotados con `@Service`,
  otro nombre de capa, puertos que no siguen la convención, claves de
  ticket en comentarios). Si la estructura **no** es hexagonal, decilo
  explícitamente acá y en el resumen: el reviewer necesita saberlo.

Completá también `project` y `description` de `.harness/feature-list.json`
(`rootProject.name` / `artifactId` y la primera línea del README).

### 4.3 Verificación independiente

Antes de mostrárselo al humano, lanzá **1 subagente `Explore` con
`model: "sonnet"`** (contexto limpio, solo lectura; comparar afirmaciones
contra archivos no necesita el modelo más caro) con este encargo: *"Verificá cada línea del bloque
PROFILE de `.harness/docs/architecture.md` contra el archivo que cita y
contra `.harness/docs/profile-facts.md`. Para cada línea: correcta,
incorrecta (qué dice el archivo) o sin fuente. Buscá también lo que
`profile-facts.md` muestra y el perfil omite o contradice. No edites
nada."*

Corregí cada línea que marque. No le pases tus conclusiones al verificador:
solo el encargo.

Si corregiste o agregaste líneas, lanzá **una** segunda verificación
acotada: solo esas líneas, con el mismo encargo y la lista de líneas a
revisar (sin decirle qué estaba mal antes). Revisar de nuevo el perfil
entero cuesta casi lo mismo que la primera pasada y no encuentra más. Si la
segunda todavía marca algo, corregilo y listalo en el resumen como
"corregido sin re-verificar": no lances una tercera.

## 5. Verificar

Corré `bash .harness/init.sh`. Tiene que terminar verde salvo por tests del
propio repo que ya estuvieran rotos — si es así, decilo, no lo arregles.

## 6. Resumen para el humano

1. Qué se instaló y que `git status` está limpio respecto del harness.
2. El perfil detectado (los valores de `harness.conf` y las líneas del
   perfil), para que lo confirme o corrija, y qué corrigió la verificación
   independiente.
3. Lo que quedó `<completar>` o se excluyó del filtro rápido, y por qué.
4. Si `CLAUDE.local.md` quedó sin instalar, que el harness está incompleto.
5. Próximos pasos:
   - `/clear`: esta sesión arrastra toda la instalación, y además no cargó
     `CLAUDE.local.md` (no existía al arrancar).
   - Cargar el primer ticket con `/java-harness-sdd:add-feature <TICKET>`.
   - `/java-harness-sdd:spec <TICKET>`: spec y resumen para aprobar.
   - Aprobar, `/clear` y `/java-harness-sdd:deliver <TICKET>`:
     implementación, review y cierre en automático.
   - Para trabajar sin el harness un rato: crear `.harness/.direct-edit`
     (y borrarlo después).
   - Para desinstalar: borrar `.harness/` y `CLAUDE.local.md`, y las líneas
     del harness en `.git/info/exclude`.

## Reglas duras

- ❌ Nunca escribas fuera de `.harness/`, `CLAUDE.local.md` y
  `.git/info/exclude`.
- ❌ Nunca uses `.gitignore`, `git add`, `git commit` ni `git update-index`.
- ❌ Nunca pises un `.harness/` o `CLAUDE.local.md` existente sin
  confirmación.
- ❌ Nunca inventes valores del perfil: lo que no se puede determinar queda
  `<completar>`.
