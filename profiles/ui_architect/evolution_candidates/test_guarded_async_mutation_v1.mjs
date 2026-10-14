import assert from "assert";
import { createGuardedMutation } from "./guarded_async_mutation_v1.mjs";
const never = () => new Promise(() => {});
const tests = [
  ["applied reply",async () => {
    const g=createGuardedMutation({send:async()=>({outcome:"APPLIED"}),lookup:async()=>({outcome:"UNKNOWN"}),timeoutMs:20});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"K"})).phase,"applied");
  }],
  ["not applied reply",async () => {
    const g=createGuardedMutation({send:async()=>({outcome:"NOT_APPLIED"}),lookup:never,timeoutMs:20});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"K"})).phase,"not_applied");
  }],
  ["send hangs but lookup confirms not applied",async () => {
    const g=createGuardedMutation({send:never,lookup:async()=>({outcome:"NOT_APPLIED"}),timeoutMs:12});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"K"})).phase,"not_applied");
    assert.strictEqual(g.snapshot().phase,"not_applied");
  }],
  ["both send and lookup hang end unknown (not pending)",async () => {
    const g=createGuardedMutation({send:never,lookup:never,timeoutMs:12});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"K"})).phase,"unknown");
    assert.strictEqual(g.snapshot().phase,"unknown");
  }],
  ["lookup throws remains unknown",async () => {
    const g=createGuardedMutation({send:async()=>{throw Error("network")},lookup:async()=>{throw Error("backend")},timeoutMs:12});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"K"})).phase,"unknown");
  }],
  ["unknown prohibits blind retry",async () => {
    let sends=0;
    const g=createGuardedMutation({send:async()=>{sends++;throw Error("network")},lookup:never,timeoutMs:8});
    await g.submit({operationId:"A",idempotencyKey:"K"});
    const r=await g.submit({operationId:"A",idempotencyKey:"K"});
    assert.strictEqual(r.action,"RECONCILIATION_REQUIRED");
    assert.strictEqual(sends,1);
  }],
  ["same idempotency key allowed only after NOT_APPLIED",async () => {
    let sends=0;const g=createGuardedMutation({send:async()=>{sends++;return {outcome:"NOT_APPLIED"}},lookup:never,timeoutMs:8});
    await g.submit({operationId:"A",idempotencyKey:"K"});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"OTHER"})).action,"IDEMPOTENCY_IDENTITY_MISMATCH");
    await g.submit({operationId:"A",idempotencyKey:"K"});
    assert.strictEqual(sends,2);
  }],
  ["concurrent calls never double send",async () => {
    let sends=0,release;
    const deferred = new Promise(resolve=>{release=resolve});
    const g=createGuardedMutation({send:async()=>{sends++;return await deferred},lookup:never,timeoutMs:70});
    const first=g.submit({operationId:"A",idempotencyKey:"K"});
    const second=await g.submit({operationId:"A",idempotencyKey:"K"});
    assert.strictEqual(second.action,"DUPLICATE_SUPPRESSED");
    release({outcome:"APPLIED"});
    assert.strictEqual((await first).phase,"applied");
    assert.strictEqual(sends,1);
  }],
  ["late success cannot flip unresolved into applied",async () => {
    let late;
    const g=createGuardedMutation({send:()=>new Promise(r=>{late=r}),lookup:never,timeoutMs:8});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"K"})).phase,"unknown");
    late({outcome:"APPLIED"});await new Promise(r=>setTimeout(r,3));
    assert.strictEqual(g.snapshot().phase,"unknown");
  }],
  ["server reconciliation APPLIED after transport error",async () => {
    const g=createGuardedMutation({send:async()=>{throw Error("network")},lookup:async()=>({outcome:"APPLIED"}),timeoutMs:10});
    assert.strictEqual((await g.submit({operationId:"A",idempotencyKey:"K"})).phase,"applied");
  }],
  ["refresh unknown catches backend recovery exceptions",async () => {
    let calls=0;
    const g=createGuardedMutation({send:async()=>{throw Error("transport")},lookup:async()=>{calls++;if(calls===1)throw Error("temporary");return {outcome:"NOT_APPLIED"}},timeoutMs:12});
    await g.submit({operationId:"A",idempotencyKey:"K"});
    assert.strictEqual((await g.refresh()).phase,"not_applied");
  }],
  ["invalid identity cannot initiate send",async () => {
    let calls=0;const g=createGuardedMutation({send:async()=>{calls++},lookup:never,timeoutMs:20});
    assert.strictEqual((await g.submit({operationId:"",idempotencyKey:"K"})).action,"INVALID_IDENTITY");
    assert.strictEqual(calls,0);
  }]
];
(async function runTests() {
let fail=0;
for (const [name,fn] of tests) {
  try {await fn();console.log("PASS",name)}
  catch(e){fail++;console.error("FAIL",name,String(e))}
}
console.log(JSON.stringify({suite:"PE10_C3_UI_ASYNC_TARGETED_V1",passed:tests.length-fail,total:tests.length}));
if(fail)process.exitCode=1;

})().catch(e=>{console.error("HARNESS_FAIL",e);process.exitCode=1});