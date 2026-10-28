# Offline material byte-observation prototype

This dependency-free experiment is **not a validator, worker, scanner or readiness
grant**. It has no file, network, environment, credential, Storage or database
access. Tests use synthetic bytes in memory. Neither retained quarantine object
is read or changed. Production runtime selection remains open.

## Run

From the repository root, with Node installed:

```sh
node --check tools/material-validation/observation.mjs
node --test tools/material-validation/observation.test.mjs
```

Local verification uses Node 25.7.0. The separate CI workflow targets Node 22;
its remote result is not established by a local pass.

2026-10-24 latest main verification: **122 tests passed, zero failed/skipped**, and both
module/test syntax checks passed. Independent Backend Architect review caught
a cleanup-property lookup exception leak; the protected lookup/call fix and
successful/cancelled regression tests were re-reviewed. Other app/database
suites and the installed APK were not rerun or changed by this experiment.

The later39cases cover malformed iterator results, throwing getters and
cancellation ordering. A reproduced lookup-to-call gap was fixed by rechecking
termination after retrieving the pull method; the receiver is preserved.
Independent bounded re-review found no remaining next() blocker. This does not
sandbox executable adapters. See the proposed
[worker isolation acceptance](../../docs/MATERIAL_WORKER_ISOLATION_ACCEPTANCE.md).

## Contract

`observeBytes({ source, expectedByteLength, signal?, timeoutMs?, maxBytes? })`
accepts a trusted synchronous factory `source(abortSignal)` returning an async
iterable of Uint8Array chunks. Only these own data fields on a plain/null-prototype
object are accepted; getters, unknown fields and invalid budgets are rejected
before starting the source. Shared/resizable byte backing stores are rejected.

Provisional experimental limits, not approved production policy:

- Exact expected size: integer 1 through maxBytes.
- maxBytes: default and ceiling 20 MiB; minimum 1.
- timeoutMs: default and ceiling 20,000 ms; minimum 1.
- Maximum chunks: 65,536, including empty chunks.
- Yield to the event loop every 64 chunks; absolute elapsed deadline checks
  supplement the timer. Copy and hash each accepted chunk before another pull.

A complete exact-size stream returns a frozen object containing
`outcome: 'observed'`, byteLength and lowercase SHA-256. All results include
`eligible: false`, `generationVerified: false`, `scanner: 'not_run'`.
Failures return only these three flags and one outcome:
`invalid_input`, `too_large`, `size_mismatch`, `timeout`, `cancelled`,
`source_error`, `unsupported_chunk`, or `chunk_limit`.
No partial digest, bytes, original error or source identity is returned.

Adapters are trusted, cooperative executable code: this is **not a JavaScript
sandbox**. Timers cannot preempt synchronous blocking factories, pulls or cleanup.
Abort and iterator cleanup are requested on termination; cleanup promises are
observed without awaiting a potentially stalled operation. This does not prove
an underlying syscall, remote transfer or writer stopped. A future isolated
worker must independently enforce process/resource and external-I/O bounds.

No parser, MIME/format validation, malware/signature policy, immutable server
generation proof, callback schema, attachment, publication, cleanup or delivery
is implemented. A local digest is not evidence about a Storage object.
See [the validation design](../../docs/MATERIAL_VALIDATION_DESIGN.md).

Built-in API references:
[Node crypto hashing](https://nodejs.org/api/crypto.html),
[Node timers](https://nodejs.org/api/timers.html).
