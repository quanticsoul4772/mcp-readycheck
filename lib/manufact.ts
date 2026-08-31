// manufact.ts — the Manufact Cloud API client.
//
// Every function here fails loudly. There is no retry, no fallback and no
// catch that returns a success shape: a failed request becomes a thrown
// ManufactApiError, and the tool handler turns that into an MCP error result.
//
// The API key is read from the environment at call time and used only as a
// bearer header. It never reaches a log line, an error message or a tool
// result — ManufactApiError carries the status and the path, never the header.

/** Base origin from the OpenAPI document's `servers` entry. */
const API_BASE = "https://cloud.manufact.com";

/**
 * Reads one environment variable.
 *
 * Goes through `globalThis` rather than the `process` global or a
 * `node:process` import: the typecheck's lib set is DOM-flavoured and does not
 * declare either. This is still `process.env` — the same object a caller
 * mutates — just reached without depending on Node's ambient declarations.
 */
function readEnv(name: string): string | undefined {
  const proc = (globalThis as { process?: { env?: Record<string, string | undefined> } })
    .process;
  return proc?.env?.[name];
}

/** Shape of an audit's `checks[]` element, as the API returns it. */
export interface RawCheck {
  id: string;
  auditId: string;
  checkId: string;
  checkName: string;
  status: string;
  severity: string;
  category: string;
  scope: string;
  platforms: string[];
  message: string | null;
  /** Untyped in the spec (`anyOf: [{}, null]`) — any JSON value, or null. */
  details: unknown;
  /** Untyped in the spec (`anyOf: [{}, null]`) — any JSON value, or null. */
  hint: unknown;
  durationMs: number | null;
  createdAt: string;
}

/** Shape of the audit-detail response. `checks` is absent from the spec's required list. */
export interface RawAudit {
  id: string;
  serverId: string;
  deploymentId: string | null;
  organizationId: string;
  targetUrl: string;
  gitBranch: string | null;
  /** Audit vocabulary: `running` means in progress, `completed` is terminal. */
  status: string;
  durationMs: number | null;
  errorMessage: string | null;
  isReadyForChatgpt: boolean | null;
  isReadyForClaudeai: boolean | null;
  startedAt: string;
  completedAt: string;
  createdAt: string;
  checks?: RawCheck[];
}

/** A non-2xx response from the Manufact API. Carries no credential material. */
export class ManufactApiError extends Error {
  // Declared as fields rather than constructor parameter properties: Node's
  // strip-only TypeScript mode, which runs the tests, rejects the latter.
  readonly status: number;
  readonly path: string;

  constructor(status: number, path: string, message: string) {
    super(message);
    this.name = "ManufactApiError";
    this.status = status;
    this.path = path;
  }
}

/** Raised before any request is made when the key is absent. */
export class MissingApiKeyError extends Error {
  constructor() {
    super(
      "MANUFACT_API_KEY is not set. Set it as a sensitive environment variable " +
        "on the Manufact server; no request was sent.",
    );
    this.name = "MissingApiKeyError";
  }
}

/**
 * Rewrites a thrown error into text a caller can act on.
 *
 * The audit's fuzz check reads a tool's error output and objects when it hands
 * back an internal identifier instead of a remedy. `ManufactApiError` carries
 * the request path and the status code precisely so this repo can log and
 * reason about them — neither belongs in a message the model reads, and the
 * path can carry a query string.
 *
 * Nothing is swallowed: the caller still returns `isError: true`, and the
 * original error object is unchanged for anything that inspects it.
 */
export function humanError(error: unknown): string {
  // Already caller-facing guidance about an operator action, and the only
  // actionable thing it says is the variable name. Rewriting it loses that.
  if (error instanceof MissingApiKeyError) return error.message;

  if (error instanceof ManufactApiError) {
    if (error.status === 404) {
      return (
        "Manufact has no record matching those ids. Check the serverId, and the " +
        "auditId if you passed one, then try again."
      );
    }
    if (error.status === 401 || error.status === 403) {
      return (
        "Manufact refused the request as unauthorised. Check that this server's " +
        "MANUFACT_API_KEY is set and still valid, then try again."
      );
    }
    if (error.status === 429) {
      return "Manufact is rate-limiting this server. Try again in a moment.";
    }
    if (error.status >= 500) {
      return "Manufact's API failed to answer. Try again in a moment.";
    }
    return (
      "Manufact refused the request. Check the ids you passed and try again."
    );
  }

  // Errors this repo raises are written to be read; anything else is passed
  // through rather than replaced, because inventing a message for an error we
  // do not recognise would hide it.
  if (error instanceof Error) return error.message;
  return String(error);
}

/**
 * Returns the API key, or throws before any network call happens.
 *
 * Called first inside {@link manufactFetch}, which is what makes "fails closed
 * with no request sent" a property of the code rather than of the caller.
 */
export function requireApiKey(): string {
  const key = readEnv("MANUFACT_API_KEY");
  if (!key) throw new MissingApiKeyError();
  return key;
}

/**
 * One request. No retry — a retry would hide the failure the guard exists to
 * surface, and would break the "exactly one request" property the tests assert.
 */
export async function manufactFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const key = requireApiKey();

  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
      ...init?.headers,
    },
  });

  if (!response.ok) {
    // The error responses in the spec are all `{ error: string }`. Read it when
    // it is there; never let a parse failure mask the status code.
    let detail = "";
    try {
      const body = (await response.json()) as { error?: unknown };
      if (typeof body?.error === "string") detail = `: ${body.error}`;
    } catch {
      // A non-JSON error body is not itself an error worth reporting over the
      // status code that caused it.
    }
    throw new ManufactApiError(
      response.status,
      path,
      `Manufact API returned ${response.status} for ${path}${detail}`,
    );
  }

  return (await response.json()) as T;
}

/**
 * The raw server record.
 *
 * `mcpUrl` is the API's own statement of where this server answers, which is
 * what makes it a live oracle rather than a constant. `activeDeploymentId` is
 * returned exactly as the API sends it, **including null** — this function
 * does not throw. Use {@link resolveActiveDeploymentId} when you need a
 * deployment id and want the null case refused.
 */
export async function fetchServer(serverId: string): Promise<{
  activeDeploymentId: string | null;
  mcpUrl: string;
  status: string;
}> {
  return manufactFetch(`/api/v1/servers/${encodeURIComponent(serverId)}`);
}

/**
 * The server's currently active deployment.
 *
 * Throws when it is null: an audit with no deployment to point at is not a
 * thing worth creating, and a silent default would be a fallback.
 */
export async function resolveActiveDeploymentId(serverId: string): Promise<string> {
  const server = await fetchServer(serverId);

  if (!server.activeDeploymentId) {
    throw new Error(
      `Server ${serverId} has no active deployment, so there is nothing to audit.`,
    );
  }
  return server.activeDeploymentId;
}

/** Creates an audit. Returns immediately — it never waits for the audit to settle. */
export async function createAudit(
  serverId: string,
  deploymentId: string,
): Promise<{ id: string; status: string }> {
  return manufactFetch<{ id: string; status: string }>(
    `/api/v1/server-audits/${encodeURIComponent(serverId)}/audits`,
    { method: "POST", body: JSON.stringify({ deploymentId }) },
  );
}

/** Reads one audit. One round trip, whatever state the audit is in. */
export async function fetchAudit(serverId: string, auditId: string): Promise<RawAudit> {
  return manufactFetch<RawAudit>(
    `/api/v1/server-audits/${encodeURIComponent(serverId)}/audits/${encodeURIComponent(auditId)}`,
  );
}
