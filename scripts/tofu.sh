#!/bin/sh
set +x
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
secret_file="$repo_dir/secrets/opentofu.sops.yml"

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <OpenTofu command> [arguments...]" >&2
    exit 2
fi
if [ ! -f "$secret_file" ]; then
    echo "Create secrets/opentofu.sops.yml with SOPS; see README.md." >&2
    exit 1
fi

TF_VAR_state_passphrase=$(sops --decrypt --extract '["state_passphrase"]' "$secret_file")
case "$TF_VAR_state_passphrase" in
    REPLACE_*) echo "Replace the example state passphrase in SOPS." >&2; exit 1 ;;
esac
if [ "${#TF_VAR_state_passphrase}" -lt 32 ]; then
    echo "The state passphrase must contain at least 32 characters." >&2
    exit 1
fi
export TF_VAR_state_passphrase
case "$1" in
    plan|apply)
        TF_VAR_bootstrap_key=$("$repo_dir/scripts/bootstrap.sh" prepare)
        export TF_VAR_bootstrap_key
        ;;
esac
exec tofu -chdir="$repo_dir/infra" "$@"
