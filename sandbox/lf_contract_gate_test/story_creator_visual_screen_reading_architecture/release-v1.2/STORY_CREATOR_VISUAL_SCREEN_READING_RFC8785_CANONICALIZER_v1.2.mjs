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

function decimalTuple(token) {
  const m = token.match(/^(-)?(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/);
  if (!m) throw new Error('JSON_BAD_NUMBER_TOKEN');
  const sign = m[1] ? -1n : 1n;
  const frac = m[3] || '';
  let digits = (m[2] + frac).replace(/^0+/, '') || '0';
  let exp = Number(m[4] || 0) - frac.length;
  while (digits.length > 1 && digits.endsWith('0')) {
    digits = digits.slice(0, -1);
    exp += 1;
  }
  return { sign: digits === '0' ? 1n : sign, digits: BigInt(digits), exp };
}

function sameDecimalValue(a, b) {
  const x = decimalTuple(a), y = decimalTuple(b);
  if (x.sign !== y.sign) return false;
  if (x.digits === 0n && y.digits === 0n) return true;
  if (x.exp === y.exp) return x.digits === y.digits;
  if (x.exp > y.exp) return x.digits * (10n ** BigInt(x.exp - y.exp)) === y.digits;
  return x.digits === y.digits * (10n ** BigInt(y.exp - x.exp));
}

function parseJsonStrict(text) {
  let i = 0;
  const ws = () => { while (i < text.length && /[\t\n\r ]/.test(text[i])) i++; };
  const fail = (code) => { throw new Error(`${code}:OFFSET_${i}`); };

  function parseString() {
    const start = i;
    if (text[i] !== '"') fail('JSON_EXPECTED_STRING');
    i++;
    while (i < text.length) {
      const ch = text[i++];
      if (ch === '"') {
        const value = JSON.parse(text.slice(start, i));
        if (hasLoneSurrogate(value)) fail('RFC8785_LONE_SURROGATE');
        return value;
      }
      if (ch === '\\') {
        if (i >= text.length) fail('JSON_BAD_ESCAPE');
        const e = text[i++];
        if (e === 'u') {
          if (!/^[0-9a-fA-F]{4}$/.test(text.slice(i, i + 4))) fail('JSON_BAD_UNICODE_ESCAPE');
          i += 4;
        } else if (!'"\\/bfnrt'.includes(e)) fail('JSON_BAD_ESCAPE');
      } else if (ch.charCodeAt(0) < 0x20) {
        fail('JSON_CONTROL_CHARACTER');
      }
    }
    fail('JSON_UNTERMINATED_STRING');
  }

  function parseNumber() {
    const m = text.slice(i).match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/);
    if (!m) fail('JSON_BAD_NUMBER');
    const token = m[0];
    i += token.length;
    const value = Number(token);
    if (!Number.isFinite(value)) fail('RFC8785_NON_FINITE_NUMBER');
    if (/^-?(?:0|[1-9]\d*)$/.test(token) && !Number.isSafeInteger(value)) fail('IJSON_UNSAFE_INTEGER');
    const canonical = JSON.stringify(value);
    if (!sameDecimalValue(token, canonical)) fail('IJSON_LOSSY_NUMBER');
    return value;
  }

  function parseArray() {
    i++; ws(); const a = [];
    if (text[i] === ']') { i++; return a; }
    while (true) {
      a.push(parseValue()); ws();
      if (text[i] === ']') { i++; return a; }
      if (text[i] !== ',') fail('JSON_EXPECTED_COMMA');
      i++; ws();
    }
  }

  function parseObject() {
    i++; ws(); const o = Object.create(null); const seen = new Set();
    if (text[i] === '}') { i++; return o; }
    while (true) {
      const key = parseString();
      if (seen.has(key)) fail(`DUPLICATE_JSON_KEY:${key}`);
      seen.add(key); ws();
      if (text[i] !== ':') fail('JSON_EXPECTED_COLON');
      i++; ws();
      Object.defineProperty(o, key, {
        value: parseValue(),
        enumerable: true,
        writable: false,
        configurable: false
      });
      ws();
      if (text[i] === '}') { i++; return o; }
      if (text[i] !== ',') fail('JSON_EXPECTED_COMMA');
      i++; ws();
    }
  }

  function parseValue() {
    ws();
    const ch = text[i];
    if (ch === '"') return parseString();
    if (ch === '{') return parseObject();
    if (ch === '[') return parseArray();
    if (text.startsWith('true', i)) { i += 4; return true; }
    if (text.startsWith('false', i)) { i += 5; return false; }
    if (text.startsWith('null', i)) { i += 4; return null; }
    if (ch === '-' || /\d/.test(ch || '')) return parseNumber();
    fail('JSON_UNEXPECTED_TOKEN');
  }

  const value = parseValue();
  ws();
  if (i !== text.length) fail('JSON_TRAILING_CONTENT');
  return value;
}

function canonicalize(value) {
  let out = '';
  function serialize(v) {
    if (v === null || typeof v !== 'object') {
      const s = JSON.stringify(v);
      if (s === undefined) throw new Error('RFC8785_UNSERIALIZABLE');
      out += s;
    } else if (Array.isArray(v)) {
      out += '[';
      for (let n = 0; n < v.length; n++) {
        if (n) out += ',';
        serialize(v[n]);
      }
      out += ']';
    } else {
      out += '{';
      const keys = Object.keys(v).sort();
      keys.forEach((k, n) => {
        if (n) out += ',';
        out += JSON.stringify(k) + ':';
        serialize(v[k]);
      });
      out += '}';
    }
  }
  serialize(value);
  return out;
}

const input = process.argv[2]
  ? fs.readFileSync(process.argv[2], 'utf8')
  : fs.readFileSync(0, 'utf8');

process.stdout.write(canonicalize(parseJsonStrict(input)));
