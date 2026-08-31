// audit-report-view.test.ts — the ten tests frozen at Gate A.
//
// Run: npm test   (node --test)
//
// These are Default-FAIL: views/audit-report/report.ts does not exist on main,
// so every test in this file fails at import until S3 creates it.
//
// Scope, stated so the coverage claim is not read as stronger than it is:
// these cover the pure transforms only. node:test cannot mount React without a
// DOM, and adding a testing library would trip the new-dependency lock. AC1,
// AC5 and AC7 are properties of the host, the wire and the browser — they are
// demonstrated by reading tools/list from the deployed endpoint and by opening
// the view in the Inspector at S5.

import { strict as assert } from "node:assert";
import { describe, it } from "node:test";

import {
  categoryRank,
  groupByCategory,
  isTerminal,
  nextPollDelay,
  readinessLabel,
  refreshArgs,
  summarize,
} from "../views/audit-report/report.ts";

/** A check shaped like the live API's, with only the fields the view reads. */
const check = (category: string, over: Record<string, unknown> = {}) => ({
  id: `chk_${category}_${Math.random().toString(36).slice(2, 8)}`,
  checkId: "some-check",
  checkName: "Some check",
  status: "pass",
  severity: "info",
  category,
  scope: "server",
  platforms: ["chatgpt"],
  message: null,
  details: null,
  hint: null,
  durationMs: 1,
  ...over,
});

// The four slugs a real audit of this server actually returned. Not the six
// documented prose names — that is the whole point of deriving them.
const LIVE = ["connectivity", "tool-metadata", "client-compatibility", "resource-metadata"];

describe("AC2 — grouping is derived from the data", () => {
  it("T1 returns one group per distinct category", () => {
    const groups = groupByCategory([
      check("connectivity"),
      check("connectivity"),
      check("tool-metadata"),
    ]);
    assert.equal(groups.length, 2);
    assert.deepEqual(
      groups.map((g) => g.category).sort(),
      ["connectivity", "tool-metadata"],
    );
    assert.equal(groups.find((g) => g.category === "connectivity")?.checks.length, 2);
  });

  it("T2 preserves an unknown slug verbatim as its group key", () => {
    const unknown = "totally-unheard-of-category";
    const groups = groupByCategory([check(unknown), check("connectivity")]);
    const found = groups.find((g) => g.category === unknown);
    assert.ok(found, "the unknown category must survive as its own group");
    assert.equal(found.category, unknown, "the slug must not be renamed or prettified");
  });

  it("T3 orders known categories by the lookup and unknown ones after, alphabetically", () => {
    const groups = groupByCategory([
      check("zzz-unknown"),
      check("aaa-unknown"),
      ...LIVE.map((c) => check(c)),
    ]);
    const order = groups.map((g) => g.category);

    const knownPositions = LIVE.map((c) => order.indexOf(c));
    const unknownPositions = ["aaa-unknown", "zzz-unknown"].map((c) => order.indexOf(c));

    assert.ok(
      Math.max(...knownPositions) < Math.min(...unknownPositions),
      "every known category must sort before every unknown one",
    );
    assert.ok(
      order.indexOf("aaa-unknown") < order.indexOf("zzz-unknown"),
      "unknown categories sort alphabetically among themselves",
    );
    // The lookup must give a rank to what it knows and a fallback to what it does not.
    assert.ok(Number.isFinite(categoryRank("connectivity")));
    assert.ok(categoryRank("totally-unheard-of-category") > categoryRank("connectivity"));
  });

  it("T4 places every input check in exactly one group", () => {
    const checks = [
      ...LIVE.map((c) => check(c)),
      check("connectivity"),
      check("brand-new-slug"),
    ];
    const groups = groupByCategory(checks);
    const regrouped = groups.flatMap((g) => g.checks);
    assert.equal(regrouped.length, checks.length, "no check dropped or duplicated");
    assert.deepEqual(
      regrouped.map((c) => c.id).sort(),
      checks.map((c) => c.id).sort(),
    );
  });

  it("T9 distinguishes absent checks from empty checks", () => {
    const absent = summarize({ status: "running", checks: undefined });
    const empty = summarize({ status: "completed", checks: [] });
    assert.notDeepEqual(
      absent.checksState,
      empty.checksState,
      "absent and empty must not collapse into the same state",
    );
    assert.equal(absent.checksState, "absent");
    assert.equal(empty.checksState, "empty");
  });
});

describe("AC4 — readiness badges", () => {
  it("T5 maps true, false and null to ready, not ready and unknown", () => {
    assert.equal(readinessLabel(true), "ready");
    assert.equal(readinessLabel(false), "not ready");
    assert.equal(readinessLabel(null), "unknown");
    assert.notEqual(
      readinessLabel(null),
      readinessLabel(false),
      "null must never render as false",
    );
  });
});

describe("AC3 — polling stops when the audit settles", () => {
  it("T6 treats completed and failed as terminal, pending and running as not", () => {
    assert.equal(isTerminal("completed"), true);
    assert.equal(isTerminal("failed"), true);
    // An audit's `running` means in progress. A deployment's means settled.
    // These vocabularies never share a terminal check.
    assert.equal(isTerminal("running"), false);
    assert.equal(isTerminal("pending"), false);
  });

  it("T7 returns null once terminal and once the deadline passes", () => {
    assert.equal(nextPollDelay({ status: "completed", elapsedMs: 0 }), null);
    assert.equal(nextPollDelay({ status: "failed", elapsedMs: 0 }), null);

    const early = nextPollDelay({ status: "running", elapsedMs: 0 });
    assert.ok(typeof early === "number" && early > 0, "a live audit keeps polling");

    assert.equal(
      nextPollDelay({ status: "running", elapsedMs: 10 * 60 * 1000 }),
      null,
      "an audit that never settles must stop being polled",
    );
  });

  it("T8 builds refresh arguments from toolInput and toolOutput", () => {
    const args = refreshArgs(
      { serverId: "a9f68f45-7160-4b30-8855-06399bd6aebb" },
      { auditId: "0ed76eb3-ab02-4bd6-b618-0705cfa7db4b", status: "pending" },
    );
    assert.deepEqual(args, {
      serverId: "a9f68f45-7160-4b30-8855-06399bd6aebb",
      auditId: "0ed76eb3-ab02-4bd6-b618-0705cfa7db4b",
    });

    // Without both ids there is nothing to call, and inventing one would be a
    // fallback. Absent input must yield no arguments rather than a guess.
    assert.equal(refreshArgs(undefined, undefined), null);
    assert.equal(refreshArgs({ serverId: "s" }, undefined), null);
  });
});

describe("AC6 — a failed audit shows why", () => {
  it("T10 surfaces errorMessage on a failed audit", () => {
    const failed = summarize({
      status: "failed",
      errorMessage: "target returned 502",
      checks: undefined,
    });
    assert.equal(failed.errorMessage, "target returned 502");
    assert.equal(failed.isFailed, true);

    const ok = summarize({ status: "completed", errorMessage: null, checks: [] });
    assert.equal(ok.isFailed, false);
    assert.equal(ok.errorMessage, null);
  });
});
