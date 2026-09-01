// scratch-discovery-proof.test.ts — TEMPORARY. Removed in the same PR.
//
// Exists to prove one thing by execution rather than by reading: a test file
// that nobody added to any list is discovered and run. Under the previous
// enumeration this file would have been invisible to CI.

import { strict as assert } from "node:assert";
import { it } from "node:test";

it("a newly added test file is discovered and executed", () => {
  assert.equal(1 + 1, 2);
});
