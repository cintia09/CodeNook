# T-004 Fix Design: AGENTS.md Verification Script References

## Problem
G3 acceptance failed: AGENTS.md Step 7 uses inline bash commands for install verification without referencing `scripts/verify-install.sh` and `scripts/verify-init.sh`.

## Proposed Changes

### File: `AGENTS.md`

After Step 7 (Verify installation results), add **Step 7.1: Deep Verification (Optional)**:

```markdown
### Step 7.1: Deep Verification (Optional)
If verification scripts exist in the repository, run the full verification:
\```bash
# Verify installation completeness (Skill format, YAML frontmatter, file permissions)
bash /tmp/multi-agent-framework/scripts/verify-install.sh

# After project initialization, verify .agents/ directory structure
bash /tmp/multi-agent-framework/scripts/verify-init.sh
\```
> Note: Must be run before Step 6 cleanup, or clone the repository separately.
```

### Alternative Approach (Recommended)
Adjust the order of Step 6 and Step 7 — verify before cleanup:

1. Step 6: Verify installation results (keep existing inline checks)
2. Step 7: Deep verification (optional, reference scripts)
3. Step 8: Clean up `/tmp/multi-agent-framework`
4. Step 9: Output results

This way users can run verification scripts before cleanup.

## Implementer Notes
- Only modify AGENTS.md, do not touch other files
- Keep step numbering sequential
- Script paths use `/tmp/multi-agent-framework/scripts/` (temporary directory during install flow)
