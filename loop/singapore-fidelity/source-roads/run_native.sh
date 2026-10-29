#!/usr/bin/env bash
set -euo pipefail
roads_repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
roads_run_tag="${1:-source-roads-fixture-r1}"
if [[ ! "$roads_run_tag" =~ ^[A-Za-z0-9_-]+$ ]]; then exit 2; fi
roads_evidence="/private/tmp/singapore-fidelity/$roads_run_tag"
if [[ -e "$roads_evidence" || -L "$roads_evidence" ]]; then
  echo "Refusing existing road evidence: $roads_evidence" >&2
  exit 2
fi
cd -- "$roads_repo_root"
exec bash loop/singapore-fidelity/run_engine.sh "$roads_run_tag" 120 "$roads_evidence" -- \
  --headless res://src/systems/fidelity_tests/source_roads_test.tscn -- \
  --qa-session "$roads_evidence/session"
