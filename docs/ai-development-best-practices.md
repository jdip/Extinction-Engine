# AI-Assisted Development Best Practices

This document distills the general practices that have proven useful for AI-assisted software development. It is intentionally system, library, framework, and product agnostic. Treat it as a portable operating model for teams where humans and AI agents share responsibility for implementation quality, validation, and continuous process improvement.

## Core Principle

Build in a way that leaves evidence.

Good AI-assisted development is not only about producing code quickly. It is about making each change understandable, reviewable, testable, reversible where possible, and easier for the next contributor to continue. The default loop is:

1. Understand the current system.
2. Define observable done.
3. Make the smallest coherent change.
4. Verify it with the right tests and runtime checks.
5. Record what changed, what passed, what remains risky, and what should improve next time.

## Working Contract

Use written project contracts as the source of truth. These may be contributor guides, architecture principles, runbooks, spec templates, release policies, or local agent instructions.

- Read the relevant project contract before changing behavior.
- Re-open it during long sessions, large refactors, security-sensitive changes, data migrations, release work, or anything involving production state.
- If the implementation conflicts with the contract, either migrate the implementation toward the contract or document why that cannot happen yet.
- Prefer established local patterns and templates over inventing new shapes.
- Convert repeated lessons into durable docs, scripts, tests, or checklists.

## Start Of Work

Begin each task by making the current state explicit.

- Check version-control status before editing.
- Identify the intended base branch or baseline artifact.
- Pull or sync from the latest trusted remote before creating new work.
- Use one logical branch, worktree, or workspace per task.
- Do not overwrite or revert changes you did not make unless explicitly asked.
- Restate the goal briefly and define observable completion criteria.
- Identify high-risk areas early: auth, permissions, data shape, migrations, concurrency, destructive operations, external services, release automation, and user-visible workflows.

## Spec-First Changes

For non-trivial work, write a short implementation spec before coding. The spec is not ceremony; it is a scratchpad that keeps AI work from drifting.

Every useful spec should include:

- Research: current behavior, constraints, affected files or systems, risks, unknowns, and prior related work.
- Plan: ordered steps, boundaries, rollback notes, and test strategy.
- Implement: concrete changes made and any deviations from the plan.
- Test: automated tests to add or update, plus the relevant existing tests that cover the touched behavior.
- Validate: commands run, pass/fail evidence, environment used, and any skipped checks with reasons.

Keep specs close to the codebase. Move them through lifecycle states if the project uses them, and update them when the work changes. A stale spec is worse than a brief one.

## Version Control

Treat version control as a coordination system, not just a save button.

- Create branches from the latest trusted remote base, not a possibly stale local branch.
- Keep each branch cohesive; split scope when a task grows into multiple concerns.
- Push checkpoints to the remote at meaningful pauses.
- Before review or merge, rebase or merge from the latest base according to project policy.
- Use safe force updates, such as force-with-lease, after rebasing.
- Do not mutate Git state in parallel. Fetches, pulls, rebases, merges, branch moves, and scripted syncs can race on locks.
- Prefer fast-forward-only updates for long-lived local branches.
- Protect the primary release branch with process: changes should arrive through review and validation, not direct commits.
- Clean up merged branches through the project-approved path, and track cleanup backlog if local deletion is unavailable.

## Implementation Discipline

Fix root causes by default.

- Do not rely on manual one-off workarounds to "get through" a task.
- If an emergency mitigation is required, mark it temporary and create a concrete follow-up.
- Make small, independently verifiable changes.
- Keep boundaries explicit between layers, modules, packages, or services.
- Avoid broad refactors unless they are necessary for the task.
- Prefer clear, boring code over clever abstractions.
- Add an abstraction only when it removes real complexity, reduces meaningful duplication, or matches an established pattern.
- Use structured APIs, parsers, and typed boundaries when available instead of ad hoc string manipulation.
- Validate untrusted inputs at system boundaries.
- Keep configuration centralized, documented, and validated at startup.
- Never commit secrets, tokens, private keys, or real credentials.
- Never log secrets.

## Scripts And Automation

Scripts should be the stable interface for recurring development work.

- Prefer checked-in helper scripts over ad hoc command sequences.
- Keep scripts idempotent, explicit, and safe to rerun.
- Make scripts fail fast with actionable messages.
- Avoid command variants that hide failures.
- Do not pipe exit-sensitive validation or release commands through tools that mask the original exit code.
- If a workflow requires the same command several times, automate it instead of relying on memory.
- If a script becomes the blessed path, document when to use it and what evidence it produces.

## Environment Isolation

Validate changes in isolated environments.

- Treat shared staging, production, or operator-owned environments as read-only diagnostic surfaces unless explicitly doing operator recovery.
- Use shared environments to gather evidence: logs, health checks, configuration state, metrics, and read-only probes.
- Do not use shared environments for trial fixes, test execution, migrations, seeding, restarts, destructive cleanup, or exploratory commands.
- Reproduce and verify fixes in an agent-owned or developer-owned environment first.
- Track resources started during a session so they can be cleaned up reliably.
- Avoid multiple live dev servers, watchers, or background workers for the same checkout unless the project explicitly supports them.
- When runtime artifacts are source-baked or cached, rebuild or refresh them before deciding a code fix failed.

## Testing Strategy

Use tests as risk control, not decoration.

- Start with the smallest failing command or reproduction.
- Add focused regression tests for the bug or changed behavior.
- Run nearby existing tests that exercise the same function, module, or workflow.
- Broaden to integration, end-to-end, or full-suite validation when the change touches shared behavior, data contracts, concurrency, permissions, migrations, or release paths.
- Manual testing can supplement automation, but it should not replace automated tests for product behavior.
- Treat coverage as a risk signal, not a vanity metric.
- High-risk logic should have high coverage: authorization, business rules, data transformations, query behavior, migrations, concurrency, serialization, and external-service boundaries.
- Do not suppress a failing safety test just to make a gate pass.
- When un-baselining or changing a known-failing test, search for passing tests that encode competing behavior before changing product code.

## Data And Migration Safety

Data changes deserve extra proof.

- Execute migrations against a real database or equivalent real storage engine, not only static review.
- Verify seeded or representative data after migrations.
- Include legacy-shape coverage when long-lived environments may differ from fresh test environments.
- Probe production-like data read-only before changes that could break existing records.
- Record probe commands and summarized findings in the spec or validation notes.
- Prefer forward fixes over rollback dependence for irreversible or hard-to-reverse data changes.
- Never run migrations, seed flows, or destructive schema experiments against shared production-like environments unless explicitly directed as an operator recovery task.

## Validation Evidence

A change is not done until validation is recorded.

Record:

- Exact command or check name.
- Environment used.
- Result summary.
- Relevant failing output if it failed.
- Any skipped checks and why.
- Residual risks or follow-ups.

When validation fails:

- Run the direct failing command first.
- Preserve the first useful failure.
- Identify whether the failure is caused by the change, stale environment state, flaky infrastructure, or an unrelated known issue.
- Fix root cause when it is in scope.
- Do not broaden blindly before understanding the direct failure.

## Review And Pull Requests

A reviewable change should be easy to reason about.

- Keep diffs focused.
- Explain behavior changes, validation, risks, and rollback notes.
- Call out destructive actions and irreversible steps.
- Include test evidence rather than vague claims.
- Link the implementation spec, issue, or task record when one exists.
- Ensure docs and examples changed with the behavior.
- Require explicit approval for irreversible, destructive, or environment-impacting operations.
- Use protected branches and required validation gates for important integration points.

## Release Discipline

Release processes should be scripted, auditable, and hard to accidentally bypass.

- Use project-owned release entrypoints instead of recreating release steps by hand.
- Keep branch rules aligned with the intended promotion model.
- Run local or trusted validation before promotion, not after.
- Record release proofs, validation artifacts, or equivalent evidence when the project requires them.
- Do not open release or promotion PRs merely to "see what CI says" when a local required gate is already failing.
- Require explicit, phrase-matched human approval immediately before live branch
  promotion workflows. Single-run approvals must not be reused; only an explicit
  unlimited-approval phrase can cover multiple workflow runs.
- Confirm the target branch actually advanced before reporting success.
- After release, sync local state back to the trusted remote baseline.

## Retrospectives And Remediation

Every meaningful failure should either teach the system something or be explicitly accepted.

After every PR, and after failed validations, incidents, or promotions, ask:

- What surprised us?
- Was the root cause in code, tests, docs, automation, environment setup, or communication?
- Could a test have caught this earlier?
- Could a script have made the safe path easier?
- Should project instructions, templates, or runbooks change?
- Is there a material follow-up that should be tracked?

Use a consistent retrospective structure so lessons are comparable over time
and turn into concrete repository improvements. The required structure is:

1. Friction points that need to be addressed in AGENTS.md.
2. Common workflows that should be automated with scripts.
3. Gaps discovered that deserve remediation.

Include a brief PR or event link, outcome, validation evidence reviewed, and
accepted risks as context, but keep the main body focused on those three
action-oriented sections.

Create remediation records only for material follow-up work. Avoid duplicate records. Every material remediation should have an owner, status, and link to the issue, spec, PR, or checked-in record where it will be closed. Keep open remediation records in a clearly named open location, and move them to a done location when implemented, cancelled with rationale, or transferred to another planning system.

## AI Agent Conduct

AI agents should optimize for continuity and evidence.

- Read before editing.
- Prefer project tools and templates.
- Keep user-visible progress updates concise and factual.
- Ask questions only when a reasonable assumption would be risky.
- Protect human work in the workspace.
- Do not invent local state, command results, or validation evidence.
- If context may have drifted, re-open the relevant contract or source file.
- If a command fails due to permissions, sandboxing, or environment access, retry through the approved escalation or helper path rather than silently switching to an unsafe workaround.
- Do not continue long-running validation while editing files that the validation snapshots.
- Before final reporting, sanity-check that the answer addresses the latest request, not an older thread context.

## Portable Checklist

Before coding:

- Workspace status checked.
- Latest trusted base identified.
- Goal and done criteria written down.
- Risks and impacted areas listed.
- Spec or plan created for non-trivial work.

During coding:

- Small changes.
- Existing patterns followed.
- Tests added or updated with the behavior.
- Docs updated with changed commands, contracts, or workflows.
- No secrets or one-off local assumptions introduced.

Before review:

- Focused tests pass.
- Relevant existing tests pass.
- Broader validation run chosen according to risk.
- Validation evidence recorded.
- Diff reviewed for accidental churn.
- Destructive actions and residual risks called out.

After merge or release:

- Local state synced.
- Temporary resources cleaned up.
- Branch cleanup handled or tracked.
- Retrospective completed for every PR.
- Remediation items created only for material, non-duplicate follow-ups.
