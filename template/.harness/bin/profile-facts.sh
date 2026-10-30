#!/usr/bin/env bash
# profile-facts.sh — deterministic facts about the repo, for the architecture profile.
#
#   bash .harness/bin/profile-facts.sh > .harness/docs/profile-facts.md
#
# Everything here is read from the code with find/grep, never inferred, and every
# fact names the file it comes from. The narrative profile in architecture.md is
# written from this output; init.sh regenerates it and warns when the repo has
# drifted from what the profile describes. Output is sorted and has no timestamps,
# so two runs over the same code are byte-identical.
set -u
export LC_ALL=C

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_DIR/.." || exit 1

PRUNE=(-path ./.git -o -path ./.harness -o -path '*/build' -o -path '*/target' -o -path '*/node_modules' -o -path '*/.gradle')

java_files() { # dir...
  find "$@" \( "${PRUNE[@]}" \) -prune -o -type f -name '*.java' -print 2>/dev/null | sed 's#^\./##' | sort
}

list_or_none() { # reads lines on stdin
  local any=0 line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf -- '- %s\n' "$line"
    any=1
  done
  [ "$any" -eq 1 ] || echo "- ninguno"
}

MODULES=$(find . \( "${PRUNE[@]}" \) -prune -o -type d -path '*/src/main/java' -print 2>/dev/null | sed 's#^\./##; s#/\{0,1\}src/main/java$##' | sort)
BUILD_FILES=$(ls build.gradle build.gradle.kts pom.xml settings.gradle settings.gradle.kts 2>/dev/null)

echo "# Hechos del repo"
echo ""
echo "> Generado por \`.harness/bin/profile-facts.sh\`. No se edita a mano: se"
echo "> regenera. Cada hecho cita el archivo del que sale. El perfil de"
echo "> \`architecture.md\` se escribe a partir de esto."
echo ""

echo "## Build"
echo ""
{
  [ -f gradlew ] && echo "wrapper: \`gradlew\`"
  [ -f mvnw ] && echo "wrapper: \`mvnw\`"
  [ -f .java-version ] && echo "Java $(tr -d '[:space:]' <.java-version) (fuente: \`.java-version\`)"
  for f in $BUILD_FILES; do
    grep -oE 'JavaLanguageVersion\.of\([0-9]+\)' "$f" | sed -E "s/.*\(([0-9]+)\)/Java toolchain \1 (fuente: \`$f\`)/"
    grep -oE '<(maven\.compiler\.release|java\.version)>[0-9]+<' "$f" | sed -E "s#<([^>]+)>([0-9]+)<#Java \2 vía \1 (fuente: \`$f\`)#"
    grep -oE "org\.springframework\.boot['\"]?\)? version ['\"][^'\"]+['\"]" "$f" | sed -E "s/.*version ['\"]([^'\"]+)['\"]/Spring Boot \1 (fuente: \`$f\`)/"
    grep -A2 'spring-boot-starter-parent' "$f" 2>/dev/null | grep -oE '<version>[^<]+' | sed -E "s#<version>#Spring Boot #; s#\$# (fuente: \`$f\`)#"
    grep -oE "include[[:space:](]+['\"][^'\"]+['\"]" "$f" | sed -E "s/.*['\"]([^'\"]+)['\"]/módulo Gradle \1 (fuente: \`$f\`)/"
    grep -oE '<module>[^<]+' "$f" | sed -E "s#<module>#módulo Maven #; s#\$# (fuente: \`$f\`)#"
  done
} | sort -u | list_or_none
echo ""
echo "Raíces de código (\`src/main/java\`):"
echo ""
printf '%s\n' "$MODULES" | sed 's#^$#(raíz del repo)#' | list_or_none
echo ""

echo "### Dependencias de test"
echo ""
for f in $BUILD_FILES; do
  grep -E "testImplementation|testRuntimeOnly" "$f" | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"" | sed "s#\$# (\`$f\`)#"
  grep -B3 '<scope>test</scope>' "$f" 2>/dev/null | grep -oE '<artifactId>[^<]+' | sed "s#<artifactId>##; s#\$# (\`$f\`)#"
done | sort -u | list_or_none
echo ""

MAIN_JAVA=$(java_files $(printf '%s\n' "$MODULES" | sed 's#$#/src/main/java#; s#^/##'))
TEST_JAVA=$(java_files $(printf '%s\n' "$MODULES" | sed 's#$#/src/test/java#; s#^/##'))

echo "## Paquetes de \`src/main/java\`"
echo ""
APP=$(printf '%s\n' "$MAIN_JAVA" | xargs grep -l '@SpringBootApplication' 2>/dev/null | sort)
echo "Clase \`@SpringBootApplication\`:"
echo ""
printf '%s\n' "$APP" | list_or_none
echo ""
echo "Clases por paquete (relativo a \`src/main/java\`):"
echo ""
printf '%s\n' "$MAIN_JAVA" | sed -E 's#^(.*/)?src/main/java/##' | awk -F/ '
  NF > 1 {
    pkg = $1; for (i = 2; i < NF; i++) pkg = pkg "." $i
    cls = $NF; sub(/\.java$/, "", cls)
    list[pkg] = (pkg in list) ? list[pkg] ", " cls : cls
  }
  END { for (p in list) print "`" p "`: " list[p] }' | sort | list_or_none
echo ""

echo "## Frontera hexagonal"
echo ""
echo "Imports de Spring o Jakarta en \`domain/\` y \`application/\`:"
echo ""
printf '%s\n' "$MAIN_JAVA" | grep -E '/(domain|application)/' | xargs grep -nE '^import (org\.springframework|jakarta)\.' 2>/dev/null | list_or_none
echo ""
echo "Métodos \`@Bean\` (archivo:línea → tipo y nombre):"
echo ""
# Only a line that starts with @Bean is the annotation (not a mention in a comment);
# the signature is the first following line that is not another annotation or comment.
printf '%s\n' "$MAIN_JAVA" | xargs awk '
  /^[[:space:]]*@Bean([[:space:](]|$)/ { want = 1; at = FNR; next }
  want && /^[[:space:]]*(@|\/\/|\/\*|\*)/ { next }
  want && NF {
    sig = $0
    sub(/\(.*/, "", sig)
    sub(/^[[:space:]]+/, "", sig)
    while (sig ~ /^(public|protected|private|static|final)[[:space:]]/) sub(/^[a-z]+[[:space:]]+/, "", sig)
    print FILENAME ":" at " → " sig "()"
    want = 0
  }' 2>/dev/null | sort | list_or_none
echo ""
echo "Activación condicional (\`@Profile\`, \`@ConditionalOn*\`):"
echo ""
printf '%s\n' "$MAIN_JAVA" | xargs grep -nE '^[[:space:]]*@(Profile|ConditionalOn[A-Za-z]*)\(' 2>/dev/null | sed -E 's#:[[:space:]]+#: #' | list_or_none
echo ""
echo "Cadenas de seguridad (\`SecurityFilterChain\`):"
echo ""
# A chain without securityMatcher catches every request the earlier chains did not:
# that is easy to misread as "just actuator", so it is stated here as a fact.
printf '%s\n' "$MAIN_JAVA" | xargs grep -l 'SecurityFilterChain' 2>/dev/null | xargs awk '
  function flush() {
    if (name == "") return
    scope = (matcher != "") ? "securityMatcher(" matcher ")" : "sin securityMatcher: cubre todo request que no tomó una cadena anterior"
    out = file ":" at " " name "()"
    if (ord != "") out = out " @Order(" ord ")"
    out = out " → " scope
    if (permit != "") out = out "; permitAll: " permit
    if (anyreq != "") out = out "; anyRequest()." anyreq
    out = out "; httpBasic: " basic
    print out
    name = ""
  }
  FNR == 1 { flush(); order = "" }
  /@Order\(/ { o = $0; sub(/.*@Order\(/, "", o); sub(/\).*/, "", o); order = o }
  /SecurityFilterChain[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(/ {
    flush()
    n = $0; sub(/.*SecurityFilterChain[[:space:]]+/, "", n); sub(/[[:space:]]*\(.*/, "", n)
    name = n; file = FILENAME; at = FNR; ord = order; order = ""
    matcher = ""; permit = ""; anyreq = ""; basic = "no"
    next
  }
  name != "" && /securityMatcher\(/ { m = $0; sub(/.*securityMatcher\(/, "", m); sub(/\)[^)]*$/, "", m); matcher = m }
  name != "" && /permitAll\(\)/ { p = $0; sub(/^[[:space:]]*\.?/, "", p); sub(/\.permitAll.*/, "", p); permit = (permit == "") ? p : permit ", " p }
  name != "" && /anyRequest\(\)\./ { a = $0; sub(/.*anyRequest\(\)\./, "", a); sub(/\(.*/, "", a); anyreq = a "()" }
  name != "" && /httpBasic/ { basic = "sí" }
  END { flush() }' 2>/dev/null | sort | list_or_none
echo ""
echo "Clases \`@ConfigurationProperties\`:"
echo ""
printf '%s\n' "$MAIN_JAVA" | xargs grep -l '@ConfigurationProperties' 2>/dev/null | list_or_none
echo ""

echo "## Reglas de arquitectura ejecutables"
echo ""
ARCH=$(printf '%s\n' "$TEST_JAVA" | xargs grep -lE 'com\.tngtech\.archunit' 2>/dev/null | sort)
if [ -z "$ARCH" ]; then
  echo "- ninguna (no hay tests ArchUnit)"
else
  for f in $ARCH; do
    echo "- \`$f\`:"
    grep -oE '(ArchRule[[:space:]]+[a-zA-Z0-9_]+|void[[:space:]]+[a-zA-Z0-9_]+\()' "$f" | sed -E 's/^ArchRule[[:space:]]+/regla /; s/^void[[:space:]]+/test /; s/\($//; s/^/  - /'
  done
fi
echo ""

echo "## Infraestructura de tests"
echo ""
echo "Contenedores (archivo → imagen):"
echo ""
printf '%s\n' "$TEST_JAVA" | xargs grep -nE 'DockerImageName\.parse\("[^"]+"\)|new [A-Za-z]+Container(<[^>]*>)?\("[^"]+"\)' 2>/dev/null \
  | sed -E 's#^([^:]+):([0-9]+):.*\("([^"]+)"\).*#\1:\2 → \3#' | list_or_none
echo ""
echo "Clases base abstractas y quién las extiende:"
echo ""
BASES=$(printf '%s\n' "$TEST_JAVA" | xargs grep -lE '\babstract class\b' 2>/dev/null | sort)
if [ -z "$BASES" ]; then
  echo "- ninguna"
else
  for f in $BASES; do
    name=$(basename "$f" .java)
    # The class that extends, not just the file that mentions it: a nested helper
    # class extending the base does not make its outer test a subclass.
    users=$(printf '%s\n' "$TEST_JAVA" | xargs grep -oE "class[[:space:]]+[A-Za-z0-9_]+[[:space:]]+extends[[:space:]]+$name\b" 2>/dev/null \
      | awk -F: '{ file = $1; sub(/.*\//, "", file); sub(/\.java$/, "", file)
                   cls = $2; sub(/^class[[:space:]]+/, "", cls); sub(/[[:space:]].*/, "", cls)
                   print (cls == file) ? file : file " (vía clase anidada " cls ")" }' \
      | sort | paste -sd, - | sed 's/,/, /g')
    echo "- \`$f\` → extendida por: ${users:-nadie}"
  done
fi
echo ""
echo "Tests que usan WireMock:"
echo ""
printf '%s\n' "$TEST_JAVA" | xargs grep -lE 'wiremock|WireMock' 2>/dev/null | list_or_none
echo ""
echo "Tests que levantan Spring (\`@SpringBootTest\`, \`@WebMvcTest\`, \`@DataJpaTest\`):"
echo ""
printf '%s\n' "$TEST_JAVA" | xargs grep -lE '@(SpringBootTest|WebMvcTest|DataJpaTest)' 2>/dev/null | list_or_none
echo ""
echo "Clases de soporte (carpetas \`support\`, \`fixtures\`, \`testutil\`):"
echo ""
printf '%s\n' "$TEST_JAVA" | grep -E '/(support|fixtures|testutil)/' | list_or_none
echo ""

echo "## Pureza del filtro rápido"
echo ""
echo "Tests en paquetes \`domain\`, \`application\` o \`architecture\` que levantan Spring,"
echo "contenedores o extienden una clase base de tests (tienen que quedar fuera de"
echo "\`FAST_TEST_CMD\`):"
echo ""
BASE_NAMES=$(for f in $BASES; do basename "$f" .java; done | paste -sd'|' -)
IMPURE='@(SpringBootTest|WebMvcTest|DataJpaTest|Testcontainers|Container)\b'
[ -n "$BASE_NAMES" ] && IMPURE="$IMPURE|extends[[:space:]]+($BASE_NAMES)\b"
printf '%s\n' "$TEST_JAVA" | grep -E '/(domain|application|architecture)/' | xargs grep -lE "$IMPURE" 2>/dev/null | list_or_none
echo ""

echo "## Persistencia"
echo ""
echo "Carpetas de migraciones:"
echo ""
find . \( "${PRUNE[@]}" \) -prune -o -type d \( -path '*/db/migration' -o -path '*/db/changelog' \) -print 2>/dev/null \
  | sed 's#^\./##' | sort | list_or_none
echo ""
echo "Migraciones (\`.sql\`, \`.java\`, changelogs):"
echo ""
find . \( "${PRUNE[@]}" \) -prune -o -type f \( -path '*/db/migration/*' -o -path '*/db/changelog/*' \) \
  \( -name '*.sql' -o -name 'V*.java' -o -name '*.xml' -o -name '*.yaml' -o -name '*.yml' \) -print 2>/dev/null \
  | sed 's#^\./##' | sort | list_or_none
echo ""
echo "\`ddl-auto\`:"
echo ""
find . \( "${PRUNE[@]}" \) -prune -o -type f -path '*/src/main/resources/application*.y*ml' -print 2>/dev/null \
  | sed 's#^\./##' | sort | xargs grep -HoE '^[[:space:]]*ddl-auto:[[:space:]]*[a-z-]+' 2>/dev/null \
  | sed -E 's#^([^:]+):[[:space:]]*#\1 → #' | list_or_none
