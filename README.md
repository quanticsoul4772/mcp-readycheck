# mcp-readycheck

An MCP App that runs Manufact's publishing checks against its own deployed URL
and renders the result by category. It is its own test case: the server you
audit with it is the server serving it.

## The self-audit

Audit [`f4022c88`](docs/demo/baseline-f4022c88.json), the current baseline:

| | |
|---|---|
| checks | 32 |
| passing | 31 |
| failing | 1, severity `warning` |
| `isReadyForChatgpt` | **true** |
| `isReadyForClaudeai` | **true** |

Severity gates readiness and warnings do not, so both flags are true with one
check red.

### The one red check, and why it stays red

`tool-resource-metadata-complete` — "1 resource(s) have incomplete metadata",
scope `view`, on `ui://views/audit-report.html`. Its hint says to set the widget
description in `widgetMetadata`, or `_meta.ui.widgetDescription`.

Neither string appears in any file of mcp-use 2.3.3. `buildResourceUiMeta` emits
exactly `csp`, `permissions`, `domain` and `prefersBorder`. There is no code path
in this repository that can satisfy the check.

That is this repository's conclusion. It is also **Manufact's own conclusion**.
[The autofix probe](docs/demo/autofix-probe.md) POSTed Manufact's autofix at this
exact failure. It returned 200, ran a coding agent with repository access
for 6 minutes 48 seconds over 200 events, called `Bash` 87 times and `Read`
twice, made **zero** `Edit`/`Write` calls and **zero** git mutations, and
recorded, in its own words:

> neither `widgetMetadata` nor `openai/widgetDescription` appears in the mcp-use
> package. This means the mcp-use 2.3.3 framework doesn't have first-class
> support for `openai/widgetDescription`.

A different agent, reasoning from the code, reached the finding this project had
recorded two goals before the probe ran, in G3. What the probe does **not** show is autofix fixing
something and opening a merged pull request; producing that would have meant
breaking production on purpose to create a defect it could fix.

## The staged-failure demo

[`docs/demo/README.md`](docs/demo/README.md) — a one-line defect was shipped to
production deliberately, the app's own audit caught it, and the revert restored
the baseline. Both audits are captured.

| | audit | `isReadyForChatgpt` |
|---|---|---|
| broken | [`5309c70b`](docs/demo/audit-red.json) | **false** |
| reverted | [`a8c78006`](docs/demo/audit-green.json) | true |

`isReadyForClaudeai` stayed `true` on both. The break moved one flag, not both.

Break: [#27](https://github.com/quanticsoul4772/mcp-readycheck/pull/27) ·
revert: [#28](https://github.com/quanticsoul4772/mcp-readycheck/pull/28)

## The endpoint

    https://mcp-readycheck.run.mcp-use.com/mcp

Two tools. `start_audit` POSTs an audit for a server id and returns the audit id;
`get_audit` fetches one and renders it by category. Views are pure-render — every
network call happens server-side in the handler, or the app trips its own CSP
check.

## Development

    npm install
    npm run dev          # /mcp on :3000, Inspector at /mcp/inspector
    npm run typecheck
    npm run test:check   # discovery matches the index, CI, and the npm scripts
    npm run test:pure    # no network, no key — what CI runs
    npm run test:live    # POSTs real audits; needs MANUFACT_API_KEY

Process record, pull-request census, and known residuals:
[docs/PROCESS.md](docs/PROCESS.md).
