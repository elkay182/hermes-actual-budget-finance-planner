#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${HOME}/.hermes/skills/actual-budget-finance-planner"

mkdir -p "$TARGET_DIR"
cp "$SOURCE_DIR/SKILL.md" "$TARGET_DIR/SKILL.md"
for dir in references examples scripts docs; do
  if [ -d "$SOURCE_DIR/$dir" ] && [ "$SOURCE_DIR" != "$TARGET_DIR" ]; then
    rm -rf "$TARGET_DIR/$dir"
    cp -R "$SOURCE_DIR/$dir" "$TARGET_DIR/$dir"
  fi
done

echo "Installed Actual Budget Finance Planner skill to: $TARGET_DIR/SKILL.md"
echo "Restart Hermes to load the skill."
