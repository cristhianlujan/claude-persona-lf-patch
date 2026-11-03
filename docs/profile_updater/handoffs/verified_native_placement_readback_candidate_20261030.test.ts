/** Offline regression fixtures for existing Edge GitHub exact-ref reader candidate.
 * Run with Node >=22: node --experimental-strip-types --test <this-file>.
 * Does not prove deployed Edge trust enforcement.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { verifyProfilePlacementSource } from "./verified_native_placement_readback_candidate_20261030.ts";
const BASE="a".repeat(40),CAND="b".repeat(40);
const base="# Example\n## Research\nlookup\n## Decision\nold\n## Quality\ncheck\n";
const inserted="# Example\n## Research\nlookup\n## N1 N2\nnew\n## Decision\nold\n## Quality\ncheck\n";
const modified="# Example\n## Research\nlookup\n## Decision\nnew\n## Quality\ncheck\n";
const removed="# Example\n## Research\nlookup\n## Quality\ncheck\n";
function ghFor(srcBase:string,srcCandidate:string){
  return async (path:string)=>{
    const isBase=path.endsWith("?ref="+BASE);
    if(!path.includes("/contents/profiles/example/SKILL.md?ref="))throw Error("UNEXPECTED_GH_PATH");
    return {type:"file",encoding:"base64",sha:"1".repeat(40),
      content:Buffer.from(isBase?srcBase:srcCandidate,"utf8").toString("base64")};
  };
}
const insert={method_id:"M",action:"INSERT" as const,relative_path:"SKILL.md",
  target_anchor:"## N1 N2",predecessor_anchor:"## Research",successor_anchor:"## Decision"};
const setup=(gh:any,mode:"baseline"|"compare",intents:any[]=[insert])=>
  verifyProfilePlacementSource({gh,profileSlug:"example",baseSha:BASE,candidateSha:CAND,
    mode,selectedMethodIds:["M"],intents});
test("source-first baseline accepts a valid prospective insertion",async()=>{
  const r=await setup(ghFor(base,inserted),"baseline");
  assert.equal(r.ok,true);
  if(r.ok)assert.equal(r.evidence.state,"SOURCE_ONLY_NOT_ENFORCEMENT");
});
test("exact-ref candidate readback observes an inserted heading",async()=>{
  const r=await setup(ghFor(base,inserted),"compare");assert.equal(r.ok,true);
  if(r.ok)assert.equal((r.evidence.records as any[]).length,1);
});
test("unreported inserted step is rejected even if no adoption claimed",async()=>{
  const r=await setup(ghFor(base,inserted),"compare",[]);
  assert.deepEqual(r,{ok:false,code:"PLACEMENT_UNDECLARED_STEP_HEADING_CHANGE"});
});
test("a nonadjacent insertion skips the real successor and is rejected",async()=>{
  const r=await setup(ghFor(base,inserted),"baseline",[
    {...insert,successor_anchor:"## Quality"}]);
  assert.deepEqual(r,{ok:false,code:"PLACEMENT_BASE_ANCHOR_OR_ORDER_INVALID"});
});
test("a method absent from trusted selection cannot adopt",async()=>{
  const r=await setup(ghFor(base,inserted),"baseline",[
    {...insert,method_id:"OTHER"}]);
  assert.deepEqual(r,{ok:false,code:"PLACEMENT_INTENT_INVALID"});
});
test("a path outside adopting profile is rejected",async()=>{
  const r=await setup(ghFor(base,inserted),"baseline",[
    {...insert,relative_path:"../../another/SKILL.md"}]);
  assert.deepEqual(r,{ok:false,code:"PLACEMENT_INTENT_INVALID"});
});
test("same-head comparison is invalid",async()=>{
  const r=await verifyProfilePlacementSource({gh:ghFor(base,base),profileSlug:"example",
    baseSha:BASE,candidateSha:BASE,mode:"compare",selectedMethodIds:[],intents:[]});
  assert.deepEqual(r,{ok:false,code:"PLACEMENT_EXACT_REVISION_INVALID"});
});
test("an existing step can be modified without a fixed position",async()=>{
  const r=await setup(ghFor(base,modified),"compare",
    [{...insert,action:"MODIFY",target_anchor:"## Decision",
      predecessor_anchor:"## Research",successor_anchor:"## Quality"}]);
  assert.equal(r.ok,true);
});
test("an existing step can be removed without an invented universal stage",async()=>{
  const r=await setup(ghFor(base,removed),"compare",
    [{...insert,action:"REMOVE",target_anchor:"## Decision",
      predecessor_anchor:"## Research",successor_anchor:"## Quality"}]);
  assert.equal(r.ok,true);
});
test("a missing actual source anchor must block",async()=>{
  const r=await setup(ghFor(base,inserted),"baseline",
    [{...insert,predecessor_anchor:"## INVENTED"}]);
  assert.deepEqual(r,{ok:false,code:"PLACEMENT_ANCHOR_UNVERIFIED_OR_AMBIGUOUS"});
});
