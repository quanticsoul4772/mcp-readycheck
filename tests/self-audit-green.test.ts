// self-audit-green.test.ts — the eight tests frozen at Gate A for G3.
//
// Run: npm test   (node --test)
//
// Default-FAIL: none of `TOOL_DEFINITIONS`, `startAuditInputSchema`,
// `getAuditInputSchema` or `humanError` is exported on main, so every test in
// this file fails at import until S3 adds them.
//
// Scope, stated so the coverage claim is not read as stronger than it is:
// these pin what the repo controls — the tool definitions the server registers
// and the text this code produces on bad input. Whether the live audit then
// scores those checks as passing is a property of the deployed server and of
// Manufact's auditor, demonstrated at S5 against the live endpoint, not here.

import { strict as assert } from "node:assert";
import { after, before, describe, it } from "node:test";

import { humanError, ManufactApiError, MissingApiKeyError } from "#lib/manufact";
import * as entry from "../index.ts";
import {
  getAuditInputSchema,
  startAuditHandler,
  startAuditInputSchema,
  TOOL_DEFINITIONS,
} from "../index.ts";

/** A key-shaped sentinel, so "never leaks the key" is checked against a real value. */
const SENTINEL_KEY = "mk_live_sentinel_do_not_leak";

/**
 * Zod 4's default issue text. A message matching any of these is the framework
 * talking, which is exactly what the fuzz check reads as a raw error.
 */
const ZOD_DEFAULT_TEXT = [
  /too small/i,
  /too big/i,
  /invalid input/i,
  /expected string/i,
  /received undefined/i,
  /^required$/i,
];

/** Every message an invalid input produces, flattened. */
function messagesFor(schema: { safeParse: (v: unknown) => unknown }, value: unknown): string[] {
  const result = schema.safeParse(value) as {
    success: boolean;
    error?: { issues: { message: string }[] };
  };
  assert.equal(result.success, false, `expected ${JSON.stringify(value)} to be rejected`);
  return (result.error?.issues ?? []).map((issue) => issue.message);
}

const definitionNamed = (name: string) => {
  const found = TOOL_DEFINITIONS.find((d) => d.name === name);
  assert.ok(found, `no registered definition named ${name}`);
  return found;
};

describe("AC1 — the annotations describe what the tools actually do", () => {
  it("T1 declares all three booleans, and no read-only tool claims the open world", () => {
    assert.ok(TOOL_DEFINITIONS.length > 0, "no tool definitions were exported");

    for (const def of TOOL_DEFINITIONS) {
      const a = def.annotations;
      assert.ok(a, `${def.name} declares no annotations`);
      for (const key of ["readOnlyHint", "destructiveHint", "openWorldHint"] as const) {
        assert.equal(typeof a?.[key], "boolean", `${def.name}.${key} is not a boolean`);
      }
      if (a?.readOnlyHint === true) {
        assert.equal(
          a.openWorldHint,
          false,
          `${def.name} is read-only yet claims openWorldHint — a read changes no ` +
            `publicly visible state and submits to no third party`,
        );
      }
    }
  });

  it("T4 registers the readiness tools and nothing else", () => {
    assert.deepEqual(
      TOOL_DEFINITIONS.map((d) => d.name).sort(),
      ["get_audit", "start_audit"],
      "the scaffold tools are still registered",
    );
    // The refs too: an unexported leftover would still mount.
    assert.equal((entry as Record<string, unknown>).showApp, undefined);
    assert.equal((entry as Record<string, unknown>).sayHello, undefined);
  });
});

describe("AC5 — the view-bound tool carries the metadata a host reads", () => {
  it("T2 declares openai/toolInvocation with both present-tense labels", () => {
    const meta = definitionNamed("start_audit")._meta as
      | Record<string, { invoking?: unknown; invoked?: unknown }>
      | undefined;
    const invocation = meta?.["openai/toolInvocation"];
    assert.ok(invocation, "start_audit carries no openai/toolInvocation metadata");

    for (const field of ["invoking", "invoked"] as const) {
      const value = invocation?.[field];
      assert.equal(typeof value, "string", `${field} is not a string`);
      assert.ok((value as string).trim().length > 0, `${field} is empty`);
    }
  });

  it("T3 binds the view to one bare HTTPS origin", () => {
    const view = definitionNamed("start_audit").view;
    assert.ok(view, "start_audit is not bound to a view");
    const domain = view?.domain;
    assert.equal(typeof domain, "string", "the view declares no domain");
    // Origin only. A path, a trailing slash or a non-https scheme is rejected
    // by the audit's own wording: "Paths are not valid".
    assert.match(
      domain as string,
      /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?$/i,
      `${domain} is not a bare HTTPS origin`,
    );
  });
});

describe("AC4 — bad input gets guidance, never internals", () => {
  it("T5 answers every rejected input in our own words", () => {
    const cases: [string, { safeParse: (v: unknown) => unknown }, unknown][] = [
      ["start_audit empty serverId", startAuditInputSchema, { serverId: "" }],
      ["start_audit missing serverId", startAuditInputSchema, {}],
      ["start_audit wrong type", startAuditInputSchema, { serverId: 42 }],
      ["get_audit empty auditId", getAuditInputSchema, { serverId: "s", auditId: "" }],
      ["get_audit missing auditId", getAuditInputSchema, { serverId: "s" }],
      ["get_audit wrong type", getAuditInputSchema, { serverId: "s", auditId: null }],
    ];

    for (const [label, schema, value] of cases) {
      const messages = messagesFor(schema, value);
      assert.ok(messages.length > 0, `${label}: rejected with no message at all`);
      for (const message of messages) {
        assert.ok(message.trim().length > 0, `${label}: empty message`);
        for (const pattern of ZOD_DEFAULT_TEXT) {
          assert.ok(
            !pattern.test(message),
            `${label}: default schema text reached the caller — ${message}`,
          );
        }
      }
    }
  });

  it("T6 rewrites an API failure into a remedy with no path and no status code", () => {
    const raw = new ManufactApiError(
      404,
      "/api/v1/servers/not-a-uuid",
      "Manufact API returned 404 for /api/v1/servers/not-a-uuid: Server not found",
    );
    const text = humanError(raw);

    assert.equal(typeof text, "string");
    assert.ok(text.trim().length >= 20, "the rewritten message says almost nothing");
    assert.ok(!text.includes("/api/"), `an API path survived: ${text}`);
    assert.ok(!/\b[45]\d{2}\b/.test(text), `an HTTP status code survived: ${text}`);
    assert.notEqual(text, raw.message, "the raw message was passed straight through");
    assert.match(text, /check|verify|confirm|make sure|try/i, "no remedy is offered");
  });

  it("T7 never emits the key, and keeps the missing-key guidance intact", () => {
    const previous = process.env.MANUFACT_API_KEY;
    process.env.MANUFACT_API_KEY = SENTINEL_KEY;
    try {
      const withKeyInside = new ManufactApiError(
        401,
        `/api/v1/servers/x?token=${SENTINEL_KEY}`,
        `Manufact API returned 401 for /api/v1/servers/x?token=${SENTINEL_KEY}`,
      );
      assert.ok(
        !humanError(withKeyInside).includes(SENTINEL_KEY),
        "the API key reached a tool-visible message",
      );

      // MissingApiKeyError is already caller-facing guidance about an operator
      // action. Rewriting it away would lose the only actionable thing it says.
      const missing = humanError(new MissingApiKeyError());
      assert.ok(missing.includes("MANUFACT_API_KEY"), "the missing-key guidance was lost");
      assert.ok(!missing.includes(SENTINEL_KEY), "the missing-key guidance leaked the key");
    } finally {
      if (previous === undefined) process.env.MANUFACT_API_KEY = "";
      else process.env.MANUFACT_API_KEY = previous;
    }
  });
});

describe("AC4 — rewriting a message never hides the failure", () => {
  const originalFetch = globalThis.fetch;
  const previousKey = process.env.MANUFACT_API_KEY;

  before(() => {
    process.env.MANUFACT_API_KEY = SENTINEL_KEY;
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ error: "Server not found" }), {
        status: 404,
        headers: { "content-type": "application/json" },
      })) as typeof fetch;
  });

  after(() => {
    globalThis.fetch = originalFetch;
    if (previousKey === undefined) process.env.MANUFACT_API_KEY = "";
    else process.env.MANUFACT_API_KEY = previousKey;
  });

  it("T8 returns isError with readable text on a failed API call", async () => {
    const result = (await startAuditHandler({ serverId: "not-a-uuid" })) as {
      isError?: boolean;
      content?: { type: string; text: string }[];
    };

    assert.equal(result.isError, true, "a 404 was reported as success");
    const text = result.content?.[0]?.text ?? "";
    assert.ok(text.trim().length > 0, "the error result carries no text");
    assert.ok(!text.includes("/api/"), `an API path reached the model: ${text}`);
    assert.ok(!text.includes(SENTINEL_KEY), "the API key reached the model");
  });
});
