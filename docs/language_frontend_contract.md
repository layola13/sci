# Language Frontend Compile-Service Contract (v1)

Status: implemented (host routing in `src/cli.zig`, extension registry in
`src/plugins.zig`). Design source: sala `05_plugins/20_system_redesign`.

A *language frontend* is a plugin whose `sap.json` declares:

```json
{
  "kind": "language",
  "language_extensions": [".sla"]
}
```

Missing `kind` means `command` (the classic plugin). An unknown `kind`
value is rejected with `InvalidSapManifest`; there is no fallback.

## Host guarantees

- The host loads every installed plugin and registers each language
  frontend's extensions. If two frontends claim the same extension, the
  first registration wins and the host records a diagnostic; resolution
  is never silently ambiguous.
- For file-consuming verbs — `check`, `test`, `build`, `build-exe`,
  `build-wasm`, `build-js`, `build-c`, `build-obj` — when the positional
  source file's extension is registered, the host routes through the
  frontend before running its own pipeline. With no frontend registered
  for the extension, host behavior is exactly as before this contract.
- At most one language source file per invocation in v1; more is an
  explicit `SA-LANGUAGE-FRONTEND` error, never a partial compile.
- The process environment is the host's own (in particular the frontend
  finds the standard library through the host's established channels —
  `SA_STD_DIR`, then the executable-relative layout — never by guessing
  user-specific paths).

## Frontend obligations

Commands are delivered through the plugin ABI `handle_command` with the
argv convention `["sa", "<frontend-name>", <subcommand>, ...]`.

- `build <source> --out <path>`: compile `<source>` to SA text and write
  it to exactly `<path>` (the host chooses the path; v1 uses the sibling
  `<name>.sa`). Success is exit code 0 **and** the file present at
  `<path>`; the host verifies presence and fails with
  `SA-LANGUAGE-FRONTEND` otherwise. Failure must be a nonzero exit code
  with diagnostics on stderr; the host then stops with that code and
  never falls back to parsing the source itself.
- `check <source> [args...]` / `test <source> [args...]`: the host
  forwards the user's full argument list after the frontend name and
  returns the frontend's exit code verbatim.
- A frontend that does not implement a subcommand returns
  `unknown_command`; the host reports that explicitly.

## Diagnostics and cache keys

- Diagnostics travel on stderr. SA-level traps already use the host's
  structured JSON format; frontend-native diagnostics (e.g. SLA type
  errors) are plain text in v1 and are passed through unchanged.
- Cache keys are the frontend's content hash over the source plus its
  dependency graph (the SLA freshness gate). Hoisting that gate into a
  shared host cache service is phase 2 of the redesign; until then the
  frontend owns its cache (`.sla-cache/`) and the host owns only the
  intermediate `.sa` placement.

## Non-goals (v1)

- No separate compile ABI entry point: with exactly one language
  frontend in existence, the command convention above is the contract,
  and it is deliberately tailored to SLA's real behavior instead of a
  speculative generalization.
- `sa <frontend> *` remains available during the transition; the
  standalone frontend binary remains a thin alias.

## Permission confirmation (all plugin kinds)

Confirmation belongs to the host, not the distribution channel. A
plugin that arrives without a matching `permissions.lock` (copied by
hand, unpacked from an archive, installed by a package manager) is
blocked in formal mode with a three-part diagnostic. The remedy is:

- `sa plugin confirm <name>` — prints the permission review and prompts
  on the TTY; on approval it writes the same `permissions.lock` a formal
  install would have produced (current dir and version dir).
- `sa plugin confirm <name> --yes` — the explicit non-interactive form;
  the review is still printed before the lock is written.
- Confirmation is bound to the manifest's permission digest: any later
  declaration change invalidates it and confirmation must be repeated.
  A plugin that declares no privileged permissions needs no
  confirmation.
