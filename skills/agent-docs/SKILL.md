---
name: agent-docs
description: "Document Pipeline — Standardized phase document templates, input/output matrix, FSM document gate"
---

# Agent Document Pipeline

> Each SDLC phase must produce standardized documents as input for the next phase. Documents are the formal deliverables for inter-agent collaboration.

## Document Flow Matrix

| Phase | Agent | Input Documents | Output Documents |
|-------|-------|----------------|-----------------|
| Requirements | Acceptor | (User requirements) | `requirements.md` + `acceptance-criteria.md` |
| Architecture Design | Designer | requirements.md | `design.md` |
| Implementation | Implementer | requirements.md + design.md | `implementation.md` |
| Code Review | Reviewer | requirements.md + design.md + implementation.md | `review-report.md` |
| Test Verification | Tester | requirements.md + design.md + implementation.md | `test-report.md` |
| Acceptance | Acceptor | acceptance-criteria.md + all documents | Accept / Reject |

## Document Storage

All documents are stored by task ID:

```
.agents/docs/T-XXX/
  requirements.md          ← Acceptor output
  acceptance-criteria.md   ← Acceptor output
  design.md                ← Designer output
  implementation.md        ← Implementer output
  review-report.md         ← Reviewer output
  test-report.md           ← Tester output
```

## Agent Startup Process

When switching to any Agent, you **must**:

1. Confirm the current task ID (read from task-board)
2. Check whether input documents exist under `.agents/docs/T-XXX/`
3. If input documents exist → **read all input documents first**, then begin work
4. If input documents are missing → remind user to complete the preceding phase
5. After work is complete, **must** create this phase's output documents

## FSM Transition Document Gate

Before state transitions, check whether the current phase's output documents have been created:

| Transition | Required Documents |
|------------|-------------------|
| `created → designing` | `requirements.md` + `acceptance-criteria.md` |
| `designing → implementing` | `design.md` |
| `implementing → reviewing` | `implementation.md` |
| `reviewing → testing` | `review-report.md` |
| `testing → accepting` | `test-report.md` |
| `accepting → accepted` | (Acceptor confirms all goals pass) |
| `reviewing → implementing` (rejected) | `review-report.md` (with issue list) |
| `testing → fixing` (issues found) | `test-report.md` (with failed test cases) |

> **Gate mode** is controlled by the `"doc_gate_mode"` top-level field in `task-board.json`:
>
> | Mode | Behavior |
> |------|----------|
> | `"warn"` (default) | ⚠️ Output warning, do not block transition. AI Agent should auto-complete documents |
> | `"strict"` | ⛔ Block transition, `LEGAL=false`. Documents must be written before proceeding |
>
> Configuration: Add `"doc_gate_mode": "strict"` to `task-board.json`

---

## Document Templates

### 1. Requirements Document (`requirements.md`)

```markdown
# Requirements Document: T-XXX — {Task Title}

## 1. Background and Goals
{Why this feature/fix is needed, what problem it solves}

## 2. Functional Requirements
### 2.1 Core Features
- [ ] {Feature 1}
- [ ] {Feature 2}

### 2.2 Constraints
- {Technical constraints, compatibility requirements, performance requirements, etc.}

## 3. Non-Functional Requirements
- **Performance**: {Response time, throughput, etc.}
- **Security**: {Permissions, data protection, etc.}
- **Compatibility**: {Platforms, browsers, API versions, etc.}

## 4. Scope
### Included
- {Explicitly included features}

### Excluded
- {Explicitly excluded features}

## 5. Dependencies
- {External dependencies, prerequisites}

---
*Created by Acceptor on {date}*
```

### 2. Acceptance Criteria Document (`acceptance-criteria.md`)

```markdown
# Acceptance Criteria: T-XXX — {Task Title}

## Acceptance Conditions

### AC-1: {Acceptance Condition Title}
- **Given**: {Preconditions}
- **When**: {Action steps}
- **Then**: {Expected result}

### AC-2: {Acceptance Condition Title}
- **Given**: {Preconditions}
- **When**: {Action steps}
- **Then**: {Expected result}

## Verification Methods
- [ ] Functional verification: {How to verify correctness}
- [ ] Boundary testing: {Edge case testing}
- [ ] Regression confirmation: {No impact on existing features}

## Rejection Conditions
- {Explicitly unacceptable situations, e.g., crashes, data loss}

---
*Created by Acceptor on {date}*
```

### 3. Design Document (`design.md`)

```markdown
# Design Document: T-XXX — {Task Title}

## 1. Requirements Analysis
{Understanding and supplementary analysis of requirements.md}

## 2. Technical Solution

### 2.1 Architecture Design
{Overall architecture, module breakdown, data flow}

### 2.2 Interface Design
{API interfaces, function signatures, data structures}

### 2.3 Data Model
{Database tables, JSON structures, etc.}

## 3. Implementation Strategy
- **Chosen approach**: {What approach was chosen and why}
- **Alternatives considered**: {Approaches considered but rejected, with reasons}

## 4. Impact Scope
- **New files**: {List of files to add}
- **Modified files**: {List of files to modify}
- **Risk points**: {Potential risks and mitigations}

## 5. Testing Recommendations
- {Suggested test case directions}
- {Boundary cases to cover}

---
*Created by Designer on {date} | Based on requirements.md*
```

### 4. Implementation Document (`implementation.md`)

```markdown
# Implementation Document: T-XXX — {Task Title}

## 1. Implementation Overview
{What was implemented and what approach was used}

## 2. Change List

### New Files
| File | Purpose |
|------|---------|
| {path} | {description} |

### Modified Files
| File | Changes |
|------|---------|
| {path} | {description} |

## 3. Key Implementation Details
{Core logic, algorithms, design patterns, etc.}

## 4. Deviations from Design Document
{Any inconsistencies with design.md, with explanations}

## 5. Test Coverage
- **Unit tests**: {New/modified test files}
- **Self-test results**: {Local run results}

## 6. Known Limitations
- {Known limitations or items to optimize}

---
*Created by Implementer on {date} | Based on design.md + requirements.md*
```

### 5. Review Report (`review-report.md`)

```markdown
# Review Report: T-XXX — {Task Title}

## 1. Review Scope
- **Files reviewed**: {N}
- **Review based on**: requirements.md + design.md + implementation.md

## 2. Review Conclusion: {✅ Passed / ❌ Rejected / ⚠️ Conditionally Passed}

## 3. Issue List

### 🔴 Must Fix (Blockers)
| # | File | Line | Issue | Severity |
|---|------|------|-------|----------|
| 1 | {path} | {line} | {description} | HIGH |

### 🟡 Suggested Fixes (Suggestions)
| # | File | Line | Issue | Severity |
|---|------|------|-------|----------|
| 1 | {path} | {line} | {description} | MEDIUM |

### 🟢 Optional Improvements (Nice-to-have)
- {suggestion}

## 4. Quality Assessment
- **Code quality**: ⭐⭐⭐⭐☆
- **Test coverage**: ⭐⭐⭐⭐☆
- **Design compliance**: ⭐⭐⭐⭐☆
- **Security**: ⭐⭐⭐⭐⭐

## 5. Design Document Consistency
{Whether implementation conforms to the design.md approach}

---
*Created by Reviewer on {date} | Based on requirements.md + design.md + implementation.md*
```

### 6. Test Report (`test-report.md`)

```markdown
# Test Report: T-XXX — {Task Title}

## 1. Test Scope
- **Tests based on**: requirements.md + design.md + implementation.md
- **Acceptance criteria reference**: acceptance-criteria.md

## 2. Test Conclusion: {✅ All Passed / ❌ Failures Found / ⚠️ Partially Passed}

## 3. Test Case Results

| # | Case Name | Type | Expected Result | Actual Result | Status |
|---|-----------|------|----------------|---------------|--------|
| 1 | {name} | Functional/Boundary/Exception | {expected} | {actual} | ✅/❌ |

## 4. Failed Case Details
### TC-{N}: {Case Name}
- **Reproduction steps**: {steps}
- **Expected**: {expected result}
- **Actual**: {actual result}
- **Screenshots/logs**: {if any}

## 5. Coverage
- **Requirements coverage**: {X}/{Y} requirements tested
- **Acceptance criteria coverage**: {X}/{Y} ACs verified
- **Code coverage**: {if coverage data available}

## 6. Risk Assessment
- {Untested areas}
- {Non-blocking issues found}

---
*Created by Tester on {date} | Based on requirements.md + design.md + implementation.md*
```

---

## 3-Phase Mode Extension

In 3-Phase mode, documents are more granular:

| Phase | Output Documents |
|-------|-----------------|
| requirements | `requirements.md` + `acceptance-criteria.md` |
| architecture | `design.md` (§2.1 Architecture section) |
| tdd_design | `design.md` (§5 Testing Recommendations → full test design) |
| dfmea | `design.md` (Appendix: DFMEA risk analysis) |
| design_review | `review-report.md` (design review version) |
| implementing | `implementation.md` |
| code_reviewing | `review-report.md` (code review version) |
| ci_monitoring | `test-report.md` (CI report section) |
| device_baseline | `test-report.md` (device baseline section) |
| regression_testing | `test-report.md` (regression testing section) |
| feature_testing | `test-report.md` (feature testing section) |
| log_analysis | `test-report.md` (log analysis section) |
| documentation | `implementation.md` (updated final version) |

---

## Command Support

AI Agents can use the following commands to manage documents:

```bash
# List all documents for a task
ls .agents/docs/T-XXX/

# Check document completeness
for doc in requirements.md acceptance-criteria.md design.md implementation.md review-report.md test-report.md; do
  [ -f ".agents/docs/T-XXX/$doc" ] && echo "✅ $doc" || echo "❌ $doc (missing)"
done
```
