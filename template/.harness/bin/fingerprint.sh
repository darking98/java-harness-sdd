#!/usr/bin/env bash
# Fingerprint of the uncommitted state of the application code. Sourced by
# .harness/init.sh and by the plugin hooks, never executed.
#
# It lives in the template, not in the plugin, because init.sh must work when run by
# hand from the repo, where the plugin path is unknown. The hooks source it only
# after load_harness has checked the harness is local (untracked).
#
# Requires PROTECTED_PATHS (from harness.conf) and the repo root as current dir.
# Prints nothing when the code has no uncommitted changes.

harness_fingerprint() {
  local changes
  # shellcheck disable=SC2086 # PROTECTED_PATHS is a space separated list on purpose
  changes=$(git status --porcelain -- $PROTECTED_PATHS 2>/dev/null)
  [ -n "$changes" ] || return 0
  # shellcheck disable=SC2086
  {
    printf '%s\n' "$changes"
    git diff HEAD -- $PROTECTED_PATHS 2>/dev/null
    git ls-files --others --exclude-standard -z -- $PROTECTED_PATHS 2>/dev/null \
      | while IFS= read -r -d '' untracked; do git hash-object -- "$untracked"; done
  } | git hash-object --stdin
}
