#!/usr/bin/env bash
# Enumera (solo lectura) los archivos del repo que nombran la ruta de actualizacion de perfiles.
# Uso: bash enumerate_updater_files.sh [repo_root]   -> imprime "path<TAB>blob_sha1" ordenado.
set -euo pipefail
cd "${1:-.}"
P='lf_profile_update_|lf_record_profile_operation_step_v1|ACTUALIZACION_PERFIL_LF|profile_update_'
git ls-files .github/workflows supabase/functions skills/profile_creator/contracts skills/profile_creator/validators docs/reconcile docs/programming-agent docs/operations \
 | xargs -d '\n' grep -l -E "$P" | sort | while read -r f; do printf '%s\t%s\n' "$f" "$(git rev-parse HEAD:"$f")"; done
