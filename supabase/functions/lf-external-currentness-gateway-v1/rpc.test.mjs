import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");

assert.match(source, /inventoryRpc\("lf_external_currentness_read_model_v1", \{\}\)/);
assert.match(source, /inventoryRpc\("lf_external_currentness_apply_observation_v1", \{/);
assert.doesNotMatch(source, /"content-profile":\s*"inventory"/);
assert.doesNotMatch(source, /"accept-profile":\s*"inventory"/);
assert.doesNotMatch(source, /inventoryRpc\("fn_external_currentness_read_model_v1"/);
assert.doesNotMatch(source, /inventoryRpc\("fn_apply_external_currentness_observation_v1"/);

console.log("PASS_GATEWAY_PUBLIC_RPC_WRAPPER_TESTS");
