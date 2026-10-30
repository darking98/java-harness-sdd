# Harness SDD local (java-harness-sdd)

> Instrucciones personales, no del equipo: este archivo y `.harness/` están
> en `.git/info/exclude` y nunca se commitean.

Este repo tiene un harness de Spec Driven Development en `.harness/`. Cada
fase corre en su propia sesión, con el protocolo cargado por su comando:

1. `/java-harness-sdd:add-feature <TICKET>` — cargar el ticket.
2. `/java-harness-sdd:spec <TICKET>` — spec y aprobación. Después, `/clear`.
3. `/java-harness-sdd:deliver <TICKET>` — implementación, review y cierre.

Si te piden trabajar un ticket sin comando, sugerí el que corresponde a su
estado en `.harness/feature-list.json`.

## Reglas duras (siempre)

- ❌ No edites código de aplicación (`PROTECTED_PATHS` de
  `.harness/harness.conf`) mientras haya una feature `in_progress`: es del
  implementer.
- ❌ Los commits son del humano: no ejecutes `git add`, `commit`, `stash`,
  `push`, ni crees ramas o PRs.
- ❌ Nada del harness entra en git ni se menciona en código, commits o PRs.
- ❌ No crees `.harness/.direct-edit` ni toques `.harness/bin/`, `init.sh`
  ni `.state/`. Si el humano quiere trabajar sin el harness, que cree él
  `.harness/.direct-edit` y lo borre al terminar.
