#!/usr/bin/env bash
set -euo pipefail

# Recreate the agent/skill links for OpenCode, Claude Code and GitHub Copilot.
# The canonical content lives in .agent/.
# Windows: enable Developer Mode or run Git with core.symlinks=true.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p .claude .opencode .github/agents

ln -sfn ../.agent/skills .claude/skills
ln -sfn ../.agent/agents .claude/agents
ln -sfn ../.agent/skills .opencode/skills
ln -sfn ../.agent/agents .opencode/agents
ln -sfn ../.agent/skills .github/skills

for name in godot-verifier gdscript-reviewer ci-fixer asset-auditor docs-maintainer; do
  ln -sfn "../../.agent/agents/$name.md" ".github/agents/$name.agent.md"
done

echo "Agent configuration links recreated."
