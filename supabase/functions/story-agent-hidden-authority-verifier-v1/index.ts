import "jsr:@supabase/functions-js/edge-runtime.d.ts";

function response(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

Deno.serve((req: Request) => {
  if (req.method !== "POST") {
    return response({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
  }
  return response(
    {
      outcome: "BLOCKED",
      code: "AUD24_F03_EXTERNAL_AUTHORITY_UNRESOLVED",
      finding: "AUD24-F03",
    },
    409,
  );
});
