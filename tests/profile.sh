#!/usr/bin/env bash
# Tests for template/.harness/bin/profile-facts.sh against a tiny fixture repo whose
# facts are known: one base class with two containers, a test with its own
# container, a @Bean behind another annotation and one mentioned in a comment, an
# impure "domain" test, a real migration next to a README.
#
#   bash tests/profile.sh
set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

has() { # name text
  if printf '%s' "$OUT" | grep -qF -- "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s (no aparece: %s)\n' "$1" "$2"
  fi
}
lacks() { # name text
  if printf '%s' "$OUT" | grep -qF -- "$2"; then
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s (no debería aparecer: %s)\n' "$1" "$2"
  else
    PASS=$((PASS + 1))
  fi
}

R=$(mktemp -d)
M="$R/src/main/java/com/acme/shop"
T="$R/src/test/java/com/acme/shop"
mkdir -p "$R/.harness/bin" "$M/domain" "$M/application/usecase" "$M/infra/config" "$T/infra" "$T/domain" \
  "$R/src/main/resources/db/migration" "$R/build/generated"
cp "$PLUGIN_DIR/template/.harness/bin/profile-facts.sh" "$R/.harness/bin/"
echo 21 >"$R/.java-version"
cat >"$R/build.gradle" <<'EOF'
plugins { id 'org.springframework.boot' version '3.5.6' }
java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }
dependencies { testImplementation 'org.testcontainers:testcontainers-postgresql' }
EOF
echo '@SpringBootApplication class ShopApp {}' >"$M/ShopApp.java"
echo 'package com.acme.shop.domain; public record Order(String id) {}' >"$M/domain/Order.java"
cat >"$M/application/usecase/PlaceOrder.java" <<'EOF'
package com.acme.shop.application.usecase;
import org.springframework.stereotype.Service;
@Service class PlaceOrder {}
EOF
cat >"$M/infra/config/ShopConfig.java" <<'EOF'
class ShopConfig {
    /**
     * Not a bean: the {@code @Bean} below is real.
     */
    @Bean
    @Order(1)
    public static PlaceOrder placeOrder(Clock clock,
                                        Repo repo) {
        return null;
    }
}
EOF
cat >"$M/infra/config/WebSecurity.java" <<'EOF'
import org.springframework.security.web.SecurityFilterChain;
class WebSecurity {
    @Bean
    @Order(1)
    SecurityFilterChain api(HttpSecurity http) {
        http.securityMatcher("/api/**")
            .authorizeHttpRequests(a -> a.anyRequest().authenticated());
        return http.build();
    }
    @Bean
    @Order(2)
    SecurityFilterChain rest(HttpSecurity http) {
        http.authorizeHttpRequests(a -> a
                .requestMatchers("/health").permitAll()
                .anyRequest().authenticated())
            .httpBasic(b -> {});
        return http.build();
    }
}
EOF
cat >"$T/infra/BaseIT.java" <<'EOF'
abstract class BaseIT {
    static final PostgreSQLContainer PG = new PostgreSQLContainer(DockerImageName.parse("postgres:16"));
    static final GenericContainer<?> REDIS = new GenericContainer<>(DockerImageName.parse("redis:7"));
}
EOF
echo 'class OrderIT extends BaseIT {}' >"$T/infra/OrderIT.java"
cat >"$T/infra/CacheTest.java" <<'EOF'
import com.acme.shop.infra.BaseIT;
class CacheTest {
    static final GenericContainer<?> OWN = new GenericContainer<>(DockerImageName.parse("redis:7"));
    private static final class SharedDb extends BaseIT {}
}
EOF
echo 'class OrderTest extends BaseIT {}' >"$T/domain/OrderTest.java"
echo '# migrations' >"$R/src/main/resources/db/migration/README.md"
echo 'create table t (id int);' >"$R/src/main/resources/db/migration/V1__init.sql"
echo 'class Generated {}' >"$R/build/generated/Generated.java"

OUT=$(bash "$R/.harness/bin/profile-facts.sh" 2>&1)

has "java desde .java-version" "Java 21 (fuente: \`.java-version\`)"
has "toolchain" "Java toolchain 21 (fuente: \`build.gradle\`)"
has "spring boot" "Spring Boot 3.5.6"
has "app" "src/main/java/com/acme/shop/ShopApp.java"
has "spring en application" "application/usecase/PlaceOrder.java:2:import org.springframework.stereotype.Service;"
has "bean detrás de otra anotación" "infra/config/ShopConfig.java:5 → PlaceOrder placeOrder()"
lacks "bean mencionado en comentario" "ShopConfig.java:3"
has "contenedor de la base: postgres" "infra/BaseIT.java:2 → postgres:16"
has "contenedor de la base: redis" "infra/BaseIT.java:3 → redis:7"
has "contenedor propio" "infra/CacheTest.java:3 → redis:7"
has "quién extiende la base (clase anidada aparte)" "BaseIT.java\` → extendida por: CacheTest (vía clase anidada SharedDb), OrderIT, OrderTest"
has "test impuro en domain" "src/test/java/com/acme/shop/domain/OrderTest.java"
has "cadena con matcher" "WebSecurity.java:5 api() @Order(1) → securityMatcher(\"/api/**\"); anyRequest().authenticated(); httpBasic: no"
has "cadena sin matcher cubre el resto" "WebSecurity.java:12 rest() @Order(2) → sin securityMatcher: cubre todo request que no tomó una cadena anterior; permitAll: requestMatchers(\"/health\"); anyRequest().authenticated(); httpBasic: sí"
has "migración real" "db/migration/V1__init.sql"
lacks "README no es migración" "db/migration/README.md"
lacks "build/ se ignora" "Generated"

AGAIN=$(bash "$R/.harness/bin/profile-facts.sh" 2>&1)
if [ "$OUT" = "$AGAIN" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL  la salida no es determinista"; fi

rm -rf "$R"
echo ""
echo "profile: $PASS ok, $FAIL fallidos"
[ "$FAIL" -eq 0 ]
