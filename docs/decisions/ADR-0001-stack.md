# ADR-0001: mcp-use v2 on TypeScript, deployed to Manufact Cloud from GitHub

- Status: accepted
- Date: 2026-08-30
- Deciders: repository owner

## Context

mcp-readycheck must call Manufact's publishing-check API against its own
deployed URL and render the result as an interactive surface in ChatGPT and
Claude. That imposes four requirements: a typed tool-to-UI contract, a public
HTTPS MCP endpoint the checks can reach, a deployment identity the audit API can
address, and a repository the autofix flow can open a pull request against.

Verified from `https://manufact.com/openapi.json` before committing to the stack:

- `POST /api/v1/server-audits/{serverId}/audits` and its GET exist and return
  `checks[]` with `isReadyForChatgpt` / `isReadyForClaudeai`.
- `POST .../autofix` returns `422 "No connected repository or audit not fixable"`
  when no repository is connected.
- The deploy pipeline injects `MCP_URL` and `CSP_URLS` as managed env vars.

The earlier feasibility study concluded no programmatic trigger for the
publishing checks existed and designed a local, equivalent check set as a
fallback. That conclusion is now superseded: the endpoints are real, so the app
runs Manufact's own checks rather than an approximation of them.

## Decision

Build on **mcp-use v2 (TypeScript)**, scaffolded from `--template mcp-apps`, and
deploy to **Manufact Cloud with a connected GitHub repository**.

## Consequences

- Zod schemas flow from tool `inputSchema`/`outputSchema` into View props, so the
  widget's contract is the tool's contract. Breaking one breaks the other visibly.
- One View per tool, and the runtime is stateless — state lives request-scoped or
  externally.
- GitHub-connected deploy is what makes the Stage 12 autofix pull request
  possible at all; `--no-github` would have foreclosed it.
- Every feature-branch push produces a failed preview deployment on the Free
  tier (`PLAN_LIMIT_PREVIEW_DEPLOYS`). Accepted as noise.
- The app is coupled to one vendor's API shape. That coupling is the product, not
  an accident of implementation.

## Alternatives considered

- **Local equivalent check set** (the feasibility study's recommendation) —
  rejected: the real API exists, and an approximation would have to be labelled
  as one, which weakens the demonstration.
- **Python MCP SDK** — rejected: no typed tool-to-UI View contract, and the
  MCP Apps widget story is TypeScript-first.
- **`deploy --no-github`** (upload local source) — rejected: gives up CI on pull
  requests and the autofix pull-request flow.

## Revisit when

mcp-use ships a major version, or Manufact changes the audit endpoints' shape.
