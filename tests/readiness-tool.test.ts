// readiness-tool.test.ts — the twelve tests frozen at Gate A.
//
// Run: npm test   (node --test)
//
// T1, T2, T4, T5 and T10 exercise the real Manufact API — the smallest real
// lifecycle that proves the change, as AGENTS.md requires. T6 tests the pure
// mapper on a crafted input; it is not a mock standing in for a lifecycle,
// because the lifecycle is covered by the live tests above it.
//
// The live tests need MANUFACT_API_KEY in the environment. They fail loudly
// when it is absent rather than skipping, because a silent skip is how a
// Default-FAIL criterion turns into a green tick that proves nothing.

import { strict as assert } from "node:assert";
import { after, before, describe, it } from "node:test";

// Library imports go through the `#lib/*` subpath map in package.json: one
// specifier that both TypeScript NodeNext and Node's type stripping resolve.
// A relative `./x.js` resolves literally under Node and finds nothing; `./x.ts`
// fails typecheck with TS5097. `../index.ts` below is relative only because the
// entry point has no subpath alias, and tsc never sees this file anyway —
// tests/ sits outside the tsconfig include.
import {
  createAudit,
  fetchAudit,
  fetchServer,
  requireApiKey,
  resolveActiveDeploymentId,
} from "#lib/manufact";
import { auditOutputSchema, mapAuditResponse } from "#lib/audit-schema";
import { getAuditHandler, startAuditHandler } from "../index.ts";

const SERVER_ID = "a9f68f45-7160-4b30-8855-06399bd6aebb";
const MCP_ORIGIN = "https://mcp-readycheck.run.mcp-use.com";

// Well-formed UUIDs that do not name anything, for the not-found paths.
const ABSENT_SERVER_ID = "00000000-0000-4000-8000-00000000dead";
const ABSENT_AUDIT_ID = "00000000-0000-4000-8000-00000000beef";

/** Counts fetch calls for the duration of `run`, restoring the original after. */
async function countingFetch<T>(run: () => Promise<T>): Promise<{ result: T; calls: number }> {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = ((...args: Parameters<typeof fetch>) => {
    calls += 1;
    return original(...args);
  }) as typeof fetch;
  try {
    const result = await run();
    return { result, calls };
  } finally {
    globalThis.fetch = original;
  }
}

/** Runs `run` with MANUFACT_API_KEY removed, restoring it after. */
async function withoutApiKey<T>(run: () => Promise<T>): Promise<T> {
  const saved = process.env.MANUFACT_API_KEY;
  delete process.env.MANUFACT_API_KEY;
  try {
    return await run();
  } finally {
    if (saved !== undefined) process.env.MANUFACT_API_KEY = saved;
  }
}

/** The audit created once by T1 and reused by T2, T3, T4, T5 and T10. */
let createdAuditId: string;
let startElapsedMs: number;

describe("AC1 — start_audit creates a real audit and returns fast", () => {
  before(() => {
    assert.ok(
      process.env.MANUFACT_API_KEY,
      "MANUFACT_API_KEY must be set to run the live tests",
    );
  });

  it("T1 returns an auditId and a non-terminal status", async () => {
    const began = Date.now();
    const result = await startAuditHandler({ serverId: SERVER_ID });
    startElapsedMs = Date.now() - began;

    assert.equal(result.isError, undefined, "start_audit must not error");
    const out = result.structuredContent as { auditId: string; status: string };

    assert.match(out.auditId, /^[0-9a-f-]{36}$/, "auditId must be a uuid");
    // An audit's `running` means in progress. A deployment's `running` means
    // settled. These vocabularies never share a terminal check.
    assert.ok(
      ["pending", "running"].includes(out.status),
      `a fresh audit must be non-terminal, got "${out.status}"`,
    );
    createdAuditId = out.auditId;
  });

  it("T2 the returned auditId names a real audit in the API", async () => {
    const audit = await fetchAudit(SERVER_ID, createdAuditId);
    assert.equal(audit.id, createdAuditId);
    assert.equal(audit.serverId, SERVER_ID);
  });

  it("T3 start_audit returns in under 10 seconds", () => {
    assert.ok(
      startElapsedMs < 10_000,
      `start_audit took ${startElapsedMs}ms, budget is 10000ms`,
    );
  });
});

describe("AC2 — get_audit validates and preserves every category", () => {
  let raw: Awaited<ReturnType<typeof fetchAudit>>;

  before(async () => {
    // Poll to completion. The tool itself never waits on an audit; this is the
    // test obtaining the completed audit that AC2 is stated against.
    const deadline = Date.now() + 180_000;
    for (;;) {
      raw = await fetchAudit(SERVER_ID, createdAuditId);
      if (raw.status === "completed" || raw.status === "failed") break;
      assert.ok(Date.now() < deadline, `audit did not settle within 180s (status ${raw.status})`);
      await new Promise((r) => setTimeout(r, 5_000));
    }
  });

  it("T4 structuredContent validates against outputSchema", async () => {
    const result = await getAuditHandler({ serverId: SERVER_ID, auditId: createdAuditId });
    assert.equal(result.isError, undefined);
    // Throws on mismatch, which is the assertion.
    auditOutputSchema.parse(result.structuredContent);
  });

  it("T5 checks[] carries every category string in the raw response", async () => {
    const result = await getAuditHandler({ serverId: SERVER_ID, auditId: createdAuditId });
    const out = result.structuredContent as { checks?: Array<{ category: string }> };

    // Guard against a vacuous pass: with no checks on either side the deepEqual
    // below compares [] with [] and proves nothing about preservation.
    //
    // The status is asserted separately so the diagnosis points at the right
    // subsystem. The before() hook exits on `failed` as well as `completed`, so
    // a 502 at the target endpoint would otherwise surface here as a complaint
    // about mapping fidelity.
    assert.equal(
      raw.status,
      "completed",
      `the audit settled at "${raw.status}" — the audit run failed, not the mapping`,
    );
    assert.ok(
      (raw.checks ?? []).length > 0,
      "a completed audit must carry checks for this assertion to mean anything",
    );

    const rawCategories = (raw.checks ?? []).map((c) => c.category).sort();
    const outCategories = (out.checks ?? []).map((c) => c.category).sort();

    assert.deepEqual(
      outCategories,
      rawCategories,
      "every category in the API response must survive the mapping, unchanged",
    );
  });
});

describe("AC3 — an unknown category survives", () => {
  it("T6 preserves a category the code has never seen", () => {
    const unknown = "totally-unheard-of-category";
    const payload = {
      id: "aud_1",
      serverId: SERVER_ID,
      deploymentId: null,
      organizationId: "org_1",
      targetUrl: `${MCP_ORIGIN}/mcp`,
      gitBranch: null,
      status: "completed",
      durationMs: 1234,
      errorMessage: null,
      isReadyForChatgpt: true,
      isReadyForClaudeai: true,
      startedAt: "2026-08-30T00:00:00Z",
      completedAt: "2026-08-30T00:00:01Z",
      createdAt: "2026-08-30T00:00:00Z",
      checks: [
        {
          id: "chk_1",
          auditId: "aud_1",
          checkId: "some-check",
          checkName: "Some check",
          status: "fail",
          severity: "whatever-severity",
          category: unknown,
          scope: "whatever-scope",
          platforms: ["chatgpt"],
          message: null,
          // Untyped in the spec: anyOf [{}, null]. A non-string must survive.
          details: { nested: { count: 3 } },
          hint: 42,
          durationMs: 5,
          createdAt: "2026-08-30T00:00:01Z",
        },
      ],
    };

    const mapped = mapAuditResponse(payload);
    auditOutputSchema.parse(mapped);

    assert.equal(mapped.targetUrl, `${MCP_ORIGIN}/mcp`, "targetUrl must survive the mapping");
    assert.equal(mapped.checks?.[0]?.category, unknown, "category must not be dropped or coerced");
    assert.equal(mapped.checks?.[0]?.severity, "whatever-severity");
    assert.deepEqual(mapped.checks?.[0]?.details, { nested: { count: 3 } });
    assert.equal(mapped.checks?.[0]?.hint, 42, "an untyped hint must not be stringified");
  });
});

describe("a failed audit keeps the reason it failed", () => {
  it("carries errorMessage through when the audit failed and produced no checks", () => {
    // The state the suite never reached live: `failed`, with `checks` absent —
    // which the spec permits, since checks is not in the required list. Before
    // errorMessage was mapped, this returned a bare "it failed" with the cause
    // the API had supplied thrown away.
    const mapped = mapAuditResponse({
      id: "aud_failed",
      serverId: SERVER_ID,
      deploymentId: null,
      organizationId: "org_1",
      targetUrl: `${MCP_ORIGIN}/mcp`,
      gitBranch: null,
      status: "failed",
      durationMs: 900,
      errorMessage: "target returned 502",
      isReadyForChatgpt: null,
      isReadyForClaudeai: null,
      startedAt: "2026-08-30T00:00:00Z",
      completedAt: "2026-08-30T00:00:01Z",
      createdAt: "2026-08-30T00:00:00Z",
    });

    auditOutputSchema.parse(mapped);
    assert.equal(mapped.status, "failed");
    assert.equal(mapped.errorMessage, "target returned 502", "the cause must reach the caller");
    assert.equal(mapped.checks, undefined, "absent checks stay absent, never coerced to []");
  });
});

describe("AC4 — invalid ids surface as tool errors", () => {
  it("T7 start_audit with an absent serverId returns a tool error", async () => {
    const result = await startAuditHandler({ serverId: ABSENT_SERVER_ID });
    assert.equal(result.isError, true, "the failure must surface, not be swallowed");
    const text = result.content?.map((c) => ("text" in c ? c.text : "")).join(" ") ?? "";
    assert.ok(text.length > 0, "a tool error must carry a model-readable message");
  });

  it("T8 get_audit with an absent auditId returns a tool error", async () => {
    const result = await getAuditHandler({ serverId: SERVER_ID, auditId: ABSENT_AUDIT_ID });
    assert.equal(result.isError, true);
    const text = result.content?.map((c) => ("text" in c ? c.text : "")).join(" ") ?? "";
    assert.ok(text.length > 0);
  });

  it("T9 a failing call issues exactly one request — no retry", async () => {
    const { result, calls } = await countingFetch(() =>
      getAuditHandler({ serverId: SERVER_ID, auditId: ABSENT_AUDIT_ID }),
    );
    assert.equal(result.isError, true);
    assert.equal(calls, 1, `expected exactly one request, saw ${calls} — a retry is a defect`);
  });
});

describe("AC5 — the audit targets this server's own endpoint", () => {
  it("T10 targetUrl equals MCP_URL + /mcp and the server record's mcpUrl", async () => {
    const audit = await fetchAudit(SERVER_ID, createdAuditId);

    // Derived from live data, not from a constant typed into this file: the
    // server record is the API's own statement of where this server answers.
    const server = await fetchServer(SERVER_ID);
    assert.equal(
      audit.targetUrl,
      server.mcpUrl,
      "the audit must target the endpoint the server record advertises",
    );

    // MCP_URL is injected by the deploy pipeline as the origin, with no /mcp
    // suffix. The constant is the documented origin and is asserted to agree
    // with the live record, so a drifted deployment fails here rather than
    // passing against a stale literal.
    const origin = process.env.MCP_URL ?? MCP_ORIGIN;
    assert.equal(server.mcpUrl, `${origin}/mcp`);
    assert.equal(audit.targetUrl, `${origin}/mcp`);
  });
});

describe("AC6 — an absent API key fails closed before any request", () => {
  it("T11 start_audit errors and sends nothing", async () => {
    const { result, calls } = await withoutApiKey(() =>
      countingFetch(() => startAuditHandler({ serverId: SERVER_ID })),
    );
    assert.equal(result.isError, true);
    assert.equal(calls, 0, "no request may leave the process without a key");
    const text = result.content?.map((c) => ("text" in c ? c.text : "")).join(" ") ?? "";
    assert.match(text, /MANUFACT_API_KEY/, "the message must name what is missing");
  });

  it("T12 get_audit errors and sends nothing", async () => {
    const { result, calls } = await withoutApiKey(() =>
      countingFetch(() => getAuditHandler({ serverId: SERVER_ID, auditId: ABSENT_AUDIT_ID })),
    );
    assert.equal(result.isError, true);
    assert.equal(calls, 0);
    const text = result.content?.map((c) => ("text" in c ? c.text : "")).join(" ") ?? "";
    assert.match(text, /MANUFACT_API_KEY/);
  });
});

describe("guards that hold across the suite", () => {
  it("requireApiKey throws when the key is absent and returns it when present", async () => {
    await withoutApiKey(async () => {
      assert.throws(() => requireApiKey(), /MANUFACT_API_KEY/);
    });
    assert.equal(typeof requireApiKey(), "string");
  });

  it("resolveActiveDeploymentId returns the server's active deployment", async () => {
    const id = await resolveActiveDeploymentId(SERVER_ID);
    assert.match(String(id), /^[0-9a-f-]{36}$/);
  });

  it("createAudit posts an audit bound to the deployment it is given", async () => {
    const deploymentId = await resolveActiveDeploymentId(SERVER_ID);
    const created = await createAudit(SERVER_ID, deploymentId);

    assert.match(created.id, /^[0-9a-f-]{36}$/);
    assert.ok(["pending", "running"].includes(created.status));

    // The binding is the point of resolving the deployment at all: assert the
    // audit actually carries it, rather than that the function exists.
    //
    // Known limit: the only deployment id available here is the active one, and
    // the API binds that by itself when the body omits deploymentId. So this
    // would still pass if createAudit sent `{}` — D2's rejected runner-up.
    // Distinguishing the two needs a non-active deployment id, which this
    // server does not have. Strictly stronger than the assertion it replaced,
    // but not proof that the id was sent.
    const audit = await fetchAudit(SERVER_ID, created.id);
    assert.equal(audit.deploymentId, deploymentId);
  });
});

after(() => {
  // Nothing to tear down: the audit created by T1 is a real record and is left
  // in place deliberately, as evidence for the PR.
});
