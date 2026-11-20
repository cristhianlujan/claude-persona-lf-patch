// Only replace the HTTP hop to PostgREST. Each real RPC runs in the test container.
import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {handleProfileContinuation} from "../../../../supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts";

const request = JSON.parse(readFileSync(0, "utf8"));
const signatures = {
  lf_profile_execution_plan_for_run_v1: ["p_execution_id", "p_decision"],
  lf_profile_skill_selection_run_bind_v1: ["p_execution_id", "p_decision", "p_actor_execution_id"],
  lf_profile_native_bridge_prepare_v1: ["p_execution_id", "p_source_revision", "p_source_digest", "p_actor_execution_id"],
};
function query(sql, values) {
  const variables = values.flatMap((v, i) => ["-v", "v" + i + "=" + (typeof v === "string" ? v : JSON.stringify(v))]);
  const out = execFileSync("docker", ["exec", "-i", process.env.PRE40_CONTAINER, "psql",
    "-XqAt", "-U", "postgres", "-v", "ON_ERROR_STOP=1", ...variables], {input: sql + ";\n", encoding:"utf8"});
  return Response.json(JSON.parse(out));
}
async function pgFetch(url, init) {
  const endpoint = new URL(url);
  if (init.method === "GET" && endpoint.pathname === "/rest/v1/lf_operation_execution") {
    const id = endpoint.searchParams.get("execution_id").slice(3);
    return query("select jsonb_agg(to_jsonb(e)) from lf_operation_execution e where execution_id=:'v0'", [id]);
  }
  const rpc = endpoint.pathname.split("/").at(-1);
  if (!Object.hasOwn(signatures, rpc)) throw Error("Unexpected test RPC " + rpc);
  const args = JSON.parse(init.body);
  const values = signatures[rpc].map(k => args[k]);
  const params = values.map((v, i) => v === null ? "NULL" : ":'v" + i + "'");
  return query("select public." + rpc + "(" + params.join(",") + ")", values);
}
const response = await handleProfileContinuation(request.action, request,
  {supabaseUrl:"https://fixture.invalid", serviceRoleKey:"fixture", repository:"fixture/lf"}, pgFetch, "a".repeat(40));
console.log(JSON.stringify([response.status, await response.json()]));
