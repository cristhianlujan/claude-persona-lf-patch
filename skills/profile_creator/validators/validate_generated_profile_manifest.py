#!/usr/bin/env python3
import json, sys
from pathlib import Path

def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    candidate = root / 'fixtures/handoff_outcome/candidate_pack.json'
    blocking = []
    try:
        pack = json.loads(candidate.read_text(encoding='utf-8'))
        files = pack.get('files')
        if not isinstance(files, dict): blocking.append('CANDIDATE_FILES_MISSING')
        else:
            raw = files.get('manifest.json')
            if not isinstance(raw, str) or not raw.strip(): blocking.append('GENERATED_PROFILE_MANIFEST_MISSING')
            else:
                manifest = json.loads(raw)
                if manifest.get('profile_pack_id') != pack.get('profile_pack_id'): blocking.append('GENERATED_PROFILE_MANIFEST_ID_MISMATCH')
                if manifest.get('operation') != 'CREACION_PERFIL_LF': blocking.append('GENERATED_PROFILE_MANIFEST_OPERATION_INVALID')
                if manifest.get('document_status') != 'CANDIDATO': blocking.append('GENERATED_PROFILE_MANIFEST_DOCUMENT_STATUS_INVALID')
                if manifest.get('operational_status') != 'READ_ONLY': blocking.append('GENERATED_PROFILE_MANIFEST_OPERATIONAL_STATUS_INVALID')
                if manifest.get('runtime') != 'NO_HABILITADO': blocking.append('GENERATED_PROFILE_MANIFEST_RUNTIME_INVALID')
                if manifest.get('automatic_impact') != 'BLOQUEADO': blocking.append('GENERATED_PROFILE_MANIFEST_AUTOMATIC_IMPACT_INVALID')
    except Exception as exc:
        blocking.append('GENERATED_PROFILE_MANIFEST_VALIDATION_ERROR:' + str(exc))
    result = {'status':'PASS' if not blocking else 'FAIL','blocking_codes':blocking,'target':'PROFILE_PACK_MANIFEST_CONTRACT'}
    print(json.dumps(result, indent=2))
    return 0 if not blocking else 1
if __name__ == '__main__': raise SystemExit(main())
