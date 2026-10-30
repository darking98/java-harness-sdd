#!/usr/bin/env bash
# Shared helpers for the java-harness-sdd hooks. Sourced, never executed.
#
# The hooks read their JSON input with grep/sed instead of jq or node: a Java repo
# cannot be assumed to have either, and the hooks only need a few flat fields.

PLUGIN_AGENT_PREFIX="java-harness-sdd:"

# Prints the first string value of a "key": "value" pair (values without escaped quotes).
json_string_field() {
  printf '%s' "$1" \
    | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

# Prints a string value that may contain escaped characters, unescaped.
json_text_field() {
  printf '%s' "$1" \
    | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" \
    | head -1 \
    | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\"/"/g' \
    | { IFS= read -r -d '' raw; printf '%b' "$raw"; }
}

json_true_field() {
  printf '%s' "$1" | grep -Eq "\"$2\"[[:space:]]*:[[:space:]]*true"
}

# JSON-escaped Windows paths arrive as C:\\Users\\...; normalise to forward slashes.
normalize_path() {
  printf '%s' "$1" | sed -e 's#\\\\#/#g' -e 's#\\#/#g'
}

# Git Bash may hand the project dir as /c/Users/...; tools report C:/Users/....
# Both sides go through this before comparing, case-insensitively.
canonical_path() {
  normalize_path "$1" | sed -E 's#^/([a-zA-Z])/#\1:/#' | tr '[:upper:]' '[:lower:]'
}

# Resolves "." and ".." segments of a forward-slash path, without touching the
# filesystem. An absolute path cannot climb above its root; a relative one that
# climbs above its start keeps a leading "../" so callers can treat it as outside.
resolve_dots() {
  local path="$1" prefix="" part
  local -a parts stack=()
  case "$path" in
    [a-zA-Z]:/*) prefix="${path:0:3}"; path="${path:3}" ;;
    /*) prefix="/"; path="${path:1}" ;;
  esac
  IFS='/' read -r -a parts <<<"$path"
  for part in "${parts[@]}"; do
    case "$part" in
      ""|.) ;;
      ..)
        if [ "${#stack[@]}" -gt 0 ] && [ "${stack[${#stack[@]}-1]}" != ".." ]; then
          stack=("${stack[@]:0:${#stack[@]}-1}")
        elif [ -z "$prefix" ]; then
          stack+=("..")
        fi
        ;;
      *) stack+=("$part") ;;
    esac
  done
  local IFS='/'
  printf '%s%s' "$prefix" "${stack[*]}"
}

# Prints the path relative to the project root, or nothing when it is outside it.
# Dots are resolved first: <repo>/.harness/specs/../../src/X.java is src/X.java.
project_relative_path() {
  local file root
  file=$(resolve_dots "$(normalize_path "$1")")
  root=$(resolve_dots "$(normalize_path "${CLAUDE_PROJECT_DIR:-.}")")
  root=${root%/}
  case "$file" in
    /*|[a-zA-Z]:/*) ;;
    ..|../*) return ;;
    *) printf '%s' "$file"; return ;;
  esac
  local canon_file canon_root
  canon_file=$(canonical_path "$file")
  canon_root=$(canonical_path "$root")
  case "$canon_file" in
    "$canon_root"/*) printf '%s' "${file:$(( ${#canon_root} + 1 ))}" ;;
  esac
}

# Loads the harness of the current project. Returns 1 (the hook must exit 0, doing
# nothing) when the project has no harness, the human disabled it, or any part of
# the harness came committed in the repo: the hooks source harness.conf and
# bin/fingerprint.sh, and a user-scoped plugin must not run code a cloned repo brings
# along without going through Claude Code's trust dialog.
load_harness() {
  HARNESS_DIR="${CLAUDE_PROJECT_DIR:-.}/.harness"
  [ -f "$HARNESS_DIR/harness.conf" ] || return 1
  if [ -n "$(git -C "${CLAUDE_PROJECT_DIR:-.}" ls-files -- .harness 2>/dev/null | head -1)" ]; then
    echo "[java-harness-sdd] Hay archivos de .harness/ trackeados por git: el harness de este repo no se ejecuta. El harness es local y nunca se commitea." >&2
    return 1
  fi
  [ -f "$HARNESS_DIR/.direct-edit" ] && return 1
  # shellcheck source=/dev/null
  . "$HARNESS_DIR/harness.conf"
  return 0
}

has_feature_in_progress() {
  grep -Eq '"status"[[:space:]]*:[[:space:]]*"in_progress"' "$HARNESS_DIR/feature-list.json" 2>/dev/null
}

# Prints the name of the feature in_progress, or nothing. feature-list.json is written
# by the model in whatever layout it likes, so it is parsed with the harness's own
# JSON reader (the JDK is already a requirement) rather than grep. Costs a JVM start:
# only call it on the rare paths that need it.
current_feature() {
  java "$HARNESS_DIR/bin/FeatureListCheck.java" --current "$HARNESS_DIR" 2>/dev/null
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# True when the project-relative path falls under one of PROTECTED_PATHS. Compared
# case-insensitively: on Windows SRC/Main/X.java is the same file as src/main/X.java.
is_protected_path() {
  local file p
  file=$(lowercase "$1")
  for p in $(lowercase "$PROTECTED_PATHS"); do
    case "$file" in
      "$p"|"$p"/*) return 0 ;;
    esac
  done
  return 1
}
