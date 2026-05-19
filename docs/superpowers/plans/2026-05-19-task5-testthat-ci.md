# Task 5 — testthat CI Job Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fourth `testthat` job to the existing `.github/workflows/ci.yml` that runs the 62-assertion testthat suite on every push and PR to `main`, and verify the existing README CI badge covers it.

**Architecture:** One new job appended to the existing `ci.yml`. The job runs in parallel with `python-check`, `r-check`, and `docker-compose-build`. It mirrors `r-check`'s system-deps + renv-restore pattern (apt cache action, `unset RENV_CONFIG_REPOS_OVERRIDE`, manual `options(repos=...)`) and shares the same renv cache key so whichever job runs second hits a warm cache. The job copies `data/processed/model.csv` to `shiny_app/model.csv` (gitignored locally) before invoking `Rscript tests/testthat.R` from the repo root.

**Tech Stack:** GitHub Actions, ubuntu-latest, R 4.4.3, renv 1.x, testthat 3.x, mockery, `awalsh128/cache-apt-pkgs-action@latest`, `r-lib/actions/setup-r@v2`.

**Spec reference:** `docs/superpowers/specs/2026-05-19-task5-testthat-ci-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `.github/workflows/ci.yml` | Modify (append) | Add the new `testthat` job after the existing `docker-compose-build` job |
| `README.md` | Verify only (no edit expected) | Confirm `[![CI](...)]` badge at line 19 already points to `actions/workflows/ci.yml/badge.svg` |
| `data/processed/model.csv` | Read-only check | Pre-flight: confirm the source file the CI step will copy from is committed and non-empty |

---

### Task 1: Pre-flight verification

Read-only checks before touching any file. No commits in this task.

**Files:**
- Verify: `data/processed/model.csv` exists and is non-empty
- Verify: `.github/workflows/ci.yml` exists with the three existing jobs intact
- Verify: `README.md` already has the CI badge at line 19
- Verify: local test run still passes (`tests/testthat.R` → `PASS 62`)

- [ ] **Step 1: Confirm `data/processed/model.csv` is committed and non-empty**

```bash
ls -la "D:/OneDrive/Developer/DataAnalytics/R_projects/bike_demand_prediction/data/processed/model.csv"
git -C "D:/OneDrive/Developer/DataAnalytics/R_projects/bike_demand_prediction" ls-files data/processed/model.csv
```

Expected: file size > 0 bytes; `git ls-files` prints the path (i.e. it is tracked, not gitignored). If the file is gitignored at this path, stop and escalate — the spec assumes it is committed.

- [ ] **Step 2: Confirm the existing ci.yml structure**

```bash
grep -n "name:\|^  [a-z]" "D:/OneDrive/Developer/DataAnalytics/R_projects/bike_demand_prediction/.github/workflows/ci.yml"
```

Expected output includes three job names: `python-check`, `r-check`, `docker-compose-build`. If any are missing, stop and escalate.

- [ ] **Step 3: Confirm README CI badge already points to ci.yml**

```bash
grep -n "actions/workflows/ci.yml/badge.svg" "D:/OneDrive/Developer/DataAnalytics/R_projects/bike_demand_prediction/README.md"
```

Expected: one matching line near line 19 inside the `## 🏷️ Project Badges` section. If absent, mark Task 3 as "Add the badge"; if present, mark Task 3 as "No change needed".

- [ ] **Step 4: Re-run the local test suite as a baseline**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
Rscript tests/testthat.R
```

Expected last line: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 62 ]` and exit code 0. If a test fails locally now, do not proceed — debug locally first before adding CI.

No commit. This task is verification only.

---

### Task 2: Append the `testthat` job to `ci.yml`

**Files:**
- Modify: `.github/workflows/ci.yml` (append at end of file)

- [ ] **Step 1: Open the file and confirm the last existing line**

The current file ends with the `docker-compose-build` job. The last meaningful line is:

```yaml
          cache-to: type=gha,mode=max                    # write all layers back to GHA cache after build
```

The new job is appended directly after this line.

- [ ] **Step 2: Append the `testthat` job block**

Append the following YAML to `.github/workflows/ci.yml`. Indentation must use exactly 2 spaces (matching the rest of the file). Do not add a trailing newline beyond a single blank one.

```yaml

  # ── Job 4: testthat unit suite ───────────────────────────────────────────────
  # Runs the 62-assertion testthat suite (20 model + 38 gbfs + 4 bigquery).
  # Mirrors the r-check renv restore pattern (unset RENV_CONFIG_REPOS_OVERRIDE,
  # manual options(repos=...)) and shares the same renv cache key so whichever
  # of {r-check, testthat} runs second pulls from a warm cache.
  # Copies data/processed/model.csv to shiny_app/model.csv before running tests
  # because shiny_app/model.csv is gitignored (Dockerfile.shiny copies it at
  # image build time; the CI run does the equivalent copy for the test job).
  testthat:
    name: R — testthat unit suite                         # label shown in the Actions UI
    runs-on: ubuntu-latest                                # GitHub-hosted Ubuntu 24.04 runner

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4                         # clone repo at current ref

      - name: Install system dependencies
        uses: awalsh128/cache-apt-pkgs-action@latest     # caches .deb files in GHA cache; dpkg-installs on hit
        with:
          packages: >-
            libcurl4-openssl-dev libssl-dev libxml2-dev
            libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev
            libpng-dev libtiff-dev libjpeg-dev
            libudunits2-dev libgdal-dev libgeos-dev libproj-dev cmake gdal-bin
            libx11-dev pandoc
          version: 1.0                                   # user-defined cache-bust key; matches r-check

      - name: Set up R 4.4.3
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.4.3"                             # pin to match renv.lock R version
          use-public-rspm: true                          # use Posit PPM for pre-built Ubuntu binaries

      - name: Cache renv packages
        uses: actions/cache@v4                           # standard GitHub cache action
        with:
          path: ~/.cache/R/renv                          # renv's global package cache directory
          key: ${{ runner.os }}-R-4.4.3-renv-3-${{ hashFiles('renv.lock') }}   # same key as r-check — shared cache
          restore-keys: ${{ runner.os }}-R-4.4.3-renv-3-                        # partial match for cache hit

      - name: Restore renv library
        shell: bash
        run: |
          # setup-r sets RENV_CONFIG_REPOS_OVERRIDE=PPM-only in the shell environment;
          # unset it here in bash before Rscript starts — renv reads this env var during
          # source('renv/activate.R'), so clearing it inside R (Sys.unsetenv) is too late.
          unset RENV_CONFIG_REPOS_OVERRIDE                                   # clear PPM-only flag before R starts
          Rscript -e "
          source('renv/activate.R')                                         # bootstrap renv from lockfile version
          options(repos = c(                                                 # dual-repo strategy:
            PPM  = 'https://packagemanager.posit.co/cran/__linux__/noble/latest',  # PPM first — fast Ubuntu binaries
            CRAN = 'https://cloud.r-project.org'                            # CRAN fallback — source for PPM gaps
          ))
          renv::restore()                                                    # restore all packages from renv.lock
          "

      - name: Copy model.csv into shiny_app/
        shell: bash
        run: |
          # shiny_app/model.csv is gitignored (Dockerfile.shiny COPYs it at image build time).
          # The testthat suite sources model_prediction.R which reads model.csv via the
          # relative path 'model.csv' from cwd=shiny_app/ — so we materialise it here.
          cp data/processed/model.csv shiny_app/model.csv  # bridge the gitignore for CI
          ls -la shiny_app/model.csv                       # verify copy succeeded

      - name: Run testthat suite
        shell: bash
        run: |
          # tests/testthat.R sets cwd to shiny_app/ via rprojroot and runs test_dir().
          # CI=true is auto-set by GitHub Actions → stop_on_failure=FALSE → all failures
          # reported in one run instead of fast-failing on the first.
          Rscript tests/testthat.R                         # full suite: 62 assertions expected
```

- [ ] **Step 3: Lint the YAML locally**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML parse OK')"
```

Expected output: `YAML parse OK` and exit code 0. If parsing fails, the indentation is wrong — re-check that every nested line is in multiples of 2 spaces, and that no tab characters slipped in.

- [ ] **Step 4: Confirm the file now has four jobs**

```bash
grep -n "^  [a-z][a-z-]*:$" "D:/OneDrive/Developer/DataAnalytics/R_projects/bike_demand_prediction/.github/workflows/ci.yml"
```

Expected: four lines — `python-check:`, `r-check:`, `docker-compose-build:`, `testthat:`. The colon at end of line and exactly 2-space indent narrow this to job declarations only.

- [ ] **Step 5: Stage the change but DO NOT commit yet**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
git add .github/workflows/ci.yml
git status
```

Expected `git status` output: exactly one file staged (`.github/workflows/ci.yml`), nothing else. If anything else is staged, unstage with `git reset HEAD <file>` and investigate.

---

### Task 3: Verify the README badge (likely no-op)

**Files:**
- Verify: `README.md` line 19

Task 1 Step 3 already determined whether the badge exists. This task acts on that finding.

- [ ] **Step 1: If the badge is already present, skip to Task 4**

Confirmed in Task 1 Step 3 that line 19 of `README.md` contains:
```markdown
[![CI](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml/badge.svg)](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml)
```
If this line is present, no README edit is needed — the badge aggregates all four jobs in the workflow. Skip to Task 4.

- [ ] **Step 2: If the badge is missing, add it**

Only run this step if Task 1 Step 3 showed no match. Edit `README.md`'s `## 🏷️ Project Badges` section: insert the line immediately after the section heading and before the existing R/Python/Shiny badges.

```markdown
## 🏷️ Project Badges

[![CI](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml/badge.svg)](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml)
![R](https://img.shields.io/badge/R-276DC3?style=for-the-badge&logo=r&logoColor=white)
```

Then:
```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
git add README.md
```

---

### Task 4: Commit, push, and verify CI passes

**Files:**
- Already staged: `.github/workflows/ci.yml` (and `README.md` if Task 3 Step 2 ran)

- [ ] **Step 1: Confirm what is staged**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
git diff --cached --stat
```

Expected: one file (`.github/workflows/ci.yml`) — and `README.md` only if Task 3 Step 2 ran.

- [ ] **Step 2: Commit with the canonical message from the parent plan**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
git commit -m @'
ci: add GitHub Actions testthat job to ci.yml

Fourth job runs the 62-assertion testthat suite (20 model + 38 gbfs +
4 bigquery) on every push and PR to main. Mirrors the r-check renv
restore pattern (unset RENV_CONFIG_REPOS_OVERRIDE, manual options(repos=...))
and shares the renv cache key for warm second-job runs. Copies
data/processed/model.csv to shiny_app/model.csv before tests because
the shiny_app/ path is gitignored (Dockerfile.shiny normally provides
this at image build time).
The existing README CI badge already aggregates all jobs in the workflow.
'@
```

Expected output: `[main <hash>] ci: add GitHub Actions testthat job to ci.yml` with `1 file changed` (or 2 if README was edited).

- [ ] **Step 3: Push to origin/main**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
git push origin main
```

Expected output: `<prev>..<new>  main -> main`.

- [ ] **Step 4: Watch the CI run**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
gh run watch --exit-status
```

If `gh` is not installed, open the URL printed by the push step or navigate to:
`https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions`

Expected: all four jobs report green. The `testthat` and `r-check` jobs share a renv cache key; whichever one finishes writing the cache first warms the other. On this specific commit both jobs start cold (lockfile-keyed cache may not yet exist for the current `renv.lock` hash), so the first run may take ≈5 min for the slower of the two. Subsequent runs at the same lockfile hash drop to ≈1 min. The spec budgets up to 5 min for cold cache.

- [ ] **Step 5: Inspect the testthat job log for the assertion count**

```powershell
Set-Location "D:\OneDrive\Developer\DataAnalytics\R_projects\bike_demand_prediction"
gh run view --log --job testthat | Select-String "PASS"
```

Expected line: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 62 ]` somewhere in the log.

- [ ] **Step 6: Confirm the README CI badge renders green**

Open `https://github.com/deepan-mehta-analytics/bike-demand-prediction` in a browser and visually confirm the CI badge is green. The badge auto-updates within ~30 s of the workflow completing.

---

## Failure Mode Recovery

If any of the four CI jobs fail on the first run, do not delete or revert the testthat job. Diagnose first:

| Failure symptom | Most likely cause | Fix |
|----------------|-------------------|-----|
| `testthat` job — `Failed to load: rprojroot` | renv cache hit but `rprojroot` was not in `renv.lock` when cache was written | run `renv::install('rprojroot')` + `renv::snapshot()` locally, push, retry |
| `testthat` job — `cannot open file 'model_prediction.R'` | Working-directory step skipped or `tests/testthat.R` did not run rprojroot::find_root | confirm `tests/testthat.R` is unchanged from commit `cce5be9`; rerun the workflow |
| `testthat` job — `cannot open file 'model.csv'` | `cp` step failed silently; `shiny_app/model.csv` not created | add `set -e` to the bash block and rerun; or list `shiny_app/` directory in a separate verify step |
| `testthat` job — `FAIL > 0` | A real test regression that does not occur locally — most likely a libcurl / SSL version skew | reproduce in a Docker container matching `ubuntu-latest` rather than ad-hoc fixes |
| `r-check` job — newly red after this PR | The shared cache key collided with a stale apt cache | bump `version: 1.0` → `version: 1.1` in BOTH `r-check` and `testthat` jobs |
| `python-check` or `docker-compose-build` — newly red | Should not be possible; this PR does not touch their inputs. Revert the testthat append and re-investigate. |

---

## Acceptance criteria (from spec)

1. `ci.yml` contains four jobs: `python-check`, `r-check`, `docker-compose-build`, `testthat`.
2. The `testthat` job passes on its first GitHub Actions run after merge to `main`.
3. The full suite reports `FAIL 0 | WARN 0 | SKIP 0 | PASS 62` in the job log.
4. The README CI badge renders green on the public repo page.
5. The existing three jobs continue to pass with no regressions.

Implementer: confirm all five before considering Task 5 complete.
