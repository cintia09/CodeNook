# Test Specification: T-001 — README Update

## Verification Checklist

### G1: Hooks Section
- [ ] Section exists between "Goals Checklist" and "File Structure"
- [ ] Contains 3-hook table (session-start, pre-tool-use, post-tool-use)
- [ ] Contains boundary rules table (5 roles × can/cannot edit)
- [ ] Mentions `active-agent` file mechanism

### G2: events.db Section
- [ ] Section exists after Hooks
- [ ] Contains schema table (7 columns)
- [ ] Contains query examples (at least 3 sqlite3 commands)

### G3: Architecture Update
- [ ] "Hook enforcement" added to Key Features
- [ ] "SQLite audit log" added to Key Features
- [ ] Roadmap shows Phase 2 as ✅

### G4: File Structure Update
- [ ] hooks/ directory shown in global layer tree
- [ ] events.db shown in project layer tree
- [ ] active-agent shown in runtime/ tree
- [ ] Installation steps include hook copying (Steps 4-5)
