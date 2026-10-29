#!/usr/bin/env bash
set -euo pipefail
cabin_repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
cabin_run_tag="${1:-mbs-cabin-r1}"
if [[ ! "$cabin_run_tag" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Refusing invalid cabin evidence tag" >&2
  exit 2
fi
cabin_evidence="/private/tmp/singapore-fidelity/$cabin_run_tag"
if [[ -e "$cabin_evidence" || -L "$cabin_evidence" ]]; then
  echo "Refusing existing cabin evidence directory: $cabin_evidence" >&2
  exit 2
fi
cd -- "$cabin_repo_root"
exec bash loop/singapore-fidelity/run_engine.sh "$cabin_run_tag" 180 "$cabin_evidence" -- \
  --headless res://src/systems/fidelity_tests/mbs_cabin_test.tscn -- \
  --qa-session "$cabin_evidence/session"
