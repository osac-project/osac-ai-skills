---
name: logging-guidelines
description: Apply OSAC logging and error-handling guidelines when implementing or reviewing services, controllers, libraries, or automation. Use when adding or changing logs, error propagation, retries, cleanup, or asynchronous work, including implement and bugfix workflows.
metadata:
  version: "0.1.0"
---

# Logging Guidelines

Read the affected component's instructions and neighboring logging/error paths
first. Use its existing logger, field names, and framework conventions; do not
introduce another logging abstraction. Apply this policy when writing code and
reviewing changes, not as a reason to rewrite unrelated logging.

## When to Log

- Log meaningful lifecycle events, operation outcomes, and state transitions
  that help an operator understand progress or diagnose a problem.
- Log actionable unexpected failures at their owning boundary. Keep terminal
  failed operations observable through the established outcome log, status,
  or error response; handling an error must not silently turn failure into success.
- Skip routine function entry/exit, unchanged polls, successful per-item work,
  and repeated "still waiting" messages. Use metrics for counts/rates and traces
  for timing/call paths; correlate them rather than copying full detail into logs.

## Choose Levels by Operational Impact

| Level | Use |
|-------|-----|
| Debug | Diagnostic detail, expected retries, intermediate attempts, or routine polling when investigation needs it. |
| Info | Significant lifecycle/state changes and normal operation outcomes. Expected validation rejection or cancellation may need no log at all. |
| Warn | A handled but significant degradation, fallback, or unusual retry condition that merits operator attention while work can continue. |
| Error | An operation that failed unexpectedly or exhausted recovery and needs attention; include the cause and outcome. |

- Judge impact and outcome, not merely `err != nil`. Retries, cancellation,
  not-found during deletion, and expected validation failures are not
  categorically Errors. Unexpected cancellation or persistent retry degradation
  can warrant escalation; report the terminal failure once recovery is exhausted.
- Respect concrete level support: `slog` has Debug/Info/Warn/Error;
  controller-runtime's `logr` interface has `Info`, verbosity via `V(n).Info`,
  and `Error`, not `Warn`. Follow component verbosity conventions and use
  `Info` with safe degradation context when a warning-like event is appropriate.
  Do not invent a Warn API or use Error merely because Warn is unavailable.
- Do not use fatal logging, process exit, or panic for ordinary failures in
  library, request, or reconcile paths. Return the error to the existing owner.

## One Owner per Error Outcome

- Trace the caller chain before adding an error log. Lower layers add safe
  operation/resource context and return or wrap; the boundary that handles the
  outcome logs it once. Avoid logging an error and returning it to another logger.
- Count framework/interceptor logging as ownership. For controller-runtime,
  return a contextual error for the framework to log and retry instead of also
  calling `log.Error` for that same returned error. Follow the actual framework
  contract; fulfillment-service's own reconciler is not controller-runtime.
- If asynchronous work has no returning caller, its worker/supervisor owns
  reporting the outcome. If an error is suppressed or consumed, identify who
  records the failure/degradation; log there when actionable, or document why
  expected benign outcomes need no log. Do not discard failures to avoid duplicates.
- Distinct state-transition/recovery events are useful; repeated copies of the
  same stack/cause at every layer or retry are not. Rate-limit, sample, or
  aggregate repeated diagnostics using existing mechanisms, while retaining
  the first actionable signal and terminal outcome.

## Preserve the Original Error

- Preserve causes/chains and error identity for callers: use Go `%w` wrapping
  when adding context, or Python exception chaining (`raise ... from error`).
  Do not replace a failure with contextless text, a new unrelated error, or nil.
- Avoid "shading" errors: neither obscure the original cause with a vague log
  nor accidentally shadow/overwrite the failing error variable. Use distinct
  names for cleanup/logging failures; preserve the primary failure and report
  secondary failures separately or join them using the project's convention.
- For example, return `fmt.Errorf("load resource %s: %w", resourceID, err)`
  from a lower layer instead of logging there and returning `errors.New(err.Error())`.
  In a named-return function, avoid a deferred `err = cleanup()` that erases
  the original failure or replaces it with success.

## Safe Structured Context and Cost

- Use stable structured keys for operation, outcome, request/trace ID, and
  resource/tenant identifiers where permitted. Reuse context-bound loggers;
  keep event messages stable rather than embedding changing values in prose.
- Allowlist safe fields. Never log credentials, tokens, authorization headers,
  private keys, or raw request/response/resource payloads. Redact sensitive
  personal/tenant data and inspect error strings too: they can carry secrets.
  Bound and sanitize untrusted values, including newlines; structured encoding
  alone does not make an arbitrary payload safe.
- Avoid per-item/retry floods, duplicate stacks, and unbounded fields. Guard
  expensive debug serialization/computation with the logger's enabled-level
  check; disabled logging must not still build a full payload.

## Review Check

For each changed error path, identify the outcome, log owner, supported level,
safe correlation fields, and preserved cause. Check retry/cleanup/async paths
as well as success; verify terminal failures remain observable without duplicates.
