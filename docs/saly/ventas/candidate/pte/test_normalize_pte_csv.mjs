import {normalizePteCsv} from './normalize_pte_csv.mjs';
const policy={source_id:'PE-PTE',scope_key:'LIMA_ICA',ubigeo_prefixes:['15','11']};
const header='DSC_INSTITUCION,DSC_RUC,COD_UBICACION\n';
const csv=header+'"A, ""B""",20100000001,150101\r\nC,20100000001,110101\nD,,110102\nE,20100000002,040101\n';
const got=normalizePteCsv(csv,policy);
if(got.total!==4||got.rows.length!==3||got.rows[0].nombre!=='A, "B"'||got.rows[2].ruc!==null||got.rows[2].fila_origen!==3||got.source_id!=='PE-PTE'||got.scope_key!=='LIMA_ICA')throw Error('PTE_TEST_POSITIVE');
const alternate=normalizePteCsv(header+'X,20100000003,040101\nY,20100000004,150101\n',{...policy,ubigeo_prefixes:['04']});
if(alternate.rows.length!==1||alternate.rows[0].nombre!=='X')throw Error('PTE_SHARED_ENGINE_SCOPE');
let passed=2;
for(const [input,pol,expected] of [
 [csv,null,'PTE_POLICY_INVALID'],
 [csv,{...policy,ubigeo_prefixes:['15','15']},'PTE_POLICY_INVALID'],
 [csv,{...policy,ubigeo_prefixes:['1']},'PTE_POLICY_INVALID'],
 ['',policy,'PTE_EMPTY_RESPONSE'],
 ['<html>403</html>',policy,'PTE_CSV_HEADER'],
 [header+'"bad',policy,'PTE_CSV_UNCLOSED_QUOTE'],
 [header+'A,B',policy,'PTE_CSV_ROW_SHAPE'],
 [header+'"A"x,B,150101',policy,'PTE_CSV_TRAILING_QUOTE'],
 [header+'A"B,C,150101',policy,'PTE_CSV_QUOTE']
]){
 let actual='';try{normalizePteCsv(input,pol)}catch(e){actual=e.message}
 if(actual!==expected)throw Error('PTE_NEGATIVE_GUARD_FAIL expected='+expected+' received='+actual);
 passed++;
}
console.log('PASS_PTE_SCOPE_CONFIG '+passed+' tests (including alternative tenant scope and negative policy)');
