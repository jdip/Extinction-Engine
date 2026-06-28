---
id: REM-20260628-enforce-five-part-spec-validation
status: done
owner: Joseph
created: 2026-06-28
source: PR 1 retrospective
closed: 2026-06-28

# Enforce Five-Part Spec Validation

## Context

The workflow scaffolding work had a spec, but the five required lifecycle
sections were not enforced by validation.

## Remediation

Add a spec validator and include it in local validation.

## Validation

`./scripts/Verify-Specs.ps1` passes and is called by
`./scripts/Invoke-LocalValidation.ps1`.
## Closure

Added docs/specs/TEMPLATE.md, scripts/Verify-Specs.ps1, and Invoke-LocalValidation coverage for durable specs.

## Closure Validation

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Invoke-LocalValidation.ps1
