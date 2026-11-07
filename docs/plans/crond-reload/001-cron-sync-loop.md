# 001: cron-sync loop for live /etc/cron.d reload

Routing category: STANDARD

## Objective

Add a background spool-resync loop so `/etc/cron.d` adds, edits and deletions reach the running dcron within about 2 minutes (one 60s sync tick plus dcron's next minute wakeup), without a container restart.

## Context

- Live bug: the deployed cron container runs this image; `/etc/cron.d` edits never reach dcron until restart. Deployment evidence was gathered in a private handover.
- Boot flow today: `scripts/docker-entry.sh:5-7` wipes `/var/spool/cron/crontabs`, copies `/etc/cron.d/*` once (`[ "$(ls -A /etc/cron.d)" ] && cp -f /etc/cron.d/* /var/spool/cron/crontabs/ || true`), then writes `CRON_STRINGS` from env and chmods 0644. `scripts/docker-cmd.sh:5-11` runs `crond -s /var/spool/cron/crontabs ...` in two branches on `CRON_TAIL`.
- dcron 4.5 mechanics, primary source `dubiousjim/dcron` `database.c` + `main.c` (fetched from GitHub master, 2026-11-07): the spool is fully re-parsed once per hour; prompt reload happens only via `<spool>/cron.update`, checked each minute by `CheckUpdates` (remove-then-read, one basename token per line, extra tokens ignored when `user_override` is set). `SynchronizeFile` deletes the in-memory entry BEFORE it reopens the file, so a `cron.update` line for a deleted file promptly drops that schedule. `SynchronizeFile` silently skips spool files whose uid is not the daemon uid (root), and every scan silently skips names containing a dot. `SynchronizeDir` removes `cron.update` during its hourly resync, so an unconsumed notification is harmless.
- Base image: `ghcr.io/mlatorre31/alpine-python:3.11-slim` (Linuxserver-style), dcron installed via `apk-requirements.txt`, busybox userland, POSIX sh, no inotify-tools. `Dockerfile:20` `COPY /scripts/* /` ships everything in `scripts/` to `/`, so a new script needs no Dockerfile change.

## Global Constraints

- POSIX sh only (busybox ash): no bashisms, no arrays, no `local` dependence for correctness.
- No new packages; no `Dockerfile` or `Dockerfile.remote` changes.
- Fixed 60s sync interval, no env knob.
- Plain `cp` only (never `-p`, `-a` or any ownership-preserving mode) plus explicit `chmod 0644` on every spool write: dcron silently ignores spool files not owned by root.
- The loop never exits: every command guarded, any failure logs one line and the tick continues. A dead loop silently reintroduces the original bug.
- Single instance, started once by `docker-cmd.sh` at `/cron-sync.sh` (installed path).

## Scope

- R1. Create `scripts/cron-sync.sh` implementing the tick algorithm below, loop running forever, first tick immediately then every 60 seconds.
- R2. Modify `scripts/docker-cmd.sh`: start `"/cron-sync.sh" &` once, after `atd`, before the `CRON_TAIL` if (covers both branches).
- R3. Update `README.md`: document the live reload behavior (adds/edits apply within ~2 min, deletions too), the no-dot filename constraint, the root-ownership requirement, and the name guards (`cron.update`, `CRON_STRINGS`, leading-dot files are never managed by the loop).
- R4. Prove it with the local docker functional test below. This repo has no test framework; the container run is the test.

## Technical design

Tick algorithm (directional; ordering is normative, do not reorder):

1. `mkdir -p` the spool dir (entry.sh created it at boot; recreate defensively).
2. Copy phase: for each regular non-hidden file F in `/etc/cron.d` (skip names `cron.update` and `CRON_STRINGS` via a case pattern): if `spool/F` is missing or `! cmp -s src dst`, then `cp src spool/.cron-sync.tmp && chmod 0644 spool/.cron-sync.tmp && mv -f spool/.cron-sync.tmp spool/F`; record F as `added` or `updated` only if the name passes the safe-name check (step 4); an unsafe name is still copied but recorded with a warning and never notified.
3. Sweep phase (after copy): for each regular non-hidden file F in the spool (skip `cron.update`, `CRON_STRINGS`, `.cron-sync.tmp`): if `/etc/cron.d/F` is missing, `rm -f spool/F`, record F as `removed` under the same safe-name rule as step 2.
4. Safe-name rule (single owner of the guard): a name enters the notification set only if it consists solely of `[A-Za-z0-9_-]`, checked at the moment it is recorded in steps 2 and 3, never after accumulation (a name containing a newline would otherwise split into arbitrary valid-looking tokens in the notify loop). Invalid names: log the warning once, keep the copy/sweep behavior, never notify. The notify phase appends each recorded `<name>\n` to `spool/cron.update` (append mode creates the file); re-checking the pattern in the notify loop is defense in depth, not the guard.
5. Logging to stdout: one startup line (`cron-sync: watching /etc/cron.d -> /var/spool/cron/crontabs every 60s`), one line per change (`cron-sync: added|updated|removed <name>`), one line per error; silence on quiet ticks.

Why the ordering matters: copy before sweep so a file replaced mid-tick is never swept; the dotted tmp name plus same-filesystem `mv` makes the spool transition atomic, so dcron never reads a torn file (a torn host write self-heals next tick because the content then differs); notify last, once per tick, so `cron.update` holds each changed name exactly once.

## Files

- Create: `scripts/cron-sync.sh` (mode 0755, consistent with the other scripts)
- Modify: `scripts/docker-cmd.sh` (one added line)
- Modify: `README.md`
- Test: local docker run per Test scenarios (no repo test dir; add none)

## Test scenarios

Seam for all: a throwaway container from a locally built image (`docker build -t crond-reload-test .` in the worktree), host dirs under `/tmp/opencode/crond-reload-test/` mounted at `/etc/cron.d` and `/app` (job logs land in the `/app` mount, observable from the host); observe via `docker exec` and `docker logs`; never touch any live system. Dcron fires at minute boundaries: use tolerances of ~70s for a first fire after add, ~2.5 min for edit/delete propagation.

- Happy path add: `cron.d/jobA` = `* * * * * date >> /app/jobA.log`; expect a log line within ~70s of the next minute boundary and `jobA` present in the spool owned by uid 0 (`docker exec <c> ls -ln /var/spool/cron/crontabs`).
- Edit: change jobA's schedule to fire at a specific next minute; old schedule stops firing, new fires; total delay after the edit ≤ ~2.5 min; `cron.update` contained `jobA`.
- Delete: remove `jobA` from `cron.d`; job stops firing within ~2.5 min, spool copy gone. (Source-verified prompt drop; if it only stops at the hourly resync, capture the observed lag in the report rather than changing the design.)
- CRON_STRINGS preservation: start with `-e 'CRON_STRINGS=* * * * * date >> /app/env.log'`; the env job keeps firing across add/edit/delete of file jobs; `CRON_STRINGS` still in the spool at the end.
- Empty `cron.d`: start with an empty mount dir; no error spam in logs, loop alive (`docker exec <c> pgrep -f cron-sync`).
- Leading-dot file: create `.hidden` in `cron.d`; never appears in the spool.
- Dotted name: create `jobB.txt`; copied to the spool but never scheduled and never notified (documented dcron rule).
- Name guards: create files literally named `cron.update` and `CRON_STRINGS` in `cron.d` on a fresh run; the loop never overwrites the spool's live `cron.update` or the env-generated `CRON_STRINGS` (boot-time copies of them are harmless: crond's startup resync removes `cron.update`, and entry.sh writes `CRON_STRINGS` after its copy so env wins).
- Quiet ticks: after changes settle, touch a marker inside the container, wait ~130s: no new `cron-sync` log lines and no spool file newer than the marker.
- Hostile filename: create a file whose name contains a newline (`a<LF>b`) in `cron.d`; the file is still copied to the spool, exactly one invalid-name warning is logged, and `cron.update` never gains a line for `a`, for `b`, or for the full name. Host-side verification with the script's `src_dir`/`spool_dir` redirected to temp dirs is acceptable for this scenario.
- `sh -n scripts/cron-sync.sh` passes (shellcheck optional; spawned shells may lack it on PATH).
- Build fallback: if the GHCR base image pull fails, verify behavior with a plain `alpine` container (`apk add dcron`), mounting the built `scripts/` and replicating entry+cmd manually; report which path was used. Do not substitute the image's base.

## Unchanged invariants

- `scripts/docker-entry.sh` boot behavior unchanged (wipe, one-shot copy, CRON_STRINGS, chmod).
- `scripts/docker-cmd.sh` keeps both `CRON_TAIL` branches and their crond invocations verbatim; only the one added background start line changes it.
- `Dockerfile`, `Dockerfile.remote`, `example-crontab`, `.github/workflows/docker-image.yml` untouched.

## Skills to use

- `verification-before-completion`

## Non-goals / Later

- No live actions: image rebuild, container recreate and live verification happen after merge via Marco's GH Actions build and his own update flow; this task touches only local docker.
- No env knobs, no inotify dependency, no scheduler swap, no cron.update format experiments beyond the verified protocol.

## Deferred questions

- Whether Alpine's packaged dcron build matches the dubiousjim master behavior verified above. Working assumption: yes (Alpine ships dcron 4.5 of the same fork). CHANGE IF: the local functional test shows an add/edit not applying within ~3 minutes; then inspect the dcron installed in the image before changing the sync design.
