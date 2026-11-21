export function normalizePteCsv(text,policy) {
 if(!policy || typeof policy!=="object" || Array.isArray(policy) ||
 typeof policy.source_id!=="string" || !policy.source_id.trim() ||
 typeof policy.scope_key!=="string" || !policy.scope_key.trim() ||
 !Array.isArray(policy.ubigeo_prefixes) || policy.ubigeo_prefixes.length===0 ||
 policy.ubigeo_prefixes.some(x=>typeof x!=="string"|| !/^[0-9]{2}$/.test(x)) ||
 new Set(policy.ubigeo_prefixes).size !== policy.ubigeo_prefixes.length)
 throw Error("PTE_POLICY_INVALID");
 if(typeof text!=="string"||!text.length)throw Error("PTE_EMPTY_RESPONSE");
 let rows=[],row=[],field="",quoted=false,closed=false;
 for(let i=0;i<text.length;i++){
  let c=text[i];
  if(quoted){if(c==='"'&&text[i+1]==='"'){field+='"';i++;}else if(c==='"'){quoted=false;closed=true;}else field+=c;continue;}
  if(c==='"'){if(field!==""||closed)throw Error("PTE_CSV_QUOTE");quoted=true;continue;}
  if(c===","||c==="\n"||(c==="\r"&&text[i+1]==="\n")){
   row.push(field);field="";closed=false;
   if(c!==","){if(c==="\r")i++;rows.push(row);row=[];}continue;}
  if(closed)throw Error("PTE_CSV_TRAILING_QUOTE");
  field+=c;
 }
 if(quoted)throw Error("PTE_CSV_UNCLOSED_QUOTE");
 if(field||row.length||closed){row.push(field);rows.push(row);}
 const h=rows.shift();if(!h||h.join(",")!=="DSC_INSTITUCION,DSC_RUC,COD_UBICACION")throw Error("PTE_CSV_HEADER");
 if(rows.some(r=>r.length!==3||!r[0].trim()))throw Error("PTE_CSV_ROW_SHAPE");
 const selected=rows.map((r,i)=>({fila_origen:i+1,nombre:r[0],ruc:r[1]===""?null:r[1],ubigeo:r[2].trim()})).filter(r=>/^[0-9]{6}$/.test(r.ubigeo)&&policy.ubigeo_prefixes.some(prefix=>r.ubigeo.startsWith(prefix)));
 return {total:rows.length,rows:selected,capture:JSON.stringify(selected),scope_key:policy.scope_key,source_id:policy.source_id};
}
