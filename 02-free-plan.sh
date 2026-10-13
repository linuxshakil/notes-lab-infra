#!/usr/bin/env bash
set -euo pipefail
TYPE="${1:?usage: ./02-free-plan.sh <instance-type> [node-count]}"
N="${2:-1}"
cd "$(dirname "$0")/notes-lab-infra"

python3 - "$TYPE" "$N" <<'PY'
import re, sys
t, n = sys.argv[1], sys.argv[2]

p = "platform/variables.tf"; s = open(p).read()
def setdef(s, var, val, quote=False):
    pat = re.compile(r'(variable "%s" \{.*?default\s*=\s*)([^\n]+)' % var, re.S)
    return pat.sub(lambda m: m.group(1) + ('"%s"' % val if quote else val), s, count=1)
s = setdef(s, "node_instance_type", t, True)
s = setdef(s, "node_min_size", n)
s = setdef(s, "node_desired_size", n)
if int(n) > 4: s = setdef(s, "node_max_size", n)
s = re.sub(r'(db_instance_class\s*=\s*)"db\.t4g\.small"', r'\1"db.t4g.micro"', s)
s = re.sub(r'(db_backup_retention\s*=\s*)\d+', r'\g<1>1', s)
open(p, "w").write(s); print("patched", p)

p = "addons/main.tf"; s = open(p).read()
if "replicaCount" not in s:
    s = s.replace("    clusterName = local.p.cluster_name\n",
                  "    clusterName  = local.p.cluster_name\n    replicaCount = 1\n", 1)
if "dex" not in s:
    s = s.replace('    server = {\n      service = { type = "ClusterIP" } # reach the UI with kubectl port-forward\n    }\n',
                  '    server = {\n      service = { type = "ClusterIP" } # reach the UI with kubectl port-forward\n    }\n    dex           = { enabled = false }\n    notifications = { enabled = false }\n', 1)
open(p, "w").write(s); print("patched", p)
PY
command -v terraform >/dev/null && terraform fmt -recursive . >/dev/null || true
echo "Done: node type=$TYPE, nodes=$N, DB=db.t4g.micro, backups=1 day."
