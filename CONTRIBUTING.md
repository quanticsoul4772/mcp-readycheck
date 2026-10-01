# Contributing to mcp-readycheck

Thanks for your interest in contributing. This guide covers how to set up a
development environment, run the checks CI runs on every pull request, and
submit your changes.

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Development environment setup

### Prerequisites

- **Node.js 22.22.2 or newer.** This is the `engines.node` requirement in
  `package.json` (`>=22.22.2`); CI runs on Node 22.
- **npm**, which ships with Node.js.

### Get the code

Fork the repository on GitHub, then clone your fork and install dependencies:

```sh
git clone https://github.com/<your-username>/mcp-readycheck.git
cd mcp-readycheck
npm ci
```

Use `npm ci` (not `npm install`) so you get exactly the versions pinned in
`package-lock.json`, the same as CI.

## Running the checks

CI's `fast-checks` job runs the following commands in this order. Run them from
the repository root:

```sh
npx mcp-use typecheck   # 1. typecheck
npm run build           # 2. build
npm run test:check      # 3. confirm test discovery is complete
npm run test:pure       # 4. pure test suite
```

All of them should pass locally before you open a pull request.

CI also runs these on every pull request targeting `main` (and in the merge
queue), so a green local run is the quickest way to avoid a red build.

## Submitting changes

1. Fork the repository and create a branch for your change from `main`.
2. Make your changes and run the checks above.
3. Commit your work with a clear message describing what changed and why.
4. Push the branch to your fork and open a pull request against `main`.
   Describe the change and its motivation in the PR description.

For background and project conventions, see the existing docs rather than
repeating them here:

- [README.md](README.md) — project overview and usage.
- [AGENTS.md](AGENTS.md) — working conventions for the repository.
- [CLAUDE.md](CLAUDE.md) — guidance for Claude Code when working in the repo.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — community behavioral standards.
- [LICENSE](LICENSE) — the license your contributions are released under.
