import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v3-retired-public-smoke-test";

function responseHeaders(): HeadersInit {
  return {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...responseHeaders(),
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  return new Response(JSON.stringify({
    outcome: "BLOCKED",
    endpoint_version: ENDPOINT_VERSION,
    code: "PUBLIC_SMOKE_TEST_RETIRED",
    runtime_status: "NOT_AVAILABLE",
    usable_for_runtime: false,
    usable_for_production: false,
    replacement: "get-perfil-lf-runtime-protocol",
  }), {
    status: 410,
    headers: responseHeaders(),
  });
});
