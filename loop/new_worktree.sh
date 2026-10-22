#!/bin/bash
# Create a builder worktree with the git-ignored private assets linked in.
#   bash loop/new_worktree.sh <piece>   ->  .worktrees/<piece> on branch opus55/<piece>
set -euo pipefail
piece="${1:?usage: $0 <piece>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
wt="$root/.worktrees/$piece"
[ -e "$wt" ] && { echo "$wt already exists" >&2; exit 1; }
git -C "$root" worktree add -b "opus55/$piece" "$wt" Opus-5.5-enhancements
for d in game/assets/providers art/source/characters art/source/helicopter art/provider-sources; do
  if [ -e "$root/$d" ] && [ ! -e "$wt/$d" ]; then mkdir -p "$(dirname "$wt/$d")"; ln -s "$root/$d" "$wt/$d"; fi
done
godot --headless --path "$wt/game" --import >"$wt/.import.log" 2>&1 || { echo "import failed: $wt/.import.log" >&2; exit 1; }
echo "$wt"
