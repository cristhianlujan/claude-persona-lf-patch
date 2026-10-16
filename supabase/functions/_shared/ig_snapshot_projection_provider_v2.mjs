/* IG M10.7 candidate: one trusted source load per execution, selective reads.
 * No HTTP handler, shared DB table, global cache, runtime wiring or deployment.
 * A trusted backend must supply a genuinely frozen, canonical source dataset.
 */
import {selectSnapshotReadV1, sha256Hex, SnapshotInvalidError} from './ig_snapshot_reader_v1.mjs';

const fields=Object.freeze([
  'run_id','pantalla_id','version_id','contract_snapshot_sha256','source_snapshot_sha256'
]);
const roles=Object.freeze({INPUT_CURATOR:'CURATING',INPUT_VALIDATOR:'VALIDATING'});
const allowed=(o,k)=>Object.prototype.hasOwnProperty.call(o,k);
function identity(run) {
  if(!run || fields.some(k=>run[k]===null || run[k]===undefined || run[k]===''))
    throw new SnapshotInvalidError('IG_PROVIDER_RUN_IDENTITY_INCOMPLETE');
  return Object.fromEntries(fields.map(k=>[k,run[k]]));
}
function sameId(a,b){return fields.every(k=>a[k]===b[k]);}
function toPayload(loaded, pinned) {
  if(!loaded || typeof loaded!=='object' || !loaded.identity ||
     !loaded.data || typeof loaded.data!=='object')
    throw new SnapshotInvalidError('IG_PROVIDER_TRUSTED_DATA_MISSING');
  if(!sameId(loaded.identity,pinned))
    throw new SnapshotInvalidError('IG_PROVIDER_TRUSTED_IDENTITY_MISMATCH');
  return loaded.data;
}
/**
 * Each instance is a single run-scope. Use once for one execution.
 * The provider binds the first trusted dataset and exposes only reader
 * projections. A new execution must create a new provider instance.
 */
export function createRunScopedProjectionProviderV2({loadTrustedRunData}={}) {
  if(typeof loadTrustedRunData!=='function')
    throw new SnapshotInvalidError('IG_PROVIDER_TRUSTED_LOADER_MISSING');
  let pinned=null;
  let datasetPromise=null;
  let digestPromise=null;
  let loadCount=0;
  const boundByStage=new Map();
  const getDataset=run=>{
    const id=identity(run);
    if(pinned && !sameId(pinned,id))
      throw new SnapshotInvalidError('IG_PROVIDER_RUN_SCOPE_MISMATCH');
    if(!datasetPromise){
      pinned=Object.freeze(id);
      loadCount++;
      datasetPromise=Promise.resolve().then(()=>loadTrustedRunData(Object.freeze({...pinned})))
        .then(loaded=>toPayload(loaded,pinned));
      digestPromise=datasetPromise.then(sha256Hex);
    }
    return datasetPromise;
  };
  async function open({consumer,run}) {
    // Reader skips the loader entirely if the consumer stage is not eligible.
    if(!allowed(roles,consumer))
      throw new SnapshotInvalidError('IG_SNAPSHOT_CONSUMER_NOT_ALLOWED');
    if(!run || run.status!==roles[consumer])
      return selectSnapshotReadV1({consumer,run,loadTrustedSnapshot:null});
    const id=identity(run);
    if(pinned && !sameId(pinned,id))
      throw new SnapshotInvalidError('IG_PROVIDER_RUN_SCOPE_MISMATCH');
    const key=consumer+':'+run.status+':'+String(run.curator_identity??'')+':'+String(run.validator_identity??'');
    if(boundByStage.has(key))return boundByStage.get(key);
    const pending=selectSnapshotReadV1({consumer,run,
      loadTrustedSnapshot:async()=>{
        const data=await getDataset(run);
        return {
          ...pinned,
          schema_version:'IG_EXECUTION_SOURCE_CONTEXT_V2',
          purpose:'READ_ONLY_DATA_PACKET',
          reuse_scope:'RUN_IMMUTABLE_COMPLETE',
          consumer_stage:roles[consumer],
          validator_identity:run.validator_identity??null,
          data,
          data_sha256:await digestPromise
        };
      }
    });
    boundByStage.set(key,pending);
    try{return await pending;}catch(e){boundByStage.delete(key);throw e;}
  }
  async function select({consumer,run,selection}) {
    const bound=await open({consumer,run});
    if(bound.mode!=='SHARED_SNAPSHOT')return bound;
    return Object.freeze({
      mode:'SHARED_SNAPSHOT',reason:'SELECTED_FROM_RUN_MEMORY',
      data:bound.read(selection)
    });
  }
  async function projectForTransfer({consumer,run,selection}) {
    const result=await select({consumer,run,selection});
    if(result.mode!=='SHARED_SNAPSHOT')return result;
    // Reconstitute only requested graph paths as nested JSON so the recipient
    // can apply its normal graph-path selector. No copy of the full graph.
    let projectedData=result.data;
    if(Array.isArray(selection.graph)){
      const graph=Object.create(null);
      for(const path of selection.graph){
        const parts=path.split('.');
        let dst=graph;
        for(const part of parts.slice(0,-1)){
          if(!Object.prototype.hasOwnProperty.call(dst,part))
            dst[part]=Object.create(null);
          dst=dst[part];
        }
        dst[parts[parts.length-1]]=result.data.graph[path];
      }
      projectedData=Object.freeze({...result.data,graph});
    }
    // Only the selected data crosses process boundaries; receiver validates
    // this digest and the full run/stage envelope before using the projection.
    return Object.freeze({
      schema_version:'IG_EXECUTION_SOURCE_CONTEXT_V2',
      purpose:'READ_ONLY_DATA_PACKET',
      reuse_scope:'RUN_IMMUTABLE_COMPLETE',
      consumer_stage:roles[consumer],
      ...identity(run),
      validator_identity:run.validator_identity??null,
      data:projectedData,
      data_sha256:await sha256Hex(projectedData)
    });
  }
  return Object.freeze({
    open,select,projectForTransfer,
    metrics:()=>Object.freeze({trusted_source_loads:loadCount,bound_stages:boundByStage.size})
  });
}
