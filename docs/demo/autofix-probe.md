# Autofix probe — Manufact's autofix against our one remaining failure

G5 S3. One POST, against a green audit, with no red window and no code change.
The question: can Manufact's autofix act on
`tool-resource-metadata-complete`, the SDK gap this project has carried since
G3?

**Answer: it can act, it investigated for nearly seven minutes, and it changed
nothing — because there is nothing in this repository to change.** An
independent coding agent with full repo access reached the same conclusion this
project reached in G3 and verified in G4.

## The prediction, recorded before the call and wrong

The spec documents `422 — No connected repository or audit not fixable`. Since
the only failing check has no code path in mcp-use 2.3.3, **I predicted 422**
and said so before making the request.

It returned **200**. Autofix accepted the job and ran a real agent against the
code. The prediction was wrong about the mechanism while being right about the
outcome, which is exactly why it was written down first.

## Request

Verified against the live OpenAPI document before calling. The endpoint takes
**no request body** — path parameters only.

```
POST /api/v1/server-audits/{serverId}/audits/{auditId}/autofix
  serverId  a9f68f45-7160-4b30-8855-06399bd6aebb
  auditId   a8c78006-ca4e-4968-9052-572d4bebdb4c   (green: 32 checks, 31 pass)
  headers   authorization: Bearer <redacted>, content-type: application/json
  body      none
```

Documented responses: `200` job enqueued or existing PR returned, `400`, `401`,
`403`, `404`, `409` already running, `422` no connected repository or audit not
fixable. The `200` schema carries `prUrl` and `prNumber` — the call can
open a pull request, which is why it was checkpointed first.

## Response — verbatim

```
status: 200 OK
content-type: application/json
body: {"id":"ad23262c-fe84-4ae2-b884-cffc9d74b64a","auditId":"a8c78006-ca4e-4968-9052-572d4bebdb4c","status":"pending","branch":null,"prUrl":null,"prNumber":null,"filesChanged":null,"errorMessage":null,"jobMeta":null,"startedAt":null,"completedAt":null,"createdAt":"2026-09-01T00:43:07.127Z"}
```

Polled `GET …/autofix` to a terminal state. Final:

```
{"status":"failed","phase":"failed","branch":null,"prUrl":null,"prNumber":null,
 "filesChanged":null,
 "errorMessage":"Validation Failed: {\"resource\":\"PullRequest\",\"field\":\"head\",\"code\":\"invalid\"} - https://docs.github.com/rest/pulls/pulls#create-a-pull-request",
 "events":200,
 "startedAt":"2026-09-01T00:43:07.830Z","completedAt":"2026-09-01T00:49:56.075Z"}
```

Elapsed: **6 minutes 48 seconds**.

## What the agent actually did

`jobMeta` carries the full trace — 200 events, about 158 KB. Counted rather
than summarized:

| | |
|---|---|
| `thinking` | 22 |
| `tool_use` | 89 |
| `tool_result` | 89 |
| tools used | `Bash` 87, `Read` 2 |
| **`Edit` / `Write` / `MultiEdit` calls** | **0** |
| **`git add` / `commit` / `checkout -b` / `push`** | **0** |

It read and searched. It never edited a file and never staged a commit.

Its own recorded conclusion, verbatim from the trace:

> neither `widgetMetadata` nor `openai/widgetDescription` appears in the mcp-use
> package. This means the mcp-use 2.3.3 framework doesn't have first-class
> support for `openai/widgetDescription`.

That is the same finding recorded in STAGE-PLAN correction 26 and re-verified in
G4 — `buildResourceUiMeta` emits exactly `csp`, `permissions`, `domain`,
`prefersBorder`, and neither field appears in any file of the package. **Reached
independently, by a different agent, from the code.**

## No pull request was opened

Confirmed three ways:

- The job record: `branch: null`, `prUrl: null`, `prNumber: null`.
- `git ls-remote --heads origin` returns `refs/heads/main` and nothing else.
- `gh pr list --state all` shows no PR from any author but the repository owner.

**On the failure message.** `field: head, code: invalid` is GitHub refusing to
open a pull request whose head branch does not exist. Taken with zero mutating
git commands and no remote branch, the supported reading is that the agent
produced nothing to open a PR *from*, and the pipeline attempted the PR anyway.

What that reading does **not** establish: whether the pipeline would have
reported "nothing to fix" had it checked before calling GitHub. The
observable outcome is a `failed` job whose error is a PR-creation error rather
than a fix-impossible one. Anyone re-reading this should treat "autofix declined
to invent a fix" as evidenced by the empty tool trace, and treat the error
string as evidence about the pipeline's ordering, not about the fix.

## What this proves, and what it does not

**Proves.** Autofix is a real coding agent with repo access, not a template
engine. It accepts a job against an audit whose only failure is an SDK gap
rather than rejecting it with 422. Given that gap, it investigates and declines
to fabricate a change. Its conclusion matches ours, independently derived.

**Does not prove.** That autofix can successfully fix anything in this
repository — no defect it *could* fix was staged for it. That it opens
well-formed PRs — the one attempt failed on a GitHub validation error. Nothing
about its behavior on `error`-severity checks; this was a `warning`.

## Decide record

**Question.** Record the probe and proceed to G6, or escalate now to a staged
re-break with a defect autofix can act on?

| option | score |
|---|---|
| **Record the probe result and proceed to G6; defer any re-break to G6's drafting** | **81** |
| Close as inconclusive and re-run against a different audit or check | 64 |
| Escalate now to a full staged re-break | 54 |

Confidence **0.585** — low, and the runner-up is close. The deciding factors
were the marginal evidentiary value of another probe, the cost of escalation (a
production red window plus roughly three hours), whether the question is already
answered, and the risk of manufacturing an artificial break that tests a
different question than the one asked.

The weakness in the recommendation: escalating would answer "can autofix
fix a defect it *can* act on?", which this probe does not answer. It
lost on cost and on testing a different question, not because the question is
uninteresting.

**This matches the pre-decided branch** — cannot-fix → record it, proceed to G6,
re-break deferred to G6's drafting and escalated only if the submission is
materially weaker without a live autofix asset. No disagreement, so no stop.

## Production stayed green throughout

The probe ran against a green audit and changed nothing, so there was no red
window at any point. Confirmed after the S2 deploy (`24dbfe2c`, the merge of
PR #31) with a fresh audit through the deployed tools —
[`audit-post-s2.json`](audit-post-s2.json):

```
audit 5e97c831-c7e8-439b-b5db-86a28f395857
isReadyForChatgpt   true
isReadyForClaudeai  true
32 checks — 31 pass
deviations from baseline f4022c88: none
```

## Reproducing this

Every id here is refetchable from Manufact's API by anyone with their own
credentials. The key appears nowhere in this file, in the trace excerpts, or in
any command recorded here.
