<!--
Sync Impact Report
===================
Version change: [TEMPLATE] → 1.0.0 (initial ratification)
Modified principles: N/A (first concrete adoption; all placeholders replaced)
Added sections:
  - Core Principles: I. Library-First, II. CLI Interface, III. Test-First (NON-NEGOTIABLE),
    IV. Integration Testing, V. Observability, Versioning & Simplicity
  - Additional Constraints
  - Development Workflow
  - Governance
Removed sections: None (template placeholders only)
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ (Constitution Check section already dynamically
    derives gates from this file; no principle names hardcoded, no change required)
  - .specify/templates/spec-template.md ✅ (no principle-specific references; no change required)
  - .specify/templates/tasks-template.md ✅ (no principle-specific references; no change required)
  - .claude/skills/speckit-*/SKILL.md ✅ (no agent-specific or outdated references found)
Follow-up TODOs: None
-->

# Translator Constitution

## Core Principles

### I. Library-First

Every feature starts as a standalone library (e.g., a translation engine, a language-detection
module, a glossary/terminology manager). Libraries MUST be self-contained, independently
testable, and documented. A library MUST exist to provide a clear, callable capability — such
as "translate text from a source to a target language," "detect the source language," or
"apply glossary/terminology overrides" — never merely for organizational convenience.

### II. CLI Interface

Every library MUST expose its functionality through a CLI. Interfaces MUST follow a text
in/out protocol: input arrives via stdin or arguments (source text, source/target language
codes, options) and results are written to stdout; errors and diagnostics go to stderr. Both
JSON output (for machine and pipeline consumption) and a human-readable format MUST be
supported.

### III. Test-First (NON-NEGOTIABLE)

Test-Driven Development is mandatory for all new functionality: tests are written first,
reviewed and approved, confirmed to fail, and only then is the implementation written. The
Red-Green-Refactor cycle MUST be strictly followed. Translation regressions and quality
defects MUST be caught by tests before merge, not discovered by end users.

### IV. Integration Testing

Integration tests are REQUIRED for: new library contract tests, changes to translation or API
contracts, communication with external translation/LLM providers, and shared schemas (e.g.,
glossary format, translation memory format). Integration tests MUST exercise real or
realistic sandboxed provider behavior — mocking external translation providers in these tests
is prohibited, since it would hide contract drift.

### V. Observability, Versioning & Simplicity

Text-based I/O keeps the translation pipeline debuggable; structured logging (source/target
language, provider used, latency, and any quality/confidence signal) is REQUIRED for every
translation request. Libraries and public interfaces follow MAJOR.MINOR.BUILD versioning;
breaking changes to a translation contract require a MAJOR version bump and a documented
migration path. Implementations MUST start simple (YAGNI); added complexity — extra caching
layers, additional provider abstractions, speculative configuration options — MUST be
justified against a demonstrated, current need.

## Additional Constraints

Technology stack, specific translation/LLM provider integrations, and deployment targets are
not yet fixed and MUST be decided and documented (e.g., in each feature's plan.md Technical
Context) as the project takes shape. Regardless of the stack chosen, the following constraints
apply project-wide:

- User-submitted text sent to a translation or LLM provider MUST be treated as potentially
  sensitive; it MUST NOT be logged in full at INFO level or above, and any persisted samples
  MUST be justified and documented.
- Any integration with an external translation or LLM provider MUST isolate provider-specific
  logic behind the library boundary defined in Principle I, so providers can be swapped or
  added without changing calling code.
- Language codes MUST use a documented standard (e.g., BCP 47) consistently across libraries,
  CLIs, and stored data.

## Development Workflow

- All changes MUST go through code review before merging; a reviewer other than the author
  MUST approve.
- CI MUST run the full automated test suite (unit, contract, and integration tests) on every
  pull request; a red build blocks merge.
- Every pull request MUST state which Core Principle(s) it touches and confirm the
  Constitution Check (see plan-template.md) was reconsidered if the change affects contracts,
  providers, or public interfaces.
- Deviations from a Core Principle MUST be recorded in the feature's Complexity Tracking table
  with a stated reason and a rejected simpler alternative; unjustified deviations MUST be
  rejected in review.

## Governance

This constitution supersedes all other project practices and templates when they conflict.
Amendments require: (1) a documented rationale for the change, (2) a version bump following
semantic versioning — MAJOR for backward-incompatible principle removals/redefinitions, MINOR
for new principles or materially expanded guidance, PATCH for clarifications and wording
fixes — and (3) propagation of the change to dependent templates (plan, spec, tasks) in the
same amendment. All pull requests and reviews MUST verify compliance with this constitution;
any added complexity MUST be justified per the Development Workflow section above. Runtime
development guidance for contributors lives alongside this constitution and MUST be kept
consistent with it as the project's tooling and docs are added.

**Version**: 1.0.0 | **Ratified**: 2026-07-24 | **Last Amended**: 2026-07-24
