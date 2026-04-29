#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${HOME}/.hermes/skills/actual-budget-finance-planner"

mkdir -p "$TARGET_DIR"
cp "$SOURCE_DIR/SKILL.md" "$TARGET_DIR/SKILL.md"

echo "Installed Actual Budget Finance Planner skill to: $TARGET_DIR/SKILL.md"
echo "Restart Hermes to load the skill."
