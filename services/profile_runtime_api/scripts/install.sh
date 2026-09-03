#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: sudo %s [--source-dir REPO] [--source-sha GIT_SHA] [--start]\n' "$0"
}

start_service=false
source_sha_override=""
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd -- "$script_dir/../../../" && pwd)"
while (($#)); do
  case "$1" in
    --source-dir)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      source_dir="$(cd -- "$2" && pwd)"
      shift 2
      ;;
    --start)
      start_service=true
      shift
      ;;
    --source-sha)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      source_sha_override="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ${EUID} -ne 0 ]]; then
  printf 'INSTALL_REQUIRES_ROOT\n' >&2
  exit 1
fi
for required in \
  "$source_dir/services/profile_runtime_api/requirements.in" \
  "$source_dir/services/profile_runtime_api/deploy/lf-profile-runtime-api.service" \
  "$source_dir/sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_runner.py"; do
  [[ -f "$required" ]] || { printf 'REQUIRED_SOURCE_MISSING=%s\n' "$required" >&2; exit 1; }
done

# Mandatory read-only inventory. This script never installs or downloads llama/model bytes.
"$source_dir/services/profile_runtime_api/scripts/inspect_vps.sh"

if [[ -n "$source_sha_override" ]] && [[ ! "$source_sha_override" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'SOURCE_SHA_INVALID\n' >&2
  exit 1
fi
if git -C "$source_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
  detected_source_sha="$(git -C "$source_dir" rev-parse HEAD)"
  if [[ -n "$source_sha_override" && "$source_sha_override" != "$detected_source_sha" ]]; then
    printf 'SOURCE_SHA_MISMATCH expected=%s actual=%s\n' \
      "$source_sha_override" "$detected_source_sha" >&2
    exit 1
  fi
  source_sha="$detected_source_sha"
elif [[ -n "$source_sha_override" ]]; then
  source_sha="$source_sha_override"
else
  printf 'SOURCE_SHA_REQUIRED_WITHOUT_GIT\n' >&2
  exit 1
fi
release_id="$source_sha"
install_root=/opt/lf-profile-runtime-api
release_root="$install_root/releases"
release_dir="$release_root/$release_id"
service_user=lfprofile
env_file=/etc/lf-profile-runtime-api.env

getent group "$service_user" >/dev/null || groupadd --system "$service_user"
id -u "$service_user" >/dev/null 2>&1 || useradd \
  --system --gid "$service_user" --home-dir /var/lib/lf-profile-runtime-api \
  --shell /usr/sbin/nologin "$service_user"
install -d -m 0755 "$install_root" "$release_root"

if [[ ! -d "$release_dir" ]]; then
  temp_release="$release_root/.${release_id}.tmp.$$"
  [[ ! -e "$temp_release" ]] || { printf 'TEMP_RELEASE_ALREADY_EXISTS=%s\n' "$temp_release" >&2; exit 1; }
  install -d -m 0755 "$temp_release"
  tar --exclude=.git --exclude='services/profile_runtime_api/.venv' \
    -C "$source_dir" -cf - . | tar -C "$temp_release" -xf -
  chmod -R u=rwX,go=rX "$temp_release"
  mv "$temp_release" "$release_dir"
fi

python3 -m venv "$install_root/venv"
"$install_root/venv/bin/python" -m pip install --disable-pip-version-check \
  -r "$release_dir/services/profile_runtime_api/requirements.in"

if [[ ! -f "$env_file" ]]; then
  api_token="$(openssl rand -hex 32)"
  install -m 0600 /dev/null "$env_file"
  {
    printf 'PROFILE_RUNTIME_API_TOKEN=%s\n' "$api_token"
    printf 'PROFILE_RUNTIME_API_HOST=127.0.0.1\n'
    printf 'PROFILE_RUNTIME_API_PORT=8090\n'
    printf 'PROFILE_RUNTIME_LLAMA_BASE_URL=http://127.0.0.1:8080\n'
    printf 'PROFILE_RUNTIME_LLAMA_MODEL=Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf\n'
    printf 'PROFILE_RUNTIME_REPO_ROOT=/opt/lf-profile-runtime-api/current\n'
    printf 'PROFILE_RUNTIME_STATE_DIR=/var/lib/lf-profile-runtime-api\n'
    printf 'PROFILE_RUNTIME_SOURCE_SHA=%s\n' "$source_sha"
    printf 'PROFILE_RUNTIME_VERSION=hetzner-profile-runtime-api/0.1.0-candidate\n'
    printf 'PROFILE_RUNTIME_RESOLVER_VERSION=structural-context-resolver/v3\n'
    printf 'PROFILE_RUNTIME_MAX_WORKERS=1\n'
    printf 'PROFILE_RUNTIME_MAX_BATCH_SIZE=8\n'
    printf 'PROFILE_RUNTIME_MAX_REQUEST_BYTES=20971520\n'
    printf 'PROFILE_RUNTIME_MAX_PROMPT_CHARS=120000\n'
    printf 'PROFILE_RUNTIME_MAX_OUTPUT_TOKENS=2048\n'
    printf 'PROFILE_RUNTIME_LLAMA_TIMEOUT_SECONDS=900\n'
    printf 'PROFILE_RUNTIME_LLAMA_HEALTH_TIMEOUT_SECONDS=3\n'
    printf 'PROFILE_RUNTIME_CACHE_MAX_ENTRIES=64\n'
    printf 'PROFILE_RUNTIME_ENABLE_TARGETED_REREAD=true\n'
    printf 'PROFILE_RUNTIME_ALLOW_MODEL_IMAGE=false\n'
    printf 'PROFILE_RUNTIME_ALLOW_NO_AUTH=false\n'
  } >"$env_file"
else
  sed -i "s|^PROFILE_RUNTIME_SOURCE_SHA=.*$|PROFILE_RUNTIME_SOURCE_SHA=$source_sha|" "$env_file"
fi

next_link="$install_root/.current.$$"
ln -s "$release_dir" "$next_link"
mv -Tf "$next_link" "$install_root/current"
install -m 0644 "$release_dir/services/profile_runtime_api/deploy/lf-profile-runtime-api.service" \
  /etc/systemd/system/lf-profile-runtime-api.service
systemctl daemon-reload

if [[ "$start_service" == true ]]; then
  systemctl enable lf-profile-runtime-api.service
  systemctl restart lf-profile-runtime-api.service
  systemctl --no-pager --full status lf-profile-runtime-api.service
else
  printf 'SERVICE_NOT_STARTED: run systemctl enable --now lf-profile-runtime-api.service after config review\n'
fi
printf 'INSTALL_COMPLETE source_sha=%s classification=INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY\n' "$source_sha"
printf 'LLAMA_OR_MODEL_MUTATIONS=NONE\n'
