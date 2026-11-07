# docker-alpine-cron

Alpine-based cron Docker image (fork of xordiv/docker-alpine-cron, published to
GHCR as mlatorre31/docker-alpine-cron). Runs dcron on a Python-capable base
(ghcr.io/mlatorre31/alpine-python:3.11-slim) with live /etc/cron.d reload.

## Repository structure

```
Dockerfile              # image cron:local (GH Actions build)
Dockerfile.remote       # variant cron:remote (adds tzdata, purges urllib3)
docker-compose.yml      # sample service (upstream artifact; CRON_STRINGS line is corrupted upstream-style, do not trust)
example-crontab         # example cron.d file
apk-requirements.txt    # apk packages, consumed by the BASE image's /entrypoint.sh
build-requirements.txt  # apk build packages for pip wheels (base image consumes)
requirements.txt        # pip packages (base image consumes); this Dockerfile only adds dcron
scripts/
  docker-entry.sh       # ENTRYPOINT: reset spool, copy /etc/cron.d once, write CRON_STRINGS, exec CMD
  docker-cmd.sh         # CMD: atd, start cron-sync.sh background, then crond (CRON_TAIL branches)
  cron-sync.sh          # 60s spool resync loop + dcron cron.update notifications
data/docker/docker-cron/app/test/test.sh  # sample mounted job
docs/
  plans/<feature-key>/  # plan artifacts and task briefs
  handovers/            # cross-session handover briefs
  solutions/            # institutional knowledge; check here before planning (start: infrastructure/dcron-live-reload.md)
.github/workflows/docker-image.yml  # on push to master: builds and publishes cron:local + cron:remote to GHCR
```

## Development

Language: POSIX shell (busybox ash inside the image) plus Docker. Package changes go
through the three requirements files, which the BASE image's entrypoint consumes;
this repo's Dockerfiles only add dcron/tzdata via `-a` flags.

### Commands

```bash
docker build -t docker-alpine-cron:local -f Dockerfile .    # build the image
sh -n scripts/cron-sync.sh                                  # syntax check a script
```

No test framework and no lint target exist. Functional testing = throwaway
container run with host dirs mounted at /etc/cron.d and /app (see
docs/plans/crond-reload/001-cron-sync-loop.md, Test scenarios, for the pattern).
dcron fires at minute boundaries: allow ~70s tolerance for a first job fire,
~2.5 min for live-reload propagation.

### Key dependencies

| Component | Purpose |
|-----------|---------|
| ghcr.io/mlatorre31/alpine-python:3.11-slim | base image; its /entrypoint.sh consumes the requirements files |
| dcron | scheduler (apk); spool at /var/spool/cron/crontabs, live reload via cron.update |
| at | atd, started by docker-cmd.sh |
| pandas / apprise / pdfplumber / bs4 / openpyxl | pip packages installed by the base image for mounted jobs |

## Code conventions

- **Shell dialect:** POSIX sh only, busybox-compatible; no bashisms, no arrays.
- **Indentation:** tabs.
- **Variables:** lowercase snake_case; quote at use sites.
- **Error handling:** short scripts use `set -e`; long-running loops never exit
  (guard every command, log one `printf 'cron-sync: error: ...'` line, continue).
- **Patterns:** atomic spool writes (`cp` to dotted tmp in the same dir, `chmod`,
  `mv -f`); reserved-name and safe-name `case` guards before accumulating state;
  plain `cp` only (never ownership-preserving) plus explicit `chmod 0644`.
- **File modes are load-bearing:** scripts stay 0755 (Docker COPY preserves modes;
  ENTRYPOINT/CMD exec them directly); spool files 0644 root-owned or dcron
  silently ignores them.

## Testing

```bash
docker build -t docker-alpine-cron:local -f Dockerfile . && docker run --rm ...
```

No test framework. Prove behavior with a local build plus a throwaway container;
verify spool state via `docker exec ... ls -ln /var/spool/cron/crontabs` and logs
via `docker logs`. Never test against a live host.

## Documentation workflow

After significant work: update `docs/solutions/` when a non-obvious lesson
surfaced, keep plan artifacts under `docs/plans/<feature-key>/`, and update the
README when image behavior changes.

## Git workflow

- **Always ask the user before committing.** Never auto-commit.
- Conventional-commit messages (via the `git-commit` skill).
- Default branch is **`master`**; one commit per logical, reviewable, revertable unit.
- **Pushing `master` publishes image tags** (GH Actions matrix, cron:local and
  cron:remote). State that blast radius before any push.

## Conventions

- YAGNI: smallest solution that works.
- @architect never edits source code directly; implementation is delegated.
- Planning artifacts live under `docs/`.
- @architect uses only read-only git commands (log, status, diff, show, branch).
