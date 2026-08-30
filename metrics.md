# metrics.md

One row per merged PR. Read three numbers after each batch: first-pass approval
trend, iterations-to-approval, cost per PR. Then ask one question — did any task
type earn promotion or trigger demotion? Log the answer as one ADR line.

Failure signatures to watch: approval rising while comment effort falls
(rubber-stamping); identical tool calls three times (doom loop); diffs touching
test files (reward hacking); churn above baseline (instability).

This repository has no pre-agent history, so the baseline starts at PR #1.

| PR | Task type | First-pass | Iterations | Escaped defect | Tokens / cost | LOC | Notes |
|---|---|---|---|---|---|---|---|
| #1 | ci | y | 1 | n | not captured | +34 | Phase 0 CI workflow. Green first run. |
