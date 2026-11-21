// Explicitly admitted technical source handlers. Not a Router or a runtime selector.
import {PTE_CSV_ADAPTER} from './pte_csv_adapter.mjs';
const sources=Object.freeze({'PE-PTE':PTE_CSV_ADAPTER});
export function resolveSourceAdapter(sourceId){
 return typeof sourceId==='string' && Object.hasOwn(sources,sourceId) ?
   sources[sourceId] : null;
}
export function listSourceAdapters(){return Object.freeze(Object.keys(sources));}
