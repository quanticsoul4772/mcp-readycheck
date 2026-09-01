// run-tests.mjs — discovers the test files instead of enumerating them.
//
// Why this exists. Both npm scripts used to list their files by hand, and no CI
// job ran the full glob, so a pull request adding `tests/foo.test.ts` went green
// with that file never executed. `tests-guard.sh` deliberately permits creating
// a new unapproved test file, so that was a reachable path rather than a
// hypothetical.
//
// The rule is default-include: every discovered file is PURE unless it is named
// in LIVE. A new test file therefore runs in CI the moment it is committed.
//
// The live set is named rather than derived from a filename convention because
// the alternative meant `git mv`-ing a file that `.tests-locked` protects.
// Feeding tests-guard.sh a constructed payload shows it exits 0 on that move and
// 2 on a Write to the same path — measured while writing this, and recorded
// nowhere else; STAGE-PLAN correction 38 is about a different asymmetry, between
// creating an unapproved test and revising one. An absent guard is a stop, not an
// allowance. A header marker was the other option the goal offered; it needs a
// write to that same locked file. `check` therefore verifies the split by
// behavior instead of by name — see mode "check" below.
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, posix, relative, sep } from "node:path";
import process from "node:process";

// `new URL("..", import.meta.url).pathname` is percent-encoded: a checkout under
// a directory containing a space arrives as `g6%20probe` and every readdir
// throws ENOENT. fileURLToPath is the API that decodes.
const ROOT = fileURLToPath(new URL("..", import.meta.url));
const TESTS = join(ROOT, "tests");

/**
 * Files that reach the Manufact API and need MANUFACT_API_KEY.
 *
 * Adding a file here removes it from every job CI runs, so `check` refuses to
 * take the claim on trust: each named file must fail without a key and say the
 * key is what it is missing, and every other file must pass without one.
 */
const LIVE = new Set(["tests/readiness-tool.test.ts"]);

/**
 * What counts as a test file.
 *
 * `.test.ts` alone was too narrow: a committed `tests/x.test.tsx` was invisible
 * to the walk, to the index cross-check and to every suite, while `check` still
 * exited 0. views/audit-report/view.tsx is this repo's known untested surface,
 * and a DOM test for it would carry exactly that extension.
 *
 * Being discovered is not the same as being runnable. Node's strip-only mode
 * cannot parse JSX, so a `.tsx` test is found and then fails with
 * ERR_UNKNOWN_FILE_EXTENSION. That is the intended trade — loud over invisible —
 * but do not read this list as support for writing one.
 */
const TEST_FILE = /\.(test|spec)\.[cm]?[jt]sx?$/;

/** Every test file under tests/, recursively, as repo-relative posix paths. */
function discover(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      out.push(...discover(full));
    } else if (TEST_FILE.test(entry)) {
      out.push(relative(ROOT, full).split(sep).join(posix.sep));
    }
  }
  return out.sort();
}

/** The same question asked of git rather than of the filesystem. */
function trackedTests() {
  // Repo-wide, not tests/-only: a test file committed anywhere else is executed
  // by nothing at all, and asking git only about tests/ would never see it.
  const r = spawnSync("git", ["-C", ROOT, "ls-files", "*.test.*", "*.spec.*"], {
    encoding: "utf8",
  });
  if (r.status !== 0) {
    console.error("git ls-files failed; check cannot compare discovery against the index");
    console.error(r.stderr ?? "");
    process.exit(1);
  }
  return (
    r.stdout
      .split(NL)
      .filter(Boolean)
      // The hook suites are shell, are governed by integrity.sh, and are out of
      // scope for a JavaScript test runner.
      .filter((f) => !f.startsWith(".claude/"))
      // `*.test.*` also matches `view.test.ts.snap` and any fixture named that
      // way. Those are not test files, and reporting one as a test the walk
      // missed would turn CI red with a message that is simply untrue.
      .filter((f) => TEST_FILE.test(f))
      .sort()
  );
}

/**
 * Runs one test file with MANUFACT_API_KEY removed, keeping what it printed.
 *
 * The output is the point. An earlier version returned only the exit status,
 * which cost two things: a file could be parked in LIVE because it failed for
 * any reason at all, and a genuine regression in a pure file produced a
 * one-line misattribution with the real assertion visible nowhere.
 */
function runKeyless(file) {
  const env = { ...process.env };
  delete env.MANUFACT_API_KEY;
  const r = spawnSync(process.execPath, ["--test", file], { cwd: ROOT, env, encoding: "utf8" });
  return { ok: r.status === 0, output: `${r.stdout ?? ""}${r.stderr ?? ""}` };
}

/**
 * Whether a failure names the missing key as its cause.
 *
 * This reads what the output says. It is not proof of causation — a keyed run is
 * impossible in CI, which has no key — and it is not tamper-proof: an evaluation
 * defeated the looser form of this by writing the env var's name into a failing
 * assertion message, and nothing stops someone writing this class name into one
 * instead. Matching the thrown error class rather than the bare variable name
 * narrows that to a deliberate act; it does not close it. What it catches
 * reliably is the accident and the shortcut, which is what LIVE gets misused for.
 */
const KEY_CAUSE = /MissingApiKeyError/;

const NL = String.fromCharCode(10);

const all = discover(TESTS);
const live = all.filter((f) => LIVE.has(f));
const pure = all.filter((f) => !LIVE.has(f));

const mode = process.argv[2];

if (mode === "check") {
  let failed = false;
  const fail = (msg, output) => {
    console.error(msg);
    if (output) for (const line of output.trimEnd().split(NL)) console.error(`    | ${line}`);
    failed = true;
  };

  console.log(`discovered ${all.length}  pure ${pure.length}  live ${live.length}`);
  for (const f of pure) console.log(`  pure  ${f}`);
  for (const f of live) console.log(`  live  ${f}`);
  console.log("");

  // 1. Two independent sources for the same question. A test file that exists
  //    but is not committed will not exist in CI's checkout; a file git tracks
  //    but the walk misses would never run. Comparing discovery against itself
  //    proves neither — the first version of this check did exactly that and
  //    could not fail.
  const tracked = trackedTests();
  for (const f of all) {
    if (!tracked.includes(f)) fail(`  not committed, so CI will never see it: ${f}`);
  }
  for (const f of tracked) {
    if (!all.includes(f)) fail(`  git tracks it but discovery missed it: ${f}`);
  }

  // 2. LIVE may not name a file that does not exist.
  for (const f of LIVE) {
    if (!all.includes(f)) fail(`  LIVE names a file that does not exist: ${f}`);
  }

  // 3. The npm scripts must still route through this runner, and exactly — a
  //    substring test is satisfied by `node --test tests/a.test.ts #
  //    scripts/run-tests.mjs`, which runs a hand-written list while looking
  //    compliant. That restored list is the state this change exists to end.
  const pkg = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8"));
  for (const name of ["test:pure", "test:live"]) {
    const want = `node scripts/run-tests.mjs ${name.slice(5)}`;
    if ((pkg.scripts?.[name] ?? "").trim() !== want) {
      fail(`  package.json "${name}" must be exactly: ${want}`);
    }
  }

  // 4. The whole `fast-checks` job is pinned to its exact text. Pinning the npm
  //    scripts is not enough: delete the step from ci.yml and every other
  //    assertion here passes while nothing checks discovery — the hole this
  //    change closes.
  //
  //    Every version of this assertion before this one was defeated by executing
  //    it, and the last two are why it is shaped this way. Three scanned ci.yml
  //    for `run:`
  //    values and fell to YAML the scanner read differently from Actions: a
  //    second job under `if: ${{ false }}`, a step-level `if:`,
  //    `continue-on-error: true`, then those two keys quoted, `${{ true }}` and
  //    `True` as values, a four-space job body, and `run: ... || true`, whose
  //    failure the shell swallows. The fourth pinned the job header and the two
  //    steps as exact text and was defeated four more ways, because a pinned
  //    line sequence constrains only itself: YAML mapping keys are order-free,
  //    so `if:` on the line *after* `run:` leaves the pinned pair verbatim while
  //    the step never runs, and the same holds for `continue-on-error:` and for
  //    a job-level `if:` written after `steps:` — or after the job's last line,
  //    outside the compared range entirely. A block scalar elsewhere in the file
  //    could also carry the pinned text while the real job differed.
  //
  //    So the pin is the entire job, and it must be the first entry under
  //    `jobs:`. An added key anywhere in the job changes the block; a decoy in a
  //    scalar is not preceded by `jobs:`. Editing this job means updating
  //    REQUIRED_JOB_BLOCK in the same commit, where a reviewer sees both halves.
  //
  //    Pinning the job still leaves the rest of the file unpinned, and an
  //    evaluation showed that is not a detail: `defaults: run: shell: cat {0}`
  //    above `jobs:` applies to every step in this job that sets no shell of its
  //    own — none do — so each one prints its script and exits 0. npm ci,
  //    typecheck, build and both test steps all report success without running,
  //    and the required check goes green. `env: npm_config_script_shell:
  //    /bin/true` does the same through npm's config. Both leave all 21 pinned
  //    lines byte-identical. So the whole file is digested as well, over the
  //    same comment-free lines: anything outside the job that can reach into it
  //    changes the digest.
  //
  //    What this still cannot see is a ruleset that stops requiring
  //    `fast-checks`, which lives in GitHub's settings rather than in this
  //    repository. Changing `on:` leaves it silent too, but that is not a way to
  //    merge green — the required check then never reports at all and the pull
  //    request stays blocked. Every blind spot named here is of that kind; the
  //    `defaults:` hole was the first fail-open one found, and it was found by
  //    an evaluation rather than by this list being complete.
  const REQUIRED_JOB = "fast-checks";
  const CI_PATH = ".github/workflows/ci.yml";
  const REQUIRED_JOB_BLOCK = [
    "  fast-checks:",
    "    name: fast-checks",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - name: Checkout",
    "        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
    "      - name: Set up Node",
    "        uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0",
    "        with:",
    "          node-version: '22'",
    "          cache: npm",
    "      - name: Install dependencies",
    "        run: npm ci",
    "      - name: Typecheck",
    "        run: npx mcp-use typecheck",
    "      - name: Build",
    "        run: npm run build",
    "      - name: Test discovery is complete",
    "        run: npm run test:check",
    "      - name: Test (pure)",
    "        run: npm run test:pure",
  ];

  // Comments and blank lines carry no meaning to Actions and are dropped before
  // comparing, so ci.yml stays commentable without touching this constant.
  const significant = readFileSync(join(ROOT, CI_PATH), "utf8")
    .split(NL)
    .map((l) => l.replace(/\r$/, ""))
    .map((l, i) => ({ line: l, at: i + 1 }))
    .filter(({ line }) => line.trim() && !line.trim().startsWith("#"));

  const matches = significant.filter((_, i) =>
    REQUIRED_JOB_BLOCK.every((want, k) => significant[i + k]?.line === want),
  );
  // The match has to be a job, not text inside a scalar. Requiring `jobs:` to be
  // the line before it settles that without interpreting anything.
  const asJob = matches.filter(({ at }) => {
    const i = significant.findIndex((entry) => entry.at === at);
    return i > 0 && significant[i - 1].line === "jobs:";
  });

  // The pin covers the job's lines; it must also cover the job's END, or a key
  // appended after the last step is outside the compared range entirely. An
  // evaluation defeated the previous version with `if: ${{ false }}` written
  // there: it skips the whole job while every pinned line stays verbatim.
  const closed = asJob.filter(({ at }) => {
    const k = significant.findIndex((entry) => entry.at === at);
    const after = significant[k + REQUIRED_JOB_BLOCK.length];
    // Nothing after it, or the next line starts a sibling job or a top-level key.
    return !after || /^ {2}[^ ]/.test(after.line) || /^[^ ]/.test(after.line);
  });

  if (closed.length !== 1) {
    fail(
      `  ${CI_PATH} must contain the \`${REQUIRED_JOB}\` job exactly as pinned,` +
        `${NL}    once, as the first entry under \`jobs:\`, with nothing of its` +
        `${NL}    own following the pinned lines — found ${closed.length}.` +
        `${NL}    A key added anywhere in that job can stop it running, including` +
        `${NL}    after the lines below, so the whole job is compared, not a part.` +
        `${NL}    If the change is deliberate, update REQUIRED_JOB_BLOCK in` +
        `${NL}    scripts/run-tests.mjs in the same commit. Expected:` +
        `${NL}${REQUIRED_JOB_BLOCK.map((l) => `      ${l}`).join(NL)}`,
    );
  }

  // The job pin covers the job. This covers everything else in the file that can
  // reach into it — computed over the same comment-free, blank-free lines, so
  // ci.yml stays commentable and the digest tracks only what Actions reads.
  const CI_DIGEST = "0e12d28a23a532f2b4397bf726867de01ef91d0b093009118f846b3e6f35819b";
  const digest = createHash("sha256")
    .update(significant.map(({ line }) => line).join(NL))
    .digest("hex");
  if (digest !== CI_DIGEST) {
    fail(
      `  ${CI_PATH} has changed outside the pinned job.` +
        `${NL}    A workflow-level \`defaults:\` or \`env:\` key reaches into every step` +
        `${NL}    of that job — \`defaults: run: shell: cat {0}\` makes each one print` +
        `${NL}    its script and exit 0, with the job's own lines untouched.` +
        `${NL}    If the change is deliberate, set CI_DIGEST in scripts/run-tests.mjs` +
        `${NL}    to ${digest} in the same commit.`,
    );
  }


  // 5. The split has to be earned. A file kept out of CI must fail without a key
  //    AND blame the key for it; a file CI runs must pass without one. Checking
  //    only that a LIVE file fails is not enough: an evaluation committed a test
  //    asserting 1 + 1 === 3, named it in LIVE, and this check went green while
  //    no CI job executed it. LIVE is for credentials, not for quarantine.
  for (const f of live) {
    const { ok, output } = runKeyless(f);
    if (ok) {
      fail(`  ${f} is in LIVE but passes with no key — it belongs in CI`);
    } else if (!KEY_CAUSE.test(output)) {
      fail(`  ${f} is in LIVE but its failure never mentions the key — LIVE is not a quarantine`, output);
    }
  }
  for (const f of pure) {
    const { ok, output } = runKeyless(f);
    if (ok) continue;
    // Naming the right cause matters: this step runs before `Test (pure)` and a
    // failed step aborts the job, so this message and this captured output are
    // the only account of the failure anyone sees.
    if (KEY_CAUSE.test(output)) {
      fail(`  ${f} runs in CI but needs MANUFACT_API_KEY — add it to LIVE`, output);
    } else {
      fail(`  ${f} fails on its own merits — a test regression, not a suite-membership problem`, output);
    }
  }

  if (failed) {
    console.error("\ndiscovery check failed");
    process.exit(1);
  }
  console.log("discovery matches the index, the npm scripts and the CI job still");
  console.log("route through it, every CI-run file passes with no key, and every");
  console.log("file held out of CI fails with no key naming MissingApiKeyError.");
  process.exit(0);
}

const files = mode === "live" ? live : mode === "pure" ? pure : null;
if (files === null) {
  console.error("usage: node scripts/run-tests.mjs <pure|live|check>");
  process.exit(2);
}
if (files.length === 0) {
  console.error(`no ${mode} test files discovered — refusing to report success`);
  process.exit(1);
}

execFileSync(process.execPath, ["--test", ...files], { stdio: "inherit", cwd: ROOT });
