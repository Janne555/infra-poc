#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tofu -chdir=infra fmt -check -recursive
tofu -chdir=infra init -backend=false -input=false -lockfile=readonly
tofu -chdir=infra validate
tofu -chdir=infra test
python3 - <<'PYCODE'
from pathlib import Path
import yaml
for path in [*Path('ansible').rglob('*.yml'), *Path('infra/tests/fixtures').glob('*.yml'), Path('config.yml'), Path('.sops.yaml')]:
    yaml.safe_load(path.read_text())
print('YAML syntax valid')
PYCODE
validation_inventory=$(mktemp --suffix=.yml)
trap 'rm -f "$validation_inventory"' EXIT HUP INT TERM
python3 scripts/inventory.py --config-only > "$validation_inventory"
(cd ansible && ansible-playbook -i "$validation_inventory" site.yml --syntax-check)
(cd ansible && ansible-playbook -i "$validation_inventory" retire-bootstrap.yml --syntax-check)
ansible-lint ansible/site.yml ansible/retire-bootstrap.yml
