#!/bin/sh
set +x
set -eu
umask 077

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
key_dir="$repo_dir/.bootstrap"
key_file="$key_dir/id_ed25519"
action=${1:-}
if [ "$#" -gt 0 ]; then shift; fi

case "$action" in
    prepare)
        mkdir -p "$key_dir"
        chmod 700 "$key_dir"
        if [ ! -f "$key_file" ]; then
            if [ -e "$key_file.pub" ]; then
                echo "Bootstrap private key is missing; recover access through the UpCloud console." >&2
                exit 1
            fi
            ssh-keygen -q -t ed25519 -N '' -C hacklab-bootstrap -f "$key_file"
        fi
        # Recover the public key after an interrupted generation, and verify the pair.
        public_key=$(ssh-keygen -y -f "$key_file")
        printf '%s\n' "$public_key" > "$key_file.pub"
        printf '%s\n' "$public_key"
        ;;
    configure)
        if [ ! -f "$key_file" ]; then
            echo "Run scripts/tofu.sh plan or apply to prepare the bootstrap key first." >&2
            exit 1
        fi
        cd "$repo_dir/ansible"
        exec ansible-playbook site.yml --private-key "$key_file" -e ansible_user=bootstrap "$@"
        ;;
    finish)
        for arg in "$@"; do
            case "$arg" in
                --check|-C|--list-*|--syntax-check|--start-at-task*|--tags*|-t|--skip-tags*)
                    echo "Finish requires the complete retirement playbook to run." >&2
                    exit 2
                    ;;
            esac
        done
        cd "$repo_dir/ansible"
        receipt=$(mktemp "$key_dir/retired.XXXXXX")
        rm -f "$receipt"
        trap 'rm -f "$receipt"' EXIT HUP INT TERM
        ansible-playbook retire-bootstrap.yml "$@" -e "bootstrap_receipt=$receipt"
        if [ ! -f "$receipt" ]; then
            echo "Retirement did not complete on any hosts; retaining the bootstrap key." >&2
            exit 1
        fi
        rm -f "$receipt" "$key_file" "$key_file.pub"
        rmdir "$key_dir" 2>/dev/null || true
        ;;
    *)
        echo "Usage: $0 prepare | configure [Ansible arguments] | finish [Ansible arguments]" >&2
        exit 2
        ;;
esac
