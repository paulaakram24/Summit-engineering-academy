# Material worker isolation — implementation acceptance plan

2026-10-24. Proposal only; no worker, image, scanner or cloud service provisioned.
This supplements [trusted validation](MATERIAL_VALIDATION_DESIGN.md), not replaces
its immutable-generation, authorization, attachment and delivery gates.

## Fresh local feasibility check

Docker CLI and Desktop executables are present. A read-only Docker engine query
failed because the Linux-engine named pipe was absent. Windows reports WSL is
not installed. An executable on disk is not a functioning Linux isolation host.
No Windows feature, virtualization setting, installation, daemon, reboot or
existing process was changed by this check.

Recommended next development route: an explicitly selected disposable Linux
environment with a hardened, pinned container configuration, using only
synthetic input initially. A plain Windows Node child process is useful for
supervision experiments but does not establish filesystem, network, identity,
native-memory or descendant-process isolation. Do not substitute it for this
acceptance gate. No hosted account, paid service or external file submission
is authorized by this proposal.

## Required separation and evidence

1. Acquisition controller owns narrowly scoped fetch authority and verifies the
   exact immutable source generation. The parser/scanner receives bounded bytes,
   not Supabase credentials, user sessions, signed URLs or live bucket access.
2. Each untrusted-input job runs as non-root in a disposable sandbox with no
   network, Docker socket, host credentials, broad host mounts or host process
   namespace. Root filesystem and tool/signature inputs are read-only; scratch
   space is private and size-bounded. Drop capabilities and apply reviewed
   seccomp/no-new-privileges controls. Containerization alone is not a complete
   security guarantee; review the host and configuration attack surface too.
3. An external supervisor enforces wall-clock termination, bounded job capacity,
   output bytes and a bounded post-kill drain. Use kernel-backed memory/CPU/PID
   and scratch limits; JavaScript heap flags and stream deadlines do not bound
   all native allocations, process descendants or disk writes.
4. Trusted supervisor validates a narrow result schema, job/attempt binding,
   digest, tool/policy/signature generations and exit state. Missing evidence,
   malformed output, timeout, crash or failed termination remains unavailable.
   Never turn an arbitrary child message or zero exit code into readiness.
5. No privileged acquisition secret crosses the parser boundary. Failure logs
   contain stable codes and correlation IDs only, not filenames, file contents,
   original exceptions, object locators, hashes or environment dumps.

## Numeric policy is a separate release gate

The current offline observer's 20 MiB, 65,536 chunks and 20-second ceilings are
experimental acquisition limits only. They do not choose parser/scanner memory,
signature freshness or an end-to-end deadline.

Before any positive verdict, pin and benchmark the selected engines against
synthetic valid, malformed and resource-expansion fixtures. Record exact
per-stage wall/CPU/memory/PID/scratch/output limits, job concurrency, queue
capacity, total deadline, kill/drain deadline and retry count in a versioned
policy. Reject omitted or unsupported controls. Antivirus engines may require
substantial signature memory; do not silently omit limits to make them run.
No engine, signature source or numeric parser/scanner policy is selected here.

## Acceptance sequence before live integration

- Prove the host is available and all requested controls are effective, not
  merely accepted configuration fields.
- Use disposable nonsensitive fixtures to demonstrate denied network and host
  filesystem access, absent credentials, bounded scratch/output and rejected
  child creation beyond the PID limit.
- Use controlled workloads in the disposable environment to verify CPU-loop
  termination, memory exhaustion and descendant cleanup without exhausting
  the owner's Windows host. Do not run stress fixtures on the unsandboxed PC.
- Prove late/duplicate/malformed responses and crash/kill/drain failure cannot
  produce effective positive evidence. Test queue saturation without dropping
  authorization or enabling unbounded retries.
- Separately prove immutable provider generation/snapshot acquisition and
  callback authentication using expressly authorized synthetic objects.
  Preserve both previously retained quarantine uploads; they are not fixtures
  for new scans by implication.
- Only then review live worker integration, additive schema/policies and
  independent attachment acceptance. Publication/student delivery stay closed.

## Sources checked

Docker documents that resource constraints are not imposed by default and
describes memory/CPU controls in [resource constraints](https://docs.docker.com/engine/containers/resource_constraints/).
Its [security overview](https://docs.docker.com/engine/security/) covers
namespaces, cgroups, daemon access and configuration risks. The sequence and
SEA-specific separation above are our proposed acceptance requirements, not
evidence that any controls have been applied or passed.
