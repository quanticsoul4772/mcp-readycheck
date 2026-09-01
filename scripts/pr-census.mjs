// Regenerates docs/pr-census.json from the GitHub API.
//
//     node scripts/pr-census.mjs > docs/pr-census.json
//
// The README quotes these figures and tests/submission.test.ts asserts the
// README against the committed file — never against the live API. The counts
// move whenever a pull request is opened or merged, including the one that
// commits this file, so README and fixture are generated in the same commit and
// the README says "as of this commit". A reviewer who runs the command above
// gets a larger number and can see exactly why.
import { execFileSync } from "node:child_process";

const raw = execFileSync(
  "gh",
  ["pr", "list", "--state", "all", "--limit", "200", "--json",
   "number,title,state,body,statusCheckRollup"],
  { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
);
const prs = JSON.parse(raw);

/** The verdict check's LATEST run. Taking the first inverts seven of them. */
function verdictRuns(pr) {
  return (pr.statusCheckRollup ?? [])
    .filter((c) => (c.name ?? c.context) === "verdict")
    .sort((a, b) => String(a.completedAt ?? "").localeCompare(String(b.completedAt ?? "")))
    .map((r) => r.conclusion ?? r.state);
}
const latest = (pr) => verdictRuns(pr).at(-1) ?? "ABSENT";
const APPROVING = /"verdict"\s*:\s*"(APPROVE|APPROVE-WITH-NOTES)"/;
const nums = (list) => list.map((p) => p.number).sort((a, b) => a - b);

const merged = prs.filter((p) => p.state === "MERGED");
const passed = merged.filter((p) => latest(p) === "SUCCESS");

process.stdout.write(JSON.stringify({
  regenerateWith: "node scripts/pr-census.mjs > docs/pr-census.json",
  note: "A pull request's gate result is its LATEST verdict check run. Taking the first inverts seven of them, because a PR opened before its verdict is in the body goes red and then green when the body is edited.",
  prsOpened: prs.length,
  merged: merged.length,
  closedUnmerged: nums(prs.filter((p) => p.state === "CLOSED")),
  open: nums(prs.filter((p) => p.state === "OPEN")),
  mergedGatePassed: passed.length,
  mergedGatePassedCarryingVerdict: nums(passed.filter((p) => APPROVING.test(p.body ?? ""))),
  mergedGatePassedByDocsExemption: nums(passed.filter((p) => !APPROVING.test(p.body ?? ""))),
  mergedOverRedGate: nums(merged.filter((p) => latest(p) === "FAILURE")),
  mergedBeforeGateExisted: nums(merged.filter((p) => latest(p) === "ABSENT")),
  redThenGreen: nums(merged.filter((p) => {
    const r = verdictRuns(p);
    return r.length > 1 && r[0] === "FAILURE" && r.at(-1) === "SUCCESS";
  })),
  // HAND-ENTERED, not derived. A BLOCK that was overridden leaves no trace the
  // API can be asked for: #8's verdict arrived 72 seconds after the merge and
  // exists only in a session record, and #10's is recorded in prose in PR #11's
  // body ("The fourth evaluation returned BLOCK on b2ccaf8"). Everything else in
  // this file is computed; this field is a claim, and the README links both PRs
  // so a reader can check it rather than take it.
  mergedOverLiveBlock: [8, 10],
  approvingVerdictObjects: prs.reduce(
    (n, p) => n + (String(p.body ?? "").match(new RegExp(APPROVING.source, "g")) ?? []).length, 0),
  prsCarryingAnApprovingVerdict: prs.filter((p) => APPROVING.test(p.body ?? "")).length,
  blockVerdictObjects: prs
    .filter((p) => /"verdict"\s*:\s*"BLOCK"/.test(p.body ?? ""))
    .map((p) => ({ pr: p.number, state: p.state, title: p.title })),
}, null, 2) + "\n");
