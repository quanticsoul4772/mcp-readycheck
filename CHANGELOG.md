# Changelog

<!--
  Header note: at the time of writing, this repository has no git tags and
  no published releases. No version history has been invented here. Once
  releases are tagged, move entries from [Unreleased] into dated version
  headings.
-->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once releases are tagged.

## [Unreleased]

### Added

Current capabilities, as described in the repository (not a record of a release):

- `start_audit` tool: starts a Manufact publishing-check audit for a server
  id, returns an `auditId`, and renders the `audit-report` view
  (`README.md`, `index.ts`).
- `get_audit` tool: reads an audit's current state; app-only, called by the
  view (`README.md`, `index.ts`).
- Development and deploy scripts: `dev`, `build`, `start`, `deploy`,
  `typecheck` and `test` (`package.json`).

### Changed

No entries yet.

### Deprecated

No entries yet.

### Removed

No entries yet.

### Fixed

No entries yet.

### Security

No entries yet.
