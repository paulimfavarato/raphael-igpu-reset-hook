#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

for script in \
  reseed \
  50-raphael-igpu-reset \
  manual-reseed.sh \
  diagnose.sh \
  install.sh \
  uninstall.sh; do
  bash -n "$project_dir/$script"
done

if rg -n -i --glob '!**/tests/smoke.sh' \
  'paulim|ea8167ce|/home/|windows11\.qcow|BEGIN.*PRIVATE|token' "$project_dir"; then
  echo "Potential private machine data found." >&2
  exit 1
fi

"$project_dir/50-raphael-igpu-reset" unrelated-vm prepare begin
"$project_dir/50-raphael-igpu-reset" windows11 stopped end

echo "PASS: smoke tests"
