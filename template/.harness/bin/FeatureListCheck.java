import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.MalformedInputException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Validates .harness/feature-list.json, the state invariants of each feature and the
 * consistency of its spec (acceptance -> requirements -> tasks).
 *
 * Runs with the JDK source launcher (java FeatureListCheck.java <harnessDir> <keyPattern>)
 * so the harness needs nothing beyond a JDK. Kept compatible with Java 17. The JSON
 * reader is deliberately minimal: it only has to read a file the harness itself writes.
 */
public class FeatureListCheck {

    private static final Set<String> VALID_STATUS =
            Set.of("pending", "spec_ready", "in_progress", "done", "blocked");
    private static final Set<String> REQUIRES_SPEC = Set.of("spec_ready", "in_progress", "done");
    private static final Set<String> REQUIRES_BASE_COMMIT = Set.of("in_progress", "done");
    private static final Set<String> BLOCKABLE = Set.of("pending", "spec_ready", "in_progress");
    private static final List<String> SPEC_FILES = List.of("requirements.md", "design.md", "tasks.md");

    private static final Pattern COMMIT = Pattern.compile("^[0-9a-f]{7,40}$");
    private static final Pattern REQUIREMENT_HEADING = Pattern.compile("^##\\s+R(\\d+)\\b");
    private static final Pattern ANY_HEADING = Pattern.compile("^#{1,6}\\s");
    private static final Pattern CRITERIA = Pattern.compile("Criterio:\\s*(A\\d+(?:\\s*,\\s*A\\d+)*)");
    private static final Pattern TASK_LINE = Pattern.compile("^\\s*- \\[[ xX]\\]\\s+T(\\d+)\\b");
    // Canonical separator is a comma; "y" and "/" are accepted so "R1 y R2" does not silently drop R2.
    private static final Pattern COVERS = Pattern.compile("Cubre:\\s*(R\\d+(?:\\s*(?:,|/|\\by\\b)\\s*R\\d+)*)");
    private static final Pattern NUMBER = Pattern.compile("\\d+");
    private static final Pattern VERDICT_PREFIX = Pattern.compile("^\\*\\*Veredicto:\\*\\*");
    private static final Pattern VERDICT_LINE =
            Pattern.compile("^\\*\\*Veredicto:\\*\\*\\s+(APPROVED|CHANGES_REQUESTED)\\s*$");

    public static void main(String[] args) throws IOException {
        // On Windows stdout defaults to the console code page; the hooks and Git Bash read UTF-8.
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8));

        // --current <harnessDir>: prints the name of the feature in_progress, for the hooks.
        boolean current = args.length == 2 && args[0].equals("--current");
        if (!current && args.length < 2) {
            System.out.println("[FAIL]  usage: java FeatureListCheck.java <harnessDir> <keyPattern>"
                    + " | --current <harnessDir>");
            System.exit(2);
        }
        Path harness = Path.of(current ? args[1] : args[0]);
        Pattern keyPattern = current ? null : Pattern.compile(args[1]);
        List<String> errors = new ArrayList<>();

        Object root;
        try {
            root = new Json(Files.readString(harness.resolve("feature-list.json"), StandardCharsets.UTF_8)).parse();
        } catch (MalformedInputException e) {
            System.out.println("[FAIL]  feature-list.json no está en UTF-8");
            System.exit(1);
            return;
        } catch (RuntimeException | IOException e) {
            System.out.println("[FAIL]  feature-list.json ilegible: " + e.getMessage());
            System.exit(1);
            return;
        }

        if (!(root instanceof Map<?, ?> rootMap) || !(rootMap.get("features") instanceof List<?> features)) {
            System.out.println("[FAIL]  feature-list.json no tiene un array \"features\"");
            System.exit(1);
            return;
        }

        if (current) {
            List<String> running = new ArrayList<>();
            for (Object item : features) {
                if (item instanceof Map<?, ?> f && "in_progress".equals(f.get("status"))) {
                    running.add(String.valueOf(f.get("name")));
                }
            }
            if (running.size() != 1) {
                System.exit(1);
            }
            System.out.println(running.get(0));
            return;
        }

        Set<String> names = new HashSet<>();
        int inProgress = 0;
        for (Object item : features) {
            if (!(item instanceof Map<?, ?> f)) {
                errors.add("una entrada de features no es un objeto");
                continue;
            }
            String name = String.valueOf(f.get("name"));
            Object statusValue = f.get("status");
            String status = statusValue == null ? "" : statusValue.toString();

            if (!keyPattern.matcher(name).matches()) {
                errors.add("feature \"" + name + "\": name no es una clave de ticket válida (" + keyPattern + ")");
            }
            if (!names.add(name)) {
                errors.add("feature \"" + name + "\" duplicada");
            }
            if (!VALID_STATUS.contains(status)) {
                errors.add("feature " + name + ": estado inválido \"" + status + "\"");
                continue;
            }
            if (status.equals("in_progress")) {
                inProgress++;
            }
            if (!(f.get("sdd") instanceof Boolean sddValue)) {
                errors.add("feature " + name + ": \"sdd\" tiene que estar presente y ser true o false");
                continue;
            }
            boolean sdd = sddValue;
            boolean approved = Boolean.TRUE.equals(f.get("spec_approved"));
            List<?> acceptance = f.get("acceptance") instanceof List<?> list ? list : List.of();
            if (acceptance.isEmpty()) {
                errors.add("feature " + name + ": sin criterios de aceptación (acceptance)");
            }

            if (approved && status.equals("pending")) {
                errors.add("feature " + name + ": \"spec_approved\": true con status pending (no hay spec que aprobar)");
            }
            if (sdd && REQUIRES_BASE_COMMIT.contains(status) && !approved) {
                errors.add("feature " + name + " en " + status + " sin \"spec_approved\": true");
            }
            if (REQUIRES_BASE_COMMIT.contains(status)) {
                Object base = f.get("base_commit");
                if (!(base instanceof String commit) || !COMMIT.matcher(commit).matches()) {
                    errors.add("feature " + name + " en " + status + " sin \"base_commit\" (git rev-parse HEAD al pasar a in_progress)");
                }
            }
            Object blockedFrom = f.get("blocked_from");
            if (status.equals("blocked")) {
                if (!(blockedFrom instanceof String from) || !BLOCKABLE.contains(from)) {
                    errors.add("feature " + name + " en blocked sin \"blocked_from\" (pending, spec_ready o in_progress)");
                }
            } else if (blockedFrom != null) {
                errors.add("feature " + name + ": \"blocked_from\" solo puede existir en status blocked");
            }
            if (status.equals("done")) {
                checkApprovedReview(harness, name, errors);
            }
            if (sdd && REQUIRES_SPEC.contains(status)) {
                checkSpec(harness, name, status, acceptance.size(), errors);
            }
        }
        if (inProgress > 1) {
            errors.add("hay " + inProgress + " features en in_progress (máximo 1)");
        }

        if (!errors.isEmpty()) {
            errors.forEach(e -> System.out.println("[FAIL]  " + e));
            System.exit(1);
        }
        System.out.println("[OK]    feature-list.json válido (" + features.size() + " features)");
        System.out.println("[OK]    estados, aprobaciones, reviews y specs consistentes");
    }

    private static void checkApprovedReview(Path harness, String name, List<String> errors) throws IOException {
        Path review = harness.resolve("progress").resolve("review-" + name + ".md");
        String problem = Files.isRegularFile(review)
                ? verdictProblem(Files.readAllLines(review, StandardCharsets.UTF_8))
                : "no existe";
        if (problem != null) {
            errors.add("feature " + name + " en done: .harness/progress/review-" + name + ".md " + problem);
        }
    }

    /** Null when the review has exactly one well-formed verdict line and it is APPROVED. */
    private static String verdictProblem(List<String> lines) {
        List<String> verdicts = new ArrayList<>();
        for (String line : lines) {
            if (VERDICT_PREFIX.matcher(line).find()) {
                Matcher verdict = VERDICT_LINE.matcher(line);
                if (!verdict.find()) {
                    return "tiene una línea de veredicto inválida: \"" + line.trim() + "\"";
                }
                verdicts.add(verdict.group(1));
            }
        }
        if (verdicts.size() != 1) {
            return "tiene " + verdicts.size() + " líneas de veredicto (tiene que haber exactamente una)";
        }
        return verdicts.get(0).equals("APPROVED") ? null : "no es APPROVED";
    }

    /** Spec Kit style "analyze": every criterion has a requirement, every requirement a task. */
    private static void checkSpec(Path harness, String name, String status, int criteria, List<String> errors)
            throws IOException {
        Path specDir = harness.resolve("specs").resolve(name);
        boolean complete = true;
        for (String file : SPEC_FILES) {
            if (!Files.isRegularFile(specDir.resolve(file))) {
                errors.add("feature " + name + " en " + status + " sin .harness/specs/" + name + "/" + file);
                complete = false;
            }
        }
        if (status.equals("spec_ready") && !Files.isRegularFile(specDir.resolve("approval.md"))) {
            errors.add("feature " + name + " en spec_ready sin .harness/specs/" + name
                    + "/approval.md (el resumen que lee el humano para aprobar)");
        }
        if (!complete) {
            return;
        }
        String where = "spec " + name + ": ";

        Map<Integer, Set<Integer>> requirements = new LinkedHashMap<>();
        Integer current = null;
        for (String line : Files.readAllLines(specDir.resolve("requirements.md"), StandardCharsets.UTF_8)) {
            Matcher heading = REQUIREMENT_HEADING.matcher(line);
            if (heading.find()) {
                current = Integer.parseInt(heading.group(1));
                if (requirements.putIfAbsent(current, new TreeSet<>()) != null) {
                    errors.add(where + "R" + current + " duplicado en requirements.md");
                }
                continue;
            }
            if (ANY_HEADING.matcher(line).find()) {
                // Any other heading ends the requirement: a "Criterio:" under "## Preguntas" covers nothing.
                current = null;
                continue;
            }
            Matcher criteriaLine = CRITERIA.matcher(line);
            if (current != null && criteriaLine.find()) {
                requirements.get(current).addAll(numbers(criteriaLine.group(1)));
            }
        }
        if (requirements.isEmpty()) {
            errors.add(where + "requirements.md no tiene requirements (## R<n>)");
            return;
        }

        Set<Integer> coveredCriteria = new TreeSet<>();
        requirements.forEach((r, refs) -> {
            if (refs.isEmpty()) {
                errors.add(where + "R" + r + " sin línea \"Criterio: A<k>\" que lo ate al acceptance");
            }
            for (int a : refs) {
                if (a < 1 || a > criteria) {
                    errors.add(where + "R" + r + " referencia A" + a + ", pero el ticket tiene " + criteria + " criterios");
                }
            }
            coveredCriteria.addAll(refs);
        });
        for (int a = 1; a <= criteria; a++) {
            if (!coveredCriteria.contains(a)) {
                errors.add(where + "el criterio de aceptación A" + a + " no está cubierto por ningún requirement");
            }
        }

        Set<Integer> coveredRequirements = new TreeSet<>();
        Map<Integer, StringBuilder> tasks = new LinkedHashMap<>();
        Integer task = null;
        for (String line : Files.readAllLines(specDir.resolve("tasks.md"), StandardCharsets.UTF_8)) {
            Matcher taskLine = TASK_LINE.matcher(line);
            if (taskLine.find()) {
                task = Integer.parseInt(taskLine.group(1));
                if (tasks.put(task, new StringBuilder(line)) != null) {
                    errors.add(where + "T" + task + " duplicada en tasks.md");
                }
            } else if (line.isBlank()) {
                task = null;
            } else if (task != null) {
                tasks.get(task).append(' ').append(line.trim());
            }
        }
        if (tasks.isEmpty()) {
            errors.add(where + "tasks.md no tiene tasks (- [ ] T<n>)");
        }
        tasks.forEach((t, text) -> {
            Matcher covers = COVERS.matcher(text);
            if (!covers.find()) {
                errors.add(where + "T" + t + " sin \"Cubre: R<n>\"");
                return;
            }
            for (int r : numbers(covers.group(1))) {
                if (!requirements.containsKey(r)) {
                    errors.add(where + "T" + t + " cubre R" + r + ", que no existe en requirements.md");
                }
                coveredRequirements.add(r);
            }
        });
        for (int r : requirements.keySet()) {
            if (!coveredRequirements.contains(r)) {
                errors.add(where + "R" + r + " no está cubierto por ninguna task");
            }
        }
    }

    private static Set<Integer> numbers(String list) {
        Set<Integer> result = new LinkedHashSet<>();
        Matcher m = NUMBER.matcher(list);
        while (m.find()) {
            result.add(Integer.parseInt(m.group()));
        }
        return result;
    }

    /** Recursive-descent reader for the JSON subset the harness writes. */
    static final class Json {
        private final String s;
        private int i;

        Json(String s) {
            this.s = s;
        }

        Object parse() {
            Object value = value();
            skipWhitespace();
            if (i != s.length()) {
                throw error("contenido extra al final");
            }
            return value;
        }

        private Object value() {
            skipWhitespace();
            if (i >= s.length()) {
                throw error("fin inesperado");
            }
            char c = s.charAt(i);
            if (c == '{') return object();
            if (c == '[') return array();
            if (c == '"') return string();
            if (s.startsWith("true", i)) { i += 4; return Boolean.TRUE; }
            if (s.startsWith("false", i)) { i += 5; return Boolean.FALSE; }
            if (s.startsWith("null", i)) { i += 4; return null; }
            return number();
        }

        private Map<String, Object> object() {
            Map<String, Object> map = new LinkedHashMap<>();
            i++;
            skipWhitespace();
            if (peek('}')) { i++; return map; }
            while (true) {
                skipWhitespace();
                String key = string();
                skipWhitespace();
                expect(':');
                map.put(key, value());
                skipWhitespace();
                if (peek(',')) { i++; continue; }
                expect('}');
                return map;
            }
        }

        private List<Object> array() {
            List<Object> list = new ArrayList<>();
            i++;
            skipWhitespace();
            if (peek(']')) { i++; return list; }
            while (true) {
                list.add(value());
                skipWhitespace();
                if (peek(',')) { i++; continue; }
                expect(']');
                return list;
            }
        }

        private String string() {
            expect('"');
            StringBuilder sb = new StringBuilder();
            while (i < s.length()) {
                char c = s.charAt(i++);
                if (c == '"') return sb.toString();
                if (c != '\\') { sb.append(c); continue; }
                char e = s.charAt(i++);
                switch (e) {
                    case 'n' -> sb.append('\n');
                    case 't' -> sb.append('\t');
                    case 'r' -> sb.append('\r');
                    case 'b' -> sb.append('\b');
                    case 'f' -> sb.append('\f');
                    case 'u' -> { sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; }
                    default -> sb.append(e);
                }
            }
            throw error("string sin cerrar");
        }

        private Object number() {
            int start = i;
            while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
            if (start == i) throw error("valor inesperado '" + s.charAt(i) + "'");
            return Double.parseDouble(s.substring(start, i));
        }

        private void skipWhitespace() {
            while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++;
        }

        private boolean peek(char c) {
            return i < s.length() && s.charAt(i) == c;
        }

        private void expect(char c) {
            if (!peek(c)) throw error("se esperaba '" + c + "'");
            i++;
        }

        private IllegalArgumentException error(String message) {
            int line = 1;
            for (int k = 0; k < Math.min(i, s.length()); k++) if (s.charAt(k) == '\n') line++;
            return new IllegalArgumentException(message + " (línea " + line + ")");
        }
    }
}
