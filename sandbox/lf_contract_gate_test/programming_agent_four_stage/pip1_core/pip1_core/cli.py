"""Read-only, offline inventory verifier."""
import argparse
import json
from .core import load_inventory

def main():
    p=argparse.ArgumentParser(description='Offline PIP-1 inventory verification (candidate only)')
    p.add_argument('inventory')
    p.add_argument('--expected-digest',default=None)
    p.add_argument('--expected-file-sha256',default=None)
    args=p.parse_args()
    if not args.expected_digest and not args.expected_file_sha256:
        p.error('EXTERNAL_PIN_REQUIRED: pass --expected-file-sha256 or --expected-digest')
    i=load_inventory(args.inventory,expected_digest=args.expected_digest,expected_file_sha256=args.expected_file_sha256)
    print(json.dumps({'status':'PASS_SYNTHETIC_OR_SOURCE_ONLY_NO_AUTHORITY','version':i.version,'digest':i.digest,'checkpoints':len(i.all_ids()),'operational_checkpoints':len(i.operational_ids()),'dependencies':sum(map(len,i.requires.values())),'parallel_layers':i.topo_layers()},indent=2))
if __name__=='__main__':
    main()
