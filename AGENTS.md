## Bug Fixing Rules

- When fixing bugs, do not guess and do not "blind patch".
- Before changing code, first identify the execution path that is actually in use.
- Prefer reproducing the bug, reading the relevant code path, and checking current runtime state before editing.
- If multiple components could own the behavior, confirm which target, extension, view, or service is responsible before making changes.
- When a bug depends on device state, shared storage, permissions, timing, or configuration, inspect those inputs directly instead of inferring them.
- If a previous fix appeared to work only sometimes, treat that as a signal that the root cause is still unknown.
- Default debugging order:
  1. Confirm the active code path.
  2. Inspect the real inputs and persisted state.
  3. Form a concrete hypothesis.
  4. Make the smallest change that proves or fixes that hypothesis.
  5. Verify the result in the environment where the bug actually happens.
- Do not replace a root-cause investigation with repeated UI tweaks, color tweaks, spacing tweaks, or fallback logic unless the root cause is already confirmed.
- If diagnosis is still uncertain, add temporary diagnostics outside user-facing UI, verify them, then remove or minimize them once the bug is understood.
