/* IG M10.7 F: backend-only transaction-scoped adapter for canonical SQL.
 * Never take SQL, snapshot data, or transaction guarantees from HTTP input.
 */
import {SnapshotInvalidError} from './ig_snapshot_reader_v1.mjs';
const fields=['run_id','pantalla_id','version_id','contract_snapshot_sha256','source_snapshot_sha256'];
const sql='select programacion.fn_ig_m107_trusted_run_data_v1($1::bigint) as payload';
const record=x=>x!==null && typeof x==='object' && !Array.isArray(x);
export function createTrustedRunDataLoaderV1({withReadOnlyRepeatableRead}={}) {
 if(typeof withReadOnlyRepeatableRead!=='function')
  throw new SnapshotInvalidError('IG_F_TRUSTED_TRANSACTION_REQUIRED');
 return async function loadTrustedRunData(pinned) {
  if(!record(pinned)||!Number.isSafeInteger(pinned.run_id)||pinned.run_id<=0||
     fields.some(k=>pinned[k]===null||pinned[k]===undefined))
   throw new SnapshotInvalidError('IG_F_PINNED_IDENTITY_MISSING');
  // Trusted backend transaction helper opens REPEATABLE READ READ ONLY.
  // SQL function independently rejects a driver that did not do so.
  const row=await withReadOnlyRepeatableRead(async client=>{
   if(typeof client?.query!=='function')
    throw new SnapshotInvalidError('IG_F_TRUSTED_SQL_CLIENT_MISSING');
   const result=await client.query(sql,[pinned.run_id]);
   return result?.rows?.[0];
  });
  const packet=row?.payload;
  if(!record(packet)||!record(packet.identity)||!record(packet.data))
   throw new SnapshotInvalidError('IG_F_SQL_PACKET_INVALID');
  if(fields.some(k=>packet.identity[k]!==pinned[k]))
   throw new SnapshotInvalidError('IG_F_SQL_IDENTITY_MISMATCH');
  const d=packet.data;
  if(!Array.isArray(d.rules)||!Array.isArray(d.contracts)||!Array.isArray(d.families)||
     !record(d.graph)||d.rules.length===0||d.contracts.length===0||d.families.length===0)
   throw new SnapshotInvalidError('IG_F_SQL_DATA_INCOMPLETE');
  if(Object.keys(d).some(k=>!['rules','contracts','families','graph'].includes(k)))
   throw new SnapshotInvalidError('IG_F_SQL_DATA_UNEXPECTED_SECTION');
  return {identity:packet.identity,data:d};
 };
}
