# Check diff — baseline, break, revert

Every row read through the deployed `get_audit`, never local dev.

| | baseline | red (break) | green (revert) |
|---|---|---|---|
| audit | `f4022c88-9204-42df-aeed-085e7066bd00` | `5309c70b-1e27-4e69-83e9-b5d70b95769d` | `a8c78006-ca4e-4968-9052-572d4bebdb4c` |
| isReadyForChatgpt | true | **false** | true |
| isReadyForClaudeai | true | true | true |
| checks | 32 | 32 | 32 |

## What the break moved

| checkId | severity | baseline | red |
|---|---|---|---|
| `tool-hints-present` | error | pass | **fail** |

## Regressions after the revert

**None.** Every check that passed in the baseline passes again.

Checks matching the baseline after the revert: **32 of 32**.

## Every check

| checkId | severity | baseline | red | green |
|---|---|---|---|---|
| `claude-tool-hints-present` | error | pass | pass | pass |
| `cursor-tool-name-budget` | warning | pass | pass | pass |
| `fuzz-edge-case-handling` | warning | pass | pass | pass |
| `mixed-read-write` | warning | pass | pass | pass |
| `openai-file-params-schema-valid` | error | pass | pass | pass |
| `prompt-injection` | warning | pass | pass | pass |
| `resource-content-valid` | error | pass | pass | pass |
| `resources-list-responds` | info | pass | pass | pass |
| `server-responds` | error | pass | pass | pass |
| `server-tools-capability-declared` | error | pass | pass | pass |
| `tool-description-no-prompt-injection` | warning | pass | pass | pass |
| `tool-description-present` | warning | pass | pass | pass |
| `tool-hints-present` | error | pass | **fail** | pass |
| `tool-input-header-annotations-valid` | error | pass | pass | pass |
| `tool-input-schema-type` | error | pass | pass | pass |
| `tool-invocation-metadata-present` | warning | pass | pass | pass |
| `tool-name-format` | warning | pass | pass | pass |
| `tool-name-length` | error | pass | pass | pass |
| `tool-name-protocol-length` | warning | pass | pass | pass |
| `tool-names-protocol-unique` | warning | pass | pass | pass |
| `tool-names-unique` | error | pass | pass | pass |
| `tool-output-schema-valid` | error | pass | pass | pass |
| `tool-params-description-present` | warning | pass | pass | pass |
| `tool-resource-metadata-complete` | warning | **fail** | **fail** | **fail** |
| `tool-resource-uri-readable` | error | pass | pass | pass |
| `tool-title-present` | error | pass | pass | pass |
| `tool-visibility-valid` | error | pass | pass | pass |
| `tools-list-responds` | warning | pass | pass | pass |
| `view-csp-origin-coverage` | warning | pass | pass | pass |
| `view-domain-present` | error | pass | pass | pass |
| `view-domain-responds` | warning | pass | pass | pass |
| `view-resource-coverage` | warning | pass | pass | pass |

