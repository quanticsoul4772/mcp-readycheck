# Plan: <feature>

Written by the orchestrator, approved by the human at **Gate A**. Nothing
executes before that approval.

## Uncertainty protocol

List every assumption as a numbered question **before writing code**. An
assumption that changes the shape of the work is a blocking question; one that
does not is stated and carried forward.

1. …

## Goal

One paragraph: why this exists and what "done" means. Not a restatement of the
issue title.

## Acceptance criteria

Three to seven, Given/When/Then, **Default-FAIL** — each must be false against
today's code, so passing means something changed.

1. **Given** … **when** … **then** …

## Phased TDD steps

Each phase: the failing test first, then the change that makes it pass.

1. …

## Files to touch

Paths, with the reason each is in scope.

## Symbol anchors

Function, type, and component names the work attaches to — **never line
numbers**, which drift the moment anything above them changes.

## Invariants

What must remain true throughout. Anything here that breaks is a stop, not a
fix-up.

## Out of scope

Explicit. Anything not listed here that the work touches is scope creep and
needs a new plan.
