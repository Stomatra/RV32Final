#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

mkdir -p build

if [[ ! -f build/vivado/digital_twin.xpr ]]; then
  vivado -mode batch \
    -source scripts/recreate_vivado_project.tcl \
    -log build/recreate_vivado_project.log \
    -journal build/recreate_vivado_project.jou
fi

vivado -mode batch \
  -source automated_build.tcl \
  -log build/vivado_build.log \
  -journal build/vivado_build.jou
