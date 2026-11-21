#!/usr/bin/env python3
"""One-off public source schema probe. No ZIP/row persistence, no credentials."""
import hashlib
import json
import re
import struct
import urllib.request
import zlib

URL = 'https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip'
# These are limits for this one-off QA experiment, not production policy.
MAX_PREFIX = 131072
MAX_HEADER = 8192
KNOWN = {
    'RUC', 'NUM_RUC', 'NUMERO_RUC', 'NRO_RUC', 'NOMBRE', 'NOMBRE_RAZON_SOCIAL',
    'NOMBRE_O_RAZON_SOCIAL', 'RAZON_SOCIAL', 'NOMBRES', 'ESTADO', 'ESTADO_CONTRIBUYENTE',
    'ESTADO_DEL_CONTRIBUYENTE', 'CONDICION', 'CONDICION_DOMICILIO', 'CONDICION_DE_DOMICILIO',
    'UBIGEO', 'COD_UBIGEO', 'CODIGO_UBIGEO', 'TIPO_VIA', 'NOMBRE_VIA', 'COD_ZONA', 'TIPO_ZONA',
    'NOMBRE_ZONA', 'NUMERO', 'INTERIOR', 'LOTE', 'DEPARTAMENTO', 'MANZANA', 'KILOMETRO',
    'DOMICILIO_FISCAL', 'DIRECCION', 'ACTIVIDAD_ECONOMICA', 'CIIU', 'TIPO_CONTRIBUYENTE',
    'FECHA_INSCRIPCION', 'FECHA_INICIO_ACTIVIDADES', 'DISTRITO', 'PROVINCIA', 'COD_CIIU',
}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('REDIRECT_DENIED')


def inspect_prefix(blob):
    if len(blob) < 30 or blob[:4] != b'PK\x03\x04':
        raise ValueError('LOCAL_HEADER_MISSING')
    _, _, flags, method, _, _, _, compressed_size, _, name_len, extra_len = struct.unpack('<IHHHHHIIIHH', blob[:30])
    offset = 30 + name_len + extra_len
    if flags & 1 or method not in (0, 8) or offset >= len(blob):
        raise ValueError('UNSUPPORTED_PREFIX')
    name = blob[30:30+name_len]
    # Never disclose unexpected archive entry names or raw data rows.
    if not re.fullmatch(rb'[A-Za-z0-9_.-]{1,100}\.(?:csv|txt)', name, re.I):
        raise ValueError('UNEXPECTED_ENTRY_NAME')
    data = blob[offset:] if flags & 8 else blob[offset:offset+compressed_size]
    raw = data[:MAX_HEADER] if method == 0 else zlib.decompressobj(-15).decompress(data, MAX_HEADER)
    if b'\n' not in raw:
        raise ValueError('HEADER_NOT_COMPLETE')
    line = raw.split(b'\n', 1)[0].rstrip(b'\r')
    if not line or len(line) >= MAX_HEADER:
        raise ValueError('HEADER_INVALID')
    try:
        decoded = line.decode('utf-8-sig')
        compatible = 'UTF8_HEADER_COMPATIBLE_NOT_FULL_ENCODING'
    except UnicodeDecodeError:
        decoded = line.decode('cp1252')
        compatible = 'CP1252_HEADER_COMPATIBLE_NOT_FULL_ENCODING'
    import unicodedata
    def normalize(s):
        s = ''.join(c for c in unicodedata.normalize('NFKD', s.upper().strip()) if not unicodedata.combining(c))
        return re.sub(r'\s+', '_', s)
    for delimiter in ('|', ';', ',', '\t'):
        if delimiter not in decoded:
            continue
        values = decoded.split(delimiter)
        trailing = values[-1] == ''
        if trailing:
            values.pop()
        tokens = [normalize(v.strip('"')) for v in values]
        if len(tokens) < 2 or not any(t in ('RUC', 'NUM_RUC', 'NUMERO_RUC', 'NRO_RUC') for t in tokens):
            continue
        # Only reveal allowlisted known schema labels. Unknown values suppressed.
        recognized = [t if t in KNOWN else None for t in tokens]
        return {'entry_extension': name.rsplit(b'.', 1)[-1].decode('ascii').lower(),
                'zip_method': method, 'zip_flags': flags, 'delimiter': repr(delimiter),
                'column_count': len(tokens), 'recognized_columns': recognized,
                'exact_recognized_labels': [v if t in KNOWN else None for v, t in zip(values, tokens)],
                'header_sha256': hashlib.sha256(line).hexdigest(),
                'trailing_delimiter': trailing, 'header_encoding': compatible,
                'all_columns_recognized': all(t is not None for t in recognized)}
    raise ValueError('NO_RECOGNIZED_HEADER')


def main():
    req = urllib.request.Request(URL, headers={'Range': f'bytes=0-{MAX_PREFIX-1}', 'Accept-Encoding': 'identity', 'User-Agent': 'AIS30-schema-probe/1.0'}, method='GET')
    opener = urllib.request.build_opener(NoRedirect())
    with opener.open(req, timeout=15) as resp:
        if resp.status not in (200, 206) or resp.geturl() != URL or resp.headers.get('Content-Encoding', 'identity').lower() != 'identity':
            raise ValueError('HTTP_RESPONSE_DENIED')
        if resp.status == 206 and not re.fullmatch(r'bytes 0-\d+/\d+', resp.headers.get('Content-Range', '')):
            raise ValueError('HTTP_RANGE_MISMATCH')
        blob = resp.read(MAX_PREFIX)
        status = resp.status
    receipt = inspect_prefix(blob)
    print('SUNAT_REAL_SCHEMA_PREFIX ' + json.dumps({'http_status': status, 'bytes_read': len(blob), **receipt}, ensure_ascii=True, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        # Never print response bodies or arbitrary exception strings.
        reason = str(e) if type(e) is ValueError and re.fullmatch('[A-Z_]+', str(e)) else type(e).__name__
        print('SUNAT_REAL_SCHEMA_PROBE_BLOCKED ' + reason)
        raise SystemExit(1)
