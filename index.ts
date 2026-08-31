import { MCPServer } from "mcp-use";
import type { ToolDefinition } from "mcp-use";

import {
  auditOutputSchema,
  getAuditInputSchema,
  mapAuditResponse,
  startAuditInputSchema,
  startAuditOutputSchema,
} from "#lib/audit-schema";
import {
  createAudit,
  fetchAudit,
  humanError,
  resolveActiveDeploymentId,
} from "#lib/manufact";

// Re-exported so the tools' input contracts are readable from the entry point,
// which is where a caller looks for them.
export { getAuditInputSchema, startAuditInputSchema } from "#lib/audit-schema";

const server = new MCPServer({
  name: "mcp-readycheck",
  title: "mcp-readycheck",
  version: "1.0.0",
  description:
    "Runs Manufact's publishing checks against a deployed MCP server and renders " +
    "the result by category.",
  // Model-facing guidance. It named show-app until G3 removed the scaffold;
  // pointing the model at a tool that no longer exists is the same defect the
  // audit's tool-metadata checks look for.
  instructions:
    "Call start_audit with a Manufact server id to run the readiness checks. " +
    "It returns an auditId immediately and renders the audit-report view.",
  websiteUrl: "https://mcp-use.com",
  icons: [
    {
      src: "icon.svg",
      mimeType: "image/svg+xml",
      sizes: ["512x512"],
    },
  ],
});

/**
 * The one origin every view resource declares, as `_meta.ui.domain`.
 *
 * A constant rather than `MCP_URL`: the audit requires one exact HTTPS origin
 * shared by every view in the app, and an environment-derived value would make
 * that origin differ per deployment — silently, and only visible in an audit.
 * `MCP_URL` is also absent locally, and a default for it would be a fallback.
 */
const VIEW_DOMAIN = "https://mcp-readycheck.run.mcp-use.com";

/** Turns a thrown error into an MCP error result. Never leaks the API key. */
function toolError(error: unknown) {
  return {
    isError: true as const,
    content: [{ type: "text" as const, text: humanError(error) }],
  };
}

export async function startAuditHandler({ serverId }: { serverId: string }) {
  try {
    const deploymentId = await resolveActiveDeploymentId(serverId);
    const created = await createAudit(serverId, deploymentId);
    const data = startAuditOutputSchema.parse({
      auditId: created.id,
      status: created.status,
    });
    return {
      content: [{ type: "text" as const, text: JSON.stringify(data) }],
      structuredContent: data,
    };
  } catch (error) {
    return toolError(error);
  }
}

export async function getAuditHandler({
  serverId,
  auditId,
}: {
  serverId: string;
  auditId: string;
}) {
  try {
    const data = mapAuditResponse(await fetchAudit(serverId, auditId));
    return {
      content: [{ type: "text" as const, text: JSON.stringify(data) }],
      structuredContent: data,
    };
  } catch (error) {
    return toolError(error);
  }
}

// READINESS TOOLS
//
// Split into start and get deliberately: no tool call waits on audit
// completion, and each call is one bounded API round-trip. A single polling
// tool would hold a request open for the whole audit and give the view nothing
// to render until it finished (STAGE-PLAN correction 5).
//
// No `csp` block: this view makes no network request. It calls get_audit
// through the host bridge, and the framework already appends the server origin
// to connectDomains. Naming the API origin would grant reach it never uses.

const startAuditDefinition = {
  name: "start_audit",
  title: "Start readiness audit",
  description:
    "Start Manufact's publishing checks against a server's active deployment. " +
    "Returns an auditId immediately; read the result with get_audit.",
  inputSchema: startAuditInputSchema,
  outputSchema: startAuditOutputSchema,
  view: {
    name: "audit-report",
    description: "Readiness audit grouped by category, with both platform badges",
    prefersBorder: false,
    // → resource `_meta.ui.domain`. The audit's view-domain-present check reads
    // this; the field is typed by ToolViewConfig, unlike the widgetMetadata the
    // check's own hint recommends, which does not exist in mcp-use 2.3.3.
    domain: VIEW_DOMAIN,
  },
  // A vendor key, carried verbatim to tools/list through _meta — proven by
  // driving a real initialize + tools/list against an in-process MCPServer.
  // There is no typed SDK field for it.
  _meta: {
    "openai/toolInvocation": {
      invoking: "Running readiness checks…",
      invoked: "Ran readiness checks",
    },
  },
  // readOnlyHint is false: this POSTs and creates a persistent audit record on
  // an external service, which is exactly what the annotation denies. A host
  // that auto-approves read-only tools would let the model create unbounded
  // audits unprompted. destructiveHint stays false — creating a record is
  // additive — and openWorldHint stays true, because it does reach a third
  // party and change state there.
  annotations: {
    readOnlyHint: false,
    destructiveHint: false,
    openWorldHint: true,
  },
} satisfies ToolDefinition;

const getAuditDefinition = {
  name: "get_audit",
  title: "Read readiness audit",
  description:
    "Read one readiness audit's current state and its checks, grouped by whatever " +
    "categories the API returns.",
  inputSchema: getAuditInputSchema,
  outputSchema: auditOutputSchema,
  // `"app"` marks a tool the host hides from the model and exposes to views via
  // useCallTool. It ships with the view, never before it.
  visibility: "app",
  // openWorldHint was true here and that is the annotation the audit's
  // tool-hints-present check refused: this reads one record and submits to
  // nobody, so by the check's own definition — "true for writes that change
  // publicly visible internet state or send/submit to third parties" — a
  // read-only tool cannot also be open-world.
  annotations: {
    readOnlyHint: true,
    destructiveHint: false,
    openWorldHint: false,
  },
} satisfies ToolDefinition;

export const startAudit = server.tool(startAuditDefinition, async (input) =>
  startAuditHandler(input),
);

export const getAudit = server.tool(getAuditDefinition, async (input) =>
  getAuditHandler(input),
);

/**
 * Every definition handed to `server.tool`, in registration order.
 *
 * These are the same objects the registrations receive, not a description of
 * them: `server.tool` returns a `ToolRef` carrying only the tool's name, and
 * `MCPServer` exposes no registry, so this array is the only in-process handle
 * on what was registered. Adding a tool without adding it here is the one gap
 * that leaves — closed at S5, where the checks are read from the deployed
 * server's own `tools/list`.
 */
export const TOOL_DEFINITIONS: ToolDefinition[] = [
  startAuditDefinition,
  getAuditDefinition,
];

export default server;
