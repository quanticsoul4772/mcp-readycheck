# ADR-0002: Accept the pr720 prerelease transitive dependency

- Status: accepted
- Date: 2026-08-30
- Deciders: repository owner

## Context

`npm ls zod` on the freshly scaffolded baseline exposes this in the production
dependency tree:

```
mcp-readycheck@1.0.0
+-- mcp-use@2.3.3
| +-- @modelcontextprotocol/client@2.0.0
| +-- @modelcontextprotocol/core@2.0.0
| +-- @modelcontextprotocol/ext-apps@npm:@mcp-use/ext-apps@1.7.4-pr720.1
| `-- @modelcontextprotocol/server@2.0.0
```

Two distinct facts are stacked in that one line.

**It is a pull-request prerelease.** `1.7.4-pr720.1` is a SemVer prerelease
identifier denoting a build published from pull request 720 — code that has not
passed the vendor's own release gating, shipped inside an otherwise stable
`mcp-use@2.3.3`. npm permits unpublishing within 72 hours, and PR-bot artifacts
are commonly pruned later, so the version can disappear from the registry.

**It is an npm alias across publisher scopes.** The name
`@modelcontextprotocol/ext-apps` is satisfied by a package published under the
`@mcp-use` scope — a different publisher with different credentials. SBOM,
provenance-attestation, and license-scanning tools can mis-attribute the
artifact's publisher as a result.

The dependency is transitive. This project's `package.json` pins
`"mcp-use": "2.3.3"` exactly and declares no direct dependency on any
`@modelcontextprotocol` package. The tree was produced by the vendor's own
official scaffolder (`create-mcp-use-app@latest --template mcp-apps`) with
default settings.

This matters more here than in a typical project: mcp-readycheck exists to run
Manufact's publishing and compliance checks against itself, and prerelease
versions in a production dependency tree are exactly what such scanners flag.

## Decision

Accept the dependency as a vendor default and change nothing.

`package-lock.json` is committed, which pins the resolved tarball and its
integrity hash, making installs deterministic for as long as the artifact
remains published.

## Consequences

- The build is reproducible today but would break if `@mcp-use/ext-apps@1.7.4-pr720.1`
  is unpublished, with no vendored fallback.
- A supply-chain or provenance scanner may report the alias or the prerelease
  version as a finding that this project cannot fix without a vendor release.
- Overriding it (npm `overrides`, vendoring, or pinning a stable `ext-apps`)
  would diverge from what `mcp-use@2.3.3` was tested against, trading a
  provenance risk for a compatibility risk. Not worth it before evidence.

## Revisit when

The Stage 10 self-audit runs. If Manufact's security-and-policy or
metadata category reports this dependency, reopen this decision and evaluate an
`overrides` pin or a vendor upgrade. If the audit is silent on it, this ADR
stands until the next `mcp-use` upgrade.
