#!/usr/bin/env python3
"""Build Ansible inventory from OpenTofu output or the shared service definitions."""
import argparse
import json
from pathlib import Path
import sys

import yaml

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config-only', action='store_true', help='Use declared private addresses without provisioning; suitable for validation.')
args = parser.parse_args()
if args.config_only:
    config = yaml.safe_load((Path(__file__).resolve().parents[1] / 'config.yml').read_text())
    nodes = {name: service['server'] for name, service in config['services'].items()}
else:
    nodes = json.load(sys.stdin)
hosts = {name: {'ansible_host': node['private_ip'], 'data_uuid': ''} for name, node in sorted(nodes.items())}
yaml.safe_dump({'all': {'vars': {'ansible_user': 'bootstrap', 'ansible_become': True}, 'children': {'infrastructure': {'hosts': hosts}}}}, sys.stdout, sort_keys=False)
