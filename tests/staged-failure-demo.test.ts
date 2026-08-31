// staged-failure-demo.test.ts — the seven tests frozen at Gate A for G4.
//
// Run: npm test   (node --test)
//
// Default-FAIL: `docs/demo/` does not exist on main, so every test in this file
// fails at the first read until S3 and S5 capture the assets.
//
// Scope, stated so the coverage claim is not read as stronger than it is:
// these pin that the committed evidence is internally consistent, is bound to
// the audit ids it claims, and says what the README says. They cannot prove the
// deployment really went red and back to green — that is a live property. What
// stands behind it is the PR trail, the deployment history, and the audit ids,
// every one of which can be refetched from Manufact's API by someone who does
// not trust this repository.

import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

const DEMO = new URL("../docs/demo/", import.meta.url);
const PRODUCTION = "https://mcp-readycheck.run.mcp-use.com/mcp";

/** The SDK gap recorded in G3: no code path in mcp-use 2.3.3 can satisfy it. */
const SDK_GAP = "tool-resource-metadata-complete";

/** The check the break is designed to trip. */
const STAGED = "tool-hints-present";

/** The green baseline, from STAGE-PLAN correction 25. */
const BASELINE_ID = "f4022c88";
const BASELINE_CHECKS = 32;
const BASELINE_PASSING = 31;

interface Check {
  checkId: string;
  status: string;
  severity: string;
  message: string | null;
}

interface Capture {
  auditId: string;
  status: string;
  isReadyForChatgpt: boolean | null;
  isReadyForClaudeai: boolean | null;
  targetUrl: string;
  checks?: Check[];
}

function capture(name: string): Capture {
  return JSON.parse(readFileSync(new URL(name, DEMO), "utf8")) as Capture;
}

const checkNamed = (c: Capture, id: string) =>
  (c.checks ?? []).find((x) => x.checkId === id);

const failing = (c: Capture) =>
  (c.checks ?? []).filter((x) => x.status !== "pass").map((x) => x.checkId).sort();

describe("AC1/AC2 — the captures are real audits", () => {
  it("T1 both captures parse and carry a settled audit with checks", () => {
    for (const name of ["audit-red.json", "audit-green.json"]) {
      const c = capture(name);
      assert.ok(c.auditId, `${name}: no auditId`);
      assert.equal(c.status, "completed", `${name}: audit did not settle`);
      assert.ok(c.targetUrl, `${name}: no targetUrl`);
      assert.ok(Array.isArray(c.checks), `${name}: checks is not an array`);
      assert.ok((c.checks ?? []).length > 0, `${name}: no checks recorded`);
    }
    // Two different audits, not one file copied twice.
    assert.notEqual(
      capture("audit-red.json").auditId,
      capture("audit-green.json").auditId,
      "red and green name the same audit",
    );
  });
});

describe("AC1 — the break was caught", () => {
  it("T2 the red capture fails the staged check and is not ChatGPT-ready", () => {
    const red = capture("audit-red.json");
    const staged = checkNamed(red, STAGED);
    assert.ok(staged, `${STAGED} is absent from the red capture`);
    assert.equal(staged?.status, "fail", `${STAGED} did not fail`);
    assert.equal(
      staged?.severity,
      "error",
      "the staged check must be error severity — a warning does not gate readiness",
    );
    assert.equal(red.isReadyForChatgpt, false, "the break did not turn the flag false");
  });
});

describe("AC2 — the revert restored the baseline", () => {
  it("T3 the green capture is ready on both platforms", () => {
    const green = capture("audit-green.json");
    assert.equal(green.isReadyForChatgpt, true);
    assert.equal(green.isReadyForClaudeai, true);
    assert.deepEqual(
      failing(green),
      [SDK_GAP],
      "the only check still failing must be the recorded SDK gap",
    );
  });

  it("T4 every check matches the recorded baseline, with zero deviations", () => {
    const green = capture("audit-green.json");
    const base = capture("baseline-f4022c88.json");

    // Bind the file to the audit it claims to be, before comparing anything
    // against it. Without this the test is circular: copying audit-green.json
    // over the baseline filename would compare the green capture with itself
    // and report zero deviations. The id is refetchable from Manufact's API by
    // anyone; the counts are recorded in STAGE-PLAN correction 25.
    assert.ok(
      base.auditId.startsWith(BASELINE_ID),
      `the baseline file is audit ${base.auditId}, not ${BASELINE_ID}`,
    );
    assert.notEqual(base.auditId, green.auditId, "the baseline is the green capture");
    assert.equal(
      (base.checks ?? []).length,
      BASELINE_CHECKS,
      `the baseline is not ${BASELINE_CHECKS} checks`,
    );
    assert.equal(
      (base.checks ?? []).filter((x) => x.status === "pass").length,
      BASELINE_PASSING,
      `the baseline is not ${BASELINE_PASSING} pass`,
    );
    assert.deepEqual(
      failing(base),
      [SDK_GAP],
      "the baseline's one failure is not the SDK gap",
    );

    const byId = (c: Capture) =>
      new Map((c.checks ?? []).map((x) => [x.checkId, x.status]));
    const g = byId(green);
    const b = byId(base);

    const deviations: string[] = [];
    for (const id of new Set([...g.keys(), ...b.keys()])) {
      const before = b.get(id) ?? "(absent)";
      const after = g.get(id) ?? "(absent)";
      if (before !== after) deviations.push(`${id}: ${before} -> ${after}`);
    }
    assert.deepEqual(deviations, [], "the green audit deviates from the baseline");
    assert.equal(g.size, b.size, "the check count changed");
  });
});

describe("AC3 — the SDK gap was neither target nor casualty", () => {
  it("T5 it is identical on both sides of the break", () => {
    const red = checkNamed(capture("audit-red.json"), SDK_GAP);
    const green = checkNamed(capture("audit-green.json"), SDK_GAP);
    assert.ok(red, `${SDK_GAP} is absent from the red capture`);
    assert.ok(green, `${SDK_GAP} is absent from the green capture`);
    assert.equal(red?.status, green?.status);
    assert.equal(red?.severity, green?.severity);
    assert.equal(red?.message, green?.message);
  });
});

describe("AC4 — every capture came from the live deployment", () => {
  it("T6 both name the production endpoint and neither names localhost", () => {
    for (const name of ["audit-red.json", "audit-green.json", "baseline-f4022c88.json"]) {
      const c = capture(name);
      assert.equal(c.targetUrl, PRODUCTION, `${name}: not the production endpoint`);
      assert.ok(!/localhost|127\.0\.0\.1/.test(c.targetUrl), `${name}: local capture`);
    }
  });
});

describe("AC5 — the narrative points at the evidence", () => {
  it("T7 the README carries both audit ids and both PR links", () => {
    const readme = readFileSync(new URL("README.md", DEMO), "utf8");
    const red = capture("audit-red.json");
    const green = capture("audit-green.json");

    assert.ok(readme.includes(red.auditId), "the README does not name the red audit");
    assert.ok(readme.includes(green.auditId), "the README does not name the green audit");

    // Two distinct PR numbers, so a README citing the same PR twice fails.
    const prs = new Set(
      [...readme.matchAll(/mcp-readycheck\/pull\/(\d+)/g)].map((m) => m[1]),
    );
    assert.ok(
      prs.size >= 2,
      `the README must link the break PR and the revert PR; found ${prs.size}`,
    );
  });
});
