# Task 5 — testthat CI Job + README Badge Design

**Date:** 2026-05-19
**Status:** Approved
**Parent plan:** `docs/superpowers/plans/2026-05-18-testthat-suite.md` (Task 5)

---

## Problem

Tasks 1–4 produced a 62-assertion testthat suite (20 model + 38 gbfs + 4 bigquery across three test files, plus a `helper-workdir.R` that contributes no assertions) that passes locally. Without a CI gate, a broken `source()` call, a renamed model coefficient, or a schema regression in `gbfs_client.R` can reach `main` unchallenged. Task 5 closes the loop by running the suite on every push and PR, and surfacing the result on the README.

The original Task 5 sketch in the parent plan assumed:

1. The repo has no `ci.yml` — but it already contains a working three-job CI workflow (`python-check`, `r-check`, `docker-compose-build`).
2. `r-lib/actions/setup-renv@v2` will Just Work — but `r-lib/actions/setup-r@v2` injects `RENV_CONFIG_REPOS_OVERRIDE` into the shell, which forces renv to use PPM-only and historically broke restoration on this repo (resolved in `r-check` by unsetting the variable in bash before invoking `Rscript`).
3. `shiny_app/model.csv` is available in CI — but it is gitignored locally and only the canonical `data/processed/model.csv` is committed.
4. `working-directory: shiny_app` is the correct invocation — but `tests/testthat.R` lives at repo root and uses `rprojroot` internally to set its own cwd.

This spec replaces those four assumptions with the patterns already proven in `r-check`.

---

## Design

Add a single new job — `testthat` — to the existing `.github/workflows/ci.yml`. The new job runs in parallel with the three existing jobs and reuses the renv cache key that `r-check` writes, so the second-to-run job hits a warm cache.

```
ci.yml workflow
├─ python-check         (existing — Python imports)
├─ r-check              (existing — renv restore + library smoke + model.csv read)
├─ docker-compose-build (existing — Dockerfile.shiny build)
└─ testthat             (NEW — runs 62-assertion testthat suite)
```

No new workflow files. One CI badge on the README covers all four jobs.

---

### `testthat` job — step-by-step

| # | Step | Purpose |
|---|------|---------|
| 1 | `actions/checkout@v4` | Clone repo at the current ref |
| 2 | `awalsh128/cache-apt-pkgs-action@latest` (17 packages, `version: 1.0` cache key) | Install + cache native system libraries that R packages link against — same list as `r-check` |
| 3 | `r-lib/actions/setup-r@v2` with `r-version: "4.4.3"`, `use-public-rspm: true` | Match the R version pinned in `renv.lock` |
| 4 | `actions/cache@v4` for `~/.cache/R/renv`, key `${{ runner.os }}-R-4.4.3-renv-3-${{ hashFiles('renv.lock') }}` | Share cache with `r-check` so whichever job runs second hits a warm cache |
| 5 | Restore renv | Bash `unset RENV_CONFIG_REPOS_OVERRIDE` → `Rscript -e "source('renv/activate.R'); options(repos=...); renv::restore()"` — identical pattern to `r-check` |
| 6 | `cp data/processed/model.csv shiny_app/model.csv` | Bridge the gitignore — make the file visible at the path `load_saved_model()` reads from |
| 7 | `Rscript tests/testthat.R` (run from repo root) | Entrypoint sets cwd to `shiny_app/` via `rprojroot`; `CI=true` (GH-Actions default) makes `stop_on_failure = FALSE` so all failures surface in one run |

---

### Why each design decision

**Parallel job, not `needs: r-check`.** Independent green/red signals for "the environment builds" and "the code is correct" are worth more than the ~1 min CI time saved by gating on `r-check`. A flaky `r-check` should not hide a real test failure.

**Shared renv cache key.** `r-check` and `testthat` install the same renv library on the same R version on the same OS. Using identical cache keys lets the second job to start pull warm — saving ~3–4 minutes on the typical run.

**Mirror `r-check`'s renv pattern, not `setup-renv@v2`.** The `unset RENV_CONFIG_REPOS_OVERRIDE` + manual `options(repos=...)` pattern is the only thing on this repo's CI history that has worked end-to-end with R 4.4.3 + renv on ubuntu-latest. Introducing a new restore mechanism in a sibling job would be a gratuitous risk.

**Copy `model.csv`, don't ungitignore it.** The gitignore on `shiny_app/model.csv` exists because the Dockerfile copies it at image build time and committing it would duplicate `data/processed/model.csv` in git. The CI copy preserves the gitignore invariant.

**Run from repo root, not `working-directory: shiny_app`.** `tests/testthat.R` resolves all paths via `rprojroot::find_root(rprojroot::is_git_root)`, so the entrypoint works from any invocation directory. Repo root is the simplest, least surprising choice.

---

## README badge

The repo's existing CI badge in `## 🏷️ Project Badges` already points to `actions/workflows/ci.yml/badge.svg` — the same workflow file the new job lives in. GitHub aggregates job status into a single workflow status, so adding the new job automatically extends the badge's coverage.

**Action:** verify the badge URL during implementation. If absent or stale, add:

```markdown
[![CI](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml/badge.svg)](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml)
```

No `?job=testthat` querystring needed — the workflow-level badge is sufficient for portfolio surfacing.

---

## Runtime budget

| Scenario | Wall clock |
|----------|------------|
| Cold cache (first run, source compile) | ~5 min |
| Warm apt + warm renv cache | ~1 min (20 s apt + 30 s renv + 2 s tests + overhead) |
| Lockfile change (renv cache miss only) | ~3 min |

GitHub Actions free tier on a public repo absorbs all of this comfortably.

---

## Out of scope

- `shinytest2` browser harness for `server.R` / `ui.R` reactives — separate phase.
- pytest suite for any Python helpers in the repo — none currently exist.
- Cross-repo CI dispatch — the sister `bike-demand-ml-system` repo has its own independent CI.
- Codecov / coverage badges — coverage tooling is not yet wired in this repo.

---

## Acceptance criteria

1. `ci.yml` contains four jobs: `python-check`, `r-check`, `docker-compose-build`, `testthat`.
2. The `testthat` job passes on its first GitHub Actions run after merge to `main`.
3. The full suite reports `FAIL 0 | WARN 0 | SKIP 0 | PASS 62` in the job log.
4. The README CI badge renders green on the public repo page.
5. The existing three jobs continue to pass with no regressions.
