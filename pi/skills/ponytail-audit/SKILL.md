---
name: ponytail-audit
description: Audit an entire codebase in the form of ponytail.
license: MIT
---
Ponytail, applied to the whole codebase. First read the ponytail skill. Then audit the *entire* codebase, continuously asking the question: "If I wrote this code according to the ponytail doctrine, would it be like this?" If not, note it down, its part of the audit now.

## Hunt
Deps the stdlib or platform already ships, single-implementation interfaces, factories with one product, wrappers that only delegate, files exporting one thing, dead flags and config, hand-rolled stdlib.

## Output

One line per finding, ranked: `<tag> <what to cut>. <replacement>. [path]`.
End with `net: -<N> lines, -<M> deps possible.`
Nothing to cut: `Lean already`

## Boundaries

Scope: over-engineering and complexity only.
Correctness bugs, security holes, and performance are explicitly out of scope.
Route them to a normal review pass. Lists findings, applies nothing.
One-shot.
