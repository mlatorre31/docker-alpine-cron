---
title: "dcron live reload: cron.update protocol, silent uid skip, validate-before-accumulate"
category: infrastructure
scope: reusable
applies_when: any setup running Alpine dcron 4.x where crontabs are copied into the spool at boot and must change without a restart
retire_when: dcron ships prompt spool rescanning by default or the image switches cron daemons; verify by reading crond's main loop (per-minute CheckUpdates vs hourly SynchronizeDir)
date: "2026-11-07"
tags:
  - dcron
  - cron
  - docker
  - alpine
  - spool
  - reload
related_components:
  - scripts/cron-sync.sh
  - scripts/docker-entry.sh
  - scripts/docker-cmd.sh
---

## Problem

Editing a file in the bind-mounted `/etc/cron.d` of a container running dcron did nothing until the container was restarted; a schedule edited on Oct 18 kept firing its pre-edit version for six days. Root-run crontab changes looked structurally impossible to apply live.

## Root cause

dcron 4.x parses the spool directory (`crond -s <dir>`) once at startup, fully re-parses it only once per hour, and reloads a file promptly ONLY when its basename is appended to `<spool>/cron.update` (the same notification channel its own `crontab` command uses; one token per line, file removed after read). A copy-once-at-boot setup therefore leaves every later edit invisible. Two silent traps make hand-rolled resyncs fail without any log line: `SynchronizeFile` skips spool files whose uid differs from the daemon uid (so `cp -p` from a host mount silently disables the job), and every scan silently ignores any name containing a dot.

## Solution

A small resync loop (see `scripts/cron-sync.sh`): every 60s, content-compare source dir vs spool, install changed files atomically (plain `cp` to a dotted tmp name inside the spool dir, `chmod 0644`, same-filesystem `mv -f`), mirror deletions while preserving reserved files (`CRON_STRINGS`, `cron.update`), and append each changed basename to `cron.update`. Deletions are prompt by design: `SynchronizeFile` deletes the in-memory entry BEFORE reopening the file, so notifying a removed name drops its schedule at the next minute wakeup. The hourly full resync is the structural fallback if any notification is missed.

## Key takeaway

Give the daemon its own update channel instead of signals or restarts: dcron has no SIGHUP reload; the supported prompt-reload path is appending basenames to `cron.update`. Validate host-supplied filenames at the moment they are recorded, never after newline-delimited accumulation (a newline inside a filename splits into arbitrary valid-looking tokens). Copy without preserving ownership (plain `cp` + explicit `chmod`), because dcron silently ignores files it does not own.
