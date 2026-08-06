#!/usr/bin/env node
import fs from 'node:fs';

function hasLoneSurrogate(s) {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= s.length) return true;
      const d = s.charCodeAt(i + 1);
      if (d < 0xDC00 || d > 0xDFFF) return true;
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) return true;
  }
  return false;
}
function parseJsonStrict(text) {
  let i = 0;
  const ws = () => { while (i < text.length && /[\t\n\r ]/.test(text[i])) i++; };
  const fail = (code) => { throw new Error(`${code}:OFFSET_${i}`); };
  function parseString() {
    const start = i; if (text[i] !== '"') fail('JSON_EXPECTED_STRING'); i++;
    while (i < text.length) {
      const ch = text[i++];
      if (ch === '"') { const value = JSON.parse(text.slice(start, i)); if (hasLoneSurrogate(value)) fail('RFC8785_LONE_SURROGATE'); return value; }
      if (ch === '\\') { if (i >= text.length) fail('JSON_BAD_ESCAPE'); const e = text[i++]; if (e === 'u') { if (!/^[0-9a-fA-F]{4}$/.test(text.slice(i,i+4))) fail('JSON_BAD_UNICODE_ESCAPE'); i += 4; } else if (!'"\\/bfnrt'.includes(e)) fail('JSON_BAD_ESCAPE'); }
      else if (ch.charCodeAt(0) < 0x20) fail('JSON_CONTROL_CHARACTER');
    }
    fail('JSON_UNTERMINATED_STRING');
  }
  function parseNumber() { const m=text.slice(i).match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/); if(!m) fail('JSON_BAD_NUMBER'); const token=m[0]; i+=token.length; const value=Number(token); if(!Number.isFinite(value)) fail('RFC8785_NON_FINITE_NUMBER'); if(/^-?(?:0|[1-9]\d*)$/.test(token)&&!Number.isSafeInteger(value)) fail('IJSON_UNSAFE_INTEGER'); return value; }
  function parseArray(){ i++; ws(); const a=[]; if(text[i]===']'){i++;return a;} while(true){a.push(parseValue());ws();if(text[i]===']'){i++;return a;}if(text[i]!==',')fail('JSON_EXPECTED_COMMA');i++;ws();}}
  function parseObject(){ i++; ws(); const o={}; const seen=new Set(); if(text[i]==='}'){i++;return o;} while(true){const key=parseString();if(seen.has(key))fail(`DUPLICATE_JSON_KEY:${key}`);seen.add(key);ws();if(text[i]!==':')fail('JSON_EXPECTED_COLON');i++;ws();o[key]=parseValue();ws();if(text[i]==='}'){i++;return o;}if(text[i]!==',')fail('JSON_EXPECTED_COMMA');i++;ws();}}
  function parseValue(){ws();const ch=text[i];if(ch==='"')return parseString();if(ch==='{')return parseObject();if(ch==='[')return parseArray();if(text.startsWith('true',i)){i+=4;return true;}if(text.startsWith('false',i)){i+=5;return false;}if(text.startsWith('null',i)){i+=4;return null;}if(ch==='-'||/\d/.test(ch||''))return parseNumber();fail('JSON_UNEXPECTED_TOKEN');}
  const value=parseValue();ws();if(i!==text.length)fail('JSON_TRAILING_CONTENT');return value;
}
function canonicalize(value){let out='';function s(v){if(v===null||typeof v!=='object'){const x=JSON.stringify(v);if(x===undefined)throw new Error('RFC8785_UNSERIALIZABLE');out+=x;}else if(Array.isArray(v)){out+='[';v.forEach((x,n)=>{if(n)out+=',';s(x)});out+=']';}else{out+='{';Object.keys(v).sort().forEach((k,n)=>{if(n)out+=',';out+=JSON.stringify(k)+':';s(v[k]);});out+='}';}}s(value);return out;}
const input=process.argv[2]?fs.readFileSync(process.argv[2],'utf8'):fs.readFileSync(0,'utf8');
process.stdout.write(canonicalize(parseJsonStrict(input)));
