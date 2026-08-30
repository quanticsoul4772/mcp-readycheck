import { MCPServer } from "mcp-use";
import { z } from "zod";

import {
  auditOutputSchema,
  mapAuditResponse,
  startAuditOutputSchema,
} from "#lib/audit-schema";
import { createAudit, fetchAudit, resolveActiveDeploymentId } from "#lib/manufact";

const server = new MCPServer({
  name: "mcp-readycheck",
  title: "mcp-readycheck", // Human readable name of the server
  version: "1.0.0",
  description: "an mcp-use app",
  instructions: "use show-app to open the app view", // Model-facing guidance — surfaced to the LLM by compatible clients.
  websiteUrl: "https://mcp-use.com",
  // Icons for your MCP Server, from public/ (or absolute URLs).
  icons: [
    {
      src: "icon.svg",
      mimeType: "image/svg+xml",
      sizes: ["512x512"],
    },
  ],

  // The MCP server is by default served at /mcp, to customise
  // basePath: "/mcp",

  // mcp-use has 1 line adapter for OAuth, import from mcp-use/oauth/*
  // oauth: oauthClerkProvider(), // zero-config via MCP_USE_OAUTH_CLERK_FRONTEND_API_URL, import from mcp-use/oauth/*

  // When OAuth is on, the HTML landing page (/mcp) is protected by default, set to true to keep the landing page public while /mcp stays bearer-protected.
  // publicLandingPage: true,
});

// TOOLS

// tool inputs are zod schemas. Important: set decriptions for the model to understand the input.
const showAppInputSchema = z.object({
  appName: z
    .string()
    .optional()
    .describe(
      "Optional title shown in the MCP App card instead of the default"
    ),
});

// tool outputs are zod schemas. Important: set descriptions for the model to understand the output.
const showAppOutputSchema = z.object({
  message: z.string().describe("Message to display in the MCP App"),
});

export const showApp = server.tool(
  {
    name: "show-app", // Unique tool id on the wire.
    title: "Show MCP App", // Short label in inspector and client UIs (falls back to name).
    description: "Display the MCP App starter view", // LLM-facing summary of what the tool does.
    inputSchema: showAppInputSchema, // Validated before the handler runs; .describe() text becomes LLM hints.
    outputSchema: showAppOutputSchema, // Required when binding a view — the view reads structuredContent typed by this.
    view: {
      name: "my-view", // directory under views/
      description: "MCP App starter card with interactive demo hooks",
      prefersBorder: false, // ask the host to skip a card border around the view
      csp: {
        resourceDomains: [
          "https://fonts.googleapis.com",
          "https://fonts.gstatic.com",
        ],
      },
    },
    // Behavioral hints for clients (readOnly / destructive / open-world).
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      openWorldHint: false,
    },
  },
  async ({ appName }, ctx) => {
    // Brief delay so the pending skeleton is visible during dev/inspector demos.
    await new Promise((resolve) => setTimeout(resolve, 1500));

    console.log(`The app name was: ${appName}`);
    const data = { message: `The MCP App starter for ${appName} is ready!` };

    return {
      content: [{ type: "text", text: data.message }],
      structuredContent: data,
    };
  }
);

// say-hello — plain tool (no view); used by the Say Hello button in my-view
const sayHelloInputSchema = z.object({
  name: z.string().describe("Name to greet"),
});

const sayHelloOutputSchema = z.object({
  greeting: z.string().describe("Greeting to display"),
});

export const sayHello = server.tool(
  {
    name: "say-hello",
    title: "Say hello",
    description: "Returns a greeting for the Say Hello button demo",
    inputSchema: sayHelloInputSchema,
    outputSchema: sayHelloOutputSchema,
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      openWorldHint: false,
    },
  },
  async ({ name }) => {
    const data = { greeting: `Hello, ${name}!` };
    return {
      content: [{ type: "text", text: data.greeting }],
      structuredContent: data,
    };
  }
);

// READINESS TOOLS
//
// Split into start and get deliberately: no tool call waits on audit
// completion, and each call is one bounded API round-trip. A single polling
// tool would hold a request open for the whole audit and give the view nothing
// to render until it finished (STAGE-PLAN correction 5).
//
// No view binding in G1. G2 adds `view: { name: "audit-report" }` together with
// `views/audit-report/` — binding a view whose directory is not in the primed
// registry throws at mount, which neither typecheck nor build would catch.

const startAuditInputSchema = z.object({
  serverId: z
    .string()
    .min(1)
    .describe("Manufact server id to audit, e.g. a9f68f45-7160-4b30-8855-06399bd6aebb"),
});

const getAuditInputSchema = z.object({
  serverId: z.string().min(1).describe("Manufact server id the audit belongs to"),
  auditId: z.string().min(1).describe("Audit id returned by start_audit"),
});

/** Turns a thrown error into an MCP error result. Never leaks the API key. */
function toolError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return {
    isError: true as const,
    content: [{ type: "text" as const, text: message }],
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

export const startAudit = server.tool(
  {
    name: "start_audit",
    title: "Start readiness audit",
    description:
      "Start Manufact's publishing checks against a server's active deployment. " +
      "Returns an auditId immediately; read the result with get_audit.",
    inputSchema: startAuditInputSchema,
    outputSchema: startAuditOutputSchema,
    // readOnlyHint is false, against the goal text's `true`: this POSTs and
    // creates a persistent audit record on an external service, which is
    // exactly what the annotation denies. A host that auto-approves read-only
    // tools would let the model create unbounded audits unprompted.
    // destructiveHint stays false — creating a record is additive, not
    // destructive — and openWorldHint stays true.
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: true,
    },
  },
  async (input) => startAuditHandler(input),
);

export const getAudit = server.tool(
  {
    name: "get_audit",
    title: "Read readiness audit",
    description:
      "Read one readiness audit's current state and its checks, grouped by whatever " +
      "categories the API returns.",
    inputSchema: getAuditInputSchema,
    outputSchema: auditOutputSchema,
    // `visibility: "app"` is deliberately omitted in G1. The SDK defines "app"
    // as "app-private helper tools callable from views via useCallTool while
    // the host hides them from the model" — and G1 ships no view. Declaring it
    // now would leave get_audit callable by nothing: hidden from the model,
    // with no view to call it from, which contradicts the OUTCOME's
    // requirement that both tools be callable. G2 adds it back alongside
    // views/audit-report/.
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      openWorldHint: true,
    },
  },
  async (input) => getAuditHandler(input),
);

export default server;
