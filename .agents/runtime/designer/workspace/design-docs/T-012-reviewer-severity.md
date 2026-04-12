# T-012: Enhance Reviewer Structured Severity Levels and Security Checklist

## Context

The current `agent-reviewer SKILL.md` defines basic review process and report template, but lacks:
1. **Severity classification**: All issues treated equally, cannot distinguish blocking bugs from suggested improvements
2. **Security review checklist**: No systematic security checks, easy to miss OWASP Top 10 issues
3. **Code quality thresholds**: No explicit quantitative standards (function length, file size, nesting depth, etc.)
4. **Confidence filtering**: All findings reported including low-confidence style issues, reducing signal-to-noise ratio

## Decision

Enhance `agent-reviewer SKILL.md` with four core capabilities: structured severity levels + security checklist + quality thresholds + confidence filtering.

## Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| **A: SKILL.md enhancement + report template upgrade (selected)** | Consistent with existing framework, incremental adoption | Relies on Agent compliance | ✅ Selected |
| **B: Integrate SonarQube/CodeClimate** | Automated detection | Requires external service, increases deployment complexity | ❌ External dependency |
| **C: Custom lint rules** | Hard constraints | Separate config per language, high maintenance cost | ❌ Maintenance burden |
| **D: Only upgrade report template** | Simple | No structured decision framework | ❌ Not systematic enough |

## Design

### Architecture

```
Enhanced Reviewer Review Process:

┌─────────────────────────────────────────────┐
│  Review input: files_modified + diff         │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│  Step 1: Security Review Checklist 🔒        │
│  Check each OWASP Top 10 + common issues     │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│  Step 2: Code Quality Threshold Check 📏     │
│  Function length / file size / nesting / TODO│
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│  Step 3: Logic/Architecture Review 🧠        │
│  Correctness, edge cases, error handling,    │
│  performance                                 │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│  Step 4: Confidence Filtering 🎯             │
│  Keep only findings with confidence >= 80%   │
│  Discard style/formatting noise              │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│  Step 5: Severity Classification + Decision  │
│  CRITICAL → BLOCK                           │
│  HIGH → REQUEST_CHANGES                     │
│  MEDIUM/LOW → APPROVE with notes            │
└─────────────────────────────────────────────┘
```

### Data Model

**Severity level definitions**:

| Level | Description | Approval Action | Examples |
|-------|------------|----------------|----------|
| 🔴 CRITICAL | Security vulnerability, data loss, system crash | **BLOCK** — must not pass | SQL injection, hardcoded secrets, unhandled null causing crash |
| 🟠 HIGH | Logic error, performance issue, missing critical error handling | **REQUEST_CHANGES** — must fix | Race condition, N+1 query, unvalidated user input |
| 🟡 MEDIUM | Maintainability issue, non-critical bug, missing tests | **APPROVE with notes** — should fix | Function too long, missing boundary test, magic numbers |
| 🔵 LOW | Minor improvement, documentation | **APPROVE with notes** — optional fix | Poor variable naming, missing comments, import order |

**Approval decision rules**:
- Any CRITICAL present → **BLOCK** (overall review result is BLOCK)
- HIGH present (no CRITICAL) → **REQUEST_CHANGES**
- Only MEDIUM + LOW → **APPROVE with notes**
- No findings → **APPROVE**

**Security review checklist**:

```markdown
| # | Check Item | Risk | Check Method |
|---|-----------|------|-------------|
| 1 | Hardcoded secrets/passwords | CRITICAL | grep sensitive patterns: password=, secret=, api_key=, token= |
| 2 | SQL injection | CRITICAL | Check for SQL concatenation, verify parameterized queries |
| 3 | XSS (Cross-Site Scripting) | HIGH | Check if user input is escaped before rendering |
| 4 | CSRF (Cross-Site Request Forgery) | HIGH | Check forms/APIs for CSRF token |
| 5 | Path traversal | HIGH | Check file paths for ../ and absolute path filtering |
| 6 | Auth bypass | CRITICAL | Check API endpoints for auth middleware |
| 7 | Insecure dependencies | MEDIUM | Check npm audit / pip audit results |
| 8 | Sensitive data in logs | MEDIUM | Check log/console for passwords, tokens |
```

**Code quality thresholds**:

```markdown
| Metric | Threshold | Level |
|--------|----------|-------|
| Function/method lines | > 50 lines | MEDIUM — suggest splitting |
| File lines | > 800 lines | MEDIUM — suggest splitting |
| Nesting depth | > 4 levels | MEDIUM — suggest early return/extract function |
| Cyclomatic complexity | > 15 | HIGH — must split |
| console.log/print debug statements | Present | LOW — clean up |
| TODO/FIXME without ticket | Present | LOW — link to issue or remove |
| Duplicate code blocks | > 10 lines duplicated | MEDIUM — extract shared function |
```

### API / Interface

**Enhanced review report template**:

```markdown
# Code Review Report — T-NNN

## Review Summary
- **Reviewer**: Reviewer Agent
- **Review Date**: YYYY-MM-DD
- **Files**: N
- **Total Findings**: N (CRITICAL: X, HIGH: Y, MEDIUM: Z, LOW: W)
- **Approval Decision**: APPROVE / REQUEST_CHANGES / BLOCK

## 🔒 Security Review
| # | Check Item | Result | Notes |
|---|-----------|--------|-------|
| 1 | Hardcoded secrets | ✅ Pass | — |
| 2 | SQL injection | ✅ Pass | Uses parameterized queries |
| ... | ... | ... | ... |

## 📋 Findings

### 🔴 CRITICAL
(None)

### 🟠 HIGH
1. **[HIGH] Unvalidated user input** (confidence: 95%)
   - File: `src/api/handler.ts:42`
   - Description: User input passed directly to SQL query
   - Suggestion: Use parameterized queries

### 🟡 MEDIUM
...

### 🔵 LOW
...

## 📏 Code Quality
| Metric | Status | Details |
|--------|--------|---------|
| Function length | ⚠️ | `processData()` 72 lines, suggest splitting |
| File size | ✅ | Largest file 320 lines |
| Nesting depth | ✅ | Max 3 levels |

## Conclusion
[Approval decision and summary]
```

### Implementation Steps

1. **Update `skills/agent-reviewer/SKILL.md` — Severity levels**:
   - Define CRITICAL/HIGH/MEDIUM/LOW four-tier classification
   - Define approval action for each level (BLOCK/REQUEST_CHANGES/APPROVE with notes)
   - Provide typical examples for each level

2. **Add security review checklist section**:
   - Define 8 security checks (hardcoded secrets, SQL injection, XSS, CSRF, path traversal, auth bypass, insecure deps, log leakage)
   - Each includes risk level and check method
   - Marked as "must execute on every review"

3. **Add code quality thresholds section**:
   - Define 7 quantitative metrics (function lines, file lines, nesting depth, cyclomatic complexity, debug statements, TODOs, duplicate code)
   - Each includes threshold and corresponding severity level

4. **Add confidence filtering rules**:
   - Rule: Only report findings with confidence >= 80%
   - Exclude: Pure style/formatting issues (whitespace, bracket placement, import order)
   - Each finding must include confidence percentage

5. **Upgrade review report template**:
   - Add review summary (finding statistics + approval decision)
   - Add security review results table
   - Group findings by severity level
   - Each finding includes: level, confidence, file location, description, suggestion
   - Add code quality table

6. **Update review process**:
   - Integrate security checklist into existing 8-step review process (as mandatory step)
   - Add confidence filtering step before final report
   - Add severity aggregation logic to approval decision

## Test Spec

### Unit Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 1 | SKILL.md contains four severity levels | CRITICAL/HIGH/MEDIUM/LOW all defined with examples |
| 2 | SKILL.md contains security checklist | All 8 security checks present |
| 3 | SKILL.md contains code quality thresholds | All 7 thresholds present |
| 4 | SKILL.md contains confidence filtering rules | >= 80% threshold clearly defined |
| 5 | Review report template has severity grouping | Template has CRITICAL/HIGH/MEDIUM/LOW sections |

### Integration Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 6 | Review finds CRITICAL issue | Approval decision is BLOCK |
| 7 | Review finds only MEDIUM issues | Approval decision is APPROVE with notes |
| 8 | Finding with 60% confidence on style issue | Filtered out, not in report |
| 9 | Function > 50 lines | MEDIUM quality warning in report |

### Acceptance Criteria

- [ ] G1: Severity levels (CRITICAL/HIGH/MEDIUM/LOW) fully defined with clear approval rules
- [ ] G2: Security checklist covers 8 checks (secrets, injection, XSS, CSRF, path traversal, auth bypass, deps, logs)
- [ ] G3: Code quality thresholds include 7 metrics
- [ ] G4: Confidence >= 80% filtering rule clearly defined

## Consequences

**Positive**:
- Review report signal-to-noise ratio significantly improved; CRITICAL issues prioritized
- Security review systematized, common vulnerabilities no longer missed
- Code quality has quantitative standards, improvement trends trackable
- Confidence filtering reduces meaningless review back-and-forth

**Negative/Risks**:
- Strict security checklist may increase review time
- Thresholds may need adjustment for project type (e.g., UI files are typically longer)
- Confidence judgment relies on Agent's subjective assessment

**Future Impact**:
- T-013 Tester can prioritize testing areas corresponding to CRITICAL/HIGH findings
- Structured review report data can be used for project-level quality analysis
