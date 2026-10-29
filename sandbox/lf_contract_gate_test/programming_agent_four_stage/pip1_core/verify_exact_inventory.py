"""Read-only exact-commit inventory fetch and SHA-256 parity verification.

Requires access to the specific repository (no token printed/logged).
The requested commit is pinned, never main or PR moving HEAD.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen
from pip1_core.core import load_inventory

COMMIT='eb0e4f3f912538b1cd2f2c9635854cbf86aeb783'
PATH='docs/programming/PROGRAMMING_PIPELINE_INVENTORY_CANDIDATE_V1.json'
EXPECTED_DIGEST='cd2f7a964b9901d9e58b8d5f4271532f480966424d37fd2d9a40332a7b440ffb'
EXPECTED_GIT_BLOB='47dd1f611ac36325b57d5129a87dc57919de330f'
EXPECTED_FILE_SHA256='fc4cd3a387858d3091bee99cbec85721744792db7fed5ffdc1cc348b1a2719c9'
URL=f'https://raw.githubusercontent.com/cristhianlujan/claude-persona-lf-patch/{COMMIT}/{PATH}'

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--file',type=Path,help='Read byte-exact file already fetched by authenticated GitHub API')
    p.add_argument('--out',type=Path,default=Path('inventory_verified.json'))
    args=p.parse_args()
    if args.file:
        raw=args.file.read_bytes()
    else:
        with urlopen(Request(URL,headers={'User-Agent':'PIP1-local-verifier'}),timeout=25) as response:
            raw=response.read(2_000_001)
    if len(raw)>2_000_000:
        raise SystemExit('BLOCKED: INVENTORY_SIZE_LIMIT')
    git_blob=hashlib.sha1(f'blob {len(raw)}\0'.encode()+raw).hexdigest()
    if git_blob!=EXPECTED_GIT_BLOB:
        raise SystemExit(f'BLOCKED: git blob SHA mismatch observed={git_blob}')
    sha256=hashlib.sha256(raw).hexdigest()
    if sha256 != EXPECTED_FILE_SHA256:
        raise SystemExit(f'BLOCKED: full file SHA-256 mismatch observed={sha256}')
    # Persist only after both byte-exact hashes pass.
    args.out.write_bytes(raw)
    inv=load_inventory(args.out,expected_digest=EXPECTED_DIGEST,expected_file_sha256=EXPECTED_FILE_SHA256)
    print(json.dumps({'status':'PASS_SOURCE_BYTES','commit':COMMIT,'source_url':URL,'sha256_complete_file':sha256,'git_blob_sha1':git_blob,'inventory_core_sha256':inv.digest,'all_checkpoints':len(inv.all_ids()),'operational_checkpoints':len(inv.operational_ids()),'pg00_checkpoints':len(inv.pg00),'edges':sum(map(len,inv.requires.values()))},indent=2))

if __name__=='__main__':
    main()
