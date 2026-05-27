# Sprint 3 — Honest Claims + Carry-over B3 — Design Spec

**Date:** 2026-05-27
**Author:** Deepan Mehta
**Scope:** `bike-demand-prediction` (Shiny repo) only — no ML-repo changes
**Parent spec:** [`2026-05-24-dashboard-truth-and-freshness-design.md`](./2026-05-24-dashboard-truth-and-freshness-design.md) §6 Workstream C and §5 Workstream B item B3
**Sprint sequence:** Sprint 3 of 3 in the parent spec's ship-in-tracks plan; closes out the v1.6.0 "Dashboard Honesty Pass" release

---

## 1. Why this sprint exists (delta from parent spec)

The parent spec defined Workstream C (items C1–C6) as the third sprint. During Sprint 2 audit on 2026-05-27, **Workstream B item B3 was discovered to be unshipped** — Sprint 2's six commits (`ea687f0`, `967c465`, `e8f4ddc`, `faef978`, `b0950c7`, `28a94dc`) landed B1 (hourly reactive timer), B2 (diurnal sinusoid in demo fallback), and B4 (reactive forecast_window), but **not** B3 (per-chart and footer `data_source` honesty). Only the map-popup labels (`"[Demo data — weather API key not set]"`) carry the demo-vs-live signal today; chart subtitles and the page footer still claim OpenWeather unconditionally.

Sprint 3 absorbs B3 because it shares the "honest claims" intent of Workstream C and naturally pairs with C1 (engine indicator) — both touch chart subtitles.

**Sprint 3 scope: 7 items total** — B3 + C1 + C2 + C3 + C4 + C5 + C6.

---

## 2. Design knobs locked

For each item, the parent spec stated *what*; this section locks the *how* (percentages, wording, code placement) so writing-plans can be mechanical.

### B3 — data_source column + reactive footer + chart subtitle source line

**Data layer (`shiny_app/model_prediction.R`):**

- Add column `data_source` (character) to the output of both `generate_city_weather_bike_data()` and `generate_demo_weather_data()`.
- Values: `"openweather_live"` and `"demo_fallback"`.
- **Per-row granularity** (one column value per city × slot) — preserves correctness when one city's API call fails over to demo while others stay live. Trade-off: 48 redundant character cells per refresh, negligible memory cost.

**Chart subtitles (`build_temp_chart`, `build_bike_chart` in `shiny_app/server.R:517-555`):**

- Derive `src <- unique(df$data_source)[1]` at function start (single-city dfs are uniform on this column).
- Append a second subtitle line after the existing `"Next 24 Hours • {fmt_start} → {fmt_end}"` line:
  - Live → `Source: OpenWeather, refreshed HH:MM UTC` (HH:MM formatted from `Sys.time()` at chart-build moment, UTC tz)
  - Demo → `Source: Demo fallback — set OPENWEATHER_KEY in .Renviron and restart`

**Page footer (`shiny_app/ui.R:388-390`):**

- Replace static `"Powered by OpenWeather API"` with `uiOutput("data_source_footer")`.
- Server logic counts live vs demo cities across the current `city_weather_bike_df()`:
  - All cities live → `Powered by OpenWeather API`
  - Mixed → `Powered by OpenWeather API — N of M cities on demo fallback` (M = total cities in the frame, not hardcoded 6)
  - All cities demo → `Demo data — OPENWEATHER_KEY not set; live forecasts disabled`

### C1 — Engine indicator on bike demand chart

- In `build_bike_chart`, read `Sys.getenv("USE_FASTAPI", unset = "false")` once at function start.
- Append a third subtitle line (after B3's Source line):
  - `Engine: FastAPI Random Forest` (USE_FASTAPI = `"true"`)
  - `Engine: Local linear regression` (any other value)
- **No RMSE quoted in UI** — RMSE lives in README/PROJECT-STATUS; quoting in real-time UI would drift as models retrain.

### C2 — Humidity chart smoother

- In the humidity-vs-demand chart code (server.R), replace `geom_smooth(method = "lm", formula = y ~ poly(x, 4))` with `geom_smooth(method = "lm")` (default linear formula).
- Update humidity chart subtitle: `"24-Hour forecast window"` → `"Linear trend across 8 forecast slots"`.

### C3 — Derive stat-card counts

- `shiny_app/ui.R:337-342`:
  - Replace literal `"6"` with `textOutput("stat_cities", inline = TRUE)`
  - Replace literal `"24"` with `textOutput("stat_hours", inline = TRUE)`
- Server:
  - `output$stat_cities <- renderText({ length(unique(city_weather_bike_df()$CITY_ASCII)) })`
  - `output$stat_hours <- renderText("24")` — kept as constant; inline comment documents that 24 is the OpenWeather forecast horizon (8 slots × 3 hours), not data-driven.

### C4 — Per-city quantile thresholds

- Replace `calculate_bike_prediction_level()` body with quantile-based logic:
  ```r
  calculate_bike_prediction_level <- function(predictions) {
    q33 <- quantile(predictions, 0.33, na.rm = TRUE)
    q67 <- quantile(predictions, 0.67, na.rm = TRUE)
    case_when(
      predictions <= q33 ~ "small",
      predictions <= q67 ~ "medium",
      TRUE               ~ "large"
    )
  }
  ```
- Apply inside `group_by(CITY_ASCII) %>% mutate(...)` in **both** `generate_city_weather_bike_data()` and `generate_demo_weather_data()`.
- **Tertile split locked at 0.33/0.67** — produces clean 3/2/3 distribution across 8 linearly-increasing forecast slots (R's default type=7 quantile gives q33≈3.31, q67≈5.69 over 1..8 → small={1,2,3}, medium={4,5}, large={6,7,8}). Alternatives rejected: 0.25/0.75 leaves only 2 slots in "medium" with skewed extremes; 0.2/0.5/0.8 yields 4 levels and doesn't match existing 3-level legend infrastructure.
- Legend wording update (`shiny_app/ui.R`): `"Low / Medium / High — relative to this city's 24h forecast range"`.

### C5 — Operator alert rewrite

- Replace the current `peak_24h_demand` vs `current_total_bikes` ratio (unit-mismatched) with zero-bike-station percentage:
  - **Red (Critical):** `≥ 25% of stations have zero bikes`
  - **Amber (Warning):** `≥ 10% of stations have zero bikes` **OR** fleet fill rate `< 20%`
  - **Green (Healthy):** otherwise
- Three thresholds extracted to named constants at top of `shiny_app/server.R` for easy tuning after lived observation:
  ```r
  OP_ALERT_RED_ZERO_PCT    <- 0.25
  OP_ALERT_AMBER_ZERO_PCT  <- 0.10
  OP_ALERT_AMBER_FILL_PCT  <- 0.20
  ```
- Forecast peak shown in the panel body as context, **not** driving alert level:
  - Body line: `"24h peak demand forecast: X bikes — for capacity planning context"`.

### C6 — CSV download metadata + filename

- `download_forecast` handler prepends 4 `#`-commented header rows:
  ```
  # Bike Demand 24h Forecast — exported YYYY-MM-DD HH:MM UTC
  # City: <city_name>
  # Source: <openweather_live | demo_fallback>
  # Forecast horizon: <start> -> <end>
  ```
- Filename pattern: `bike-demand-forecast-<city-slug>-<YYYYMMDD-HHMM>.csv` (UTC stamp).
- City slug = lowercased + spaces→dashes (e.g., `"New York"` → `"new-york"`, `"Washington DC"` → `"washington-dc"`).

---

## 3. Files touched

| File | Items | Net change |
|---|---|---|
| `shiny_app/model_prediction.R` | B3 (data_source col), C4 (quantile + group_by) | ~30 LOC |
| `shiny_app/server.R` | B3 (subtitle, footer reactive), C1 (engine subtitle), C2 (smoother + subtitle), C3 (stat outputs), C5 (alert rewrite + constants), C6 (download header + filename) | ~120 LOC |
| `shiny_app/ui.R` | B3 (footer uiOutput), C3 (textOutput placeholders), C4 (legend wording) | ~10 LOC |
| `tests/testthat/test-model-prediction.R` | B3 column, C4 quantile distribution | ~30 LOC |
| `tests/testthat/test-data-source-footer.R` (new) | B3 footer text logic | ~50 LOC |
| `tests/testthat/test-build-bike-chart.R` (new) | C1 engine indicator subtitle | ~40 LOC |
| `tests/testthat/test-stat-card.R` (new) | C3 derived counts | ~25 LOC |
| `tests/testthat/test-operator-alert.R` (new) | C5 threshold logic | ~60 LOC |
| `tests/testthat/test-download-handler.R` (new) | C6 CSV header + filename | ~40 LOC |

**Test count delta:** 37 tests / 63 assertions → projected **~47-50 tests / ~80 assertions**.

---

## 4. Packaging — TDD per item, 7 + 1 commits

User chose Approach 1 (TDD-per-item, 7 commits) over grouped-by-file or single-bundled approaches. Reasoning: best traceability, easiest revert per item, matches Sprint 1 cadence, avoids the Sprint 2 miss-pattern (4 sub-tasks in one commit → 1 missed).

**Commit order (risk- and dependency-ordered):**

| # | Commit | Subject | Rationale for ordering |
|---|---|---|---|
| 1 | feat | `feat(model_prediction): add data_source column + reactive footer (Sprint 3 B3)` | Foundation; C6 consumes `data_source` for CSV header |
| 2 | feat | `feat(model_prediction): per-city quantile thresholds for demand levels (Sprint 3 C4)` | Touches same generators as commit 1 — minimizes file churn |
| 3 | fix | `fix(server): rewrite operator alert to zero-bike-station thresholds (Sprint 3 C5)` | 🔴 Critical item; isolated to server.R; high priority |
| 4 | feat | `feat(server): engine indicator on bike demand chart (Sprint 3 C1)` | Builds on B3's subtitle structure |
| 5 | refactor | `refactor(server): replace humidity poly(4) smoother with linear (Sprint 3 C2)` | Isolated cosmetic |
| 6 | refactor | `refactor(ui): derive stat-card city/forecast counts (Sprint 3 C3)` | Trivial; ui.R + 2 server outputs |
| 7 | feat | `feat(server): timestamped CSV export with source metadata (Sprint 3 C6)` | Last because consumes data_source from commit 1 |
| 8 | docs | `docs(sprint3): close v1.6.0 Dashboard Honesty Pass — Pattern A-D sweep` | Doc sync + release framing |

**Per-commit TDD cycle:**
1. Write failing testthat block(s) for the item
2. Run testthat suite — confirm RED
3. Implement the change
4. Run testthat suite — confirm GREEN
5. Manual smoke check if relevant (e.g., subtitle text in browser)
6. Commit

---

## 5. Testing approach

| Item | Test | Notes |
|---|---|---|
| B3 (data layer) | `data_source` column exists with value `"openweather_live"` in `generate_city_weather_bike_data()` output and `"demo_fallback"` in `generate_demo_weather_data()` output | Pure-function test, no mocking needed for demo path |
| B3 (footer logic) | Footer renderer returns expected text given synthetic df with all live / mixed / all demo | Test the helper function that computes the text; renderUI itself is integration-tested manually |
| C1 | `build_bike_chart` ggplot object's `labels$subtitle` includes `"FastAPI Random Forest"` when `USE_FASTAPI=true` (withr::with_envvar), `"Local linear regression"` otherwise | Tests the env-var branch via `withr` |
| C2 | (skipped — visual change; geom_smooth method change isn't usefully unit-testable) | Manual eyeball only |
| C3 | `length(unique(df$CITY_ASCII))` returns expected value for synthetic df | Trivial; covers the renderText body |
| C4 | Given synthetic 8-slot df with linearly-increasing predictions for one city: tertile split returns 3 "small" + 2 "medium" + 3 "large" (q33≈3.31, q67≈5.69 on 1..8); levels are monotonically non-decreasing as predictions increase | Edge case: all-equal predictions return all-"small" (degenerate quantile, all values ≤ q33) — test this too |
| C5 | Given synthetic stations df: returns "red" at 25% zero, "amber" at 10% zero, "amber" at 19% fill rate, "green" at 30% fill + 5% zero; boundary conditions tested (24%, 9%, 20%, 21%) | Pure function test on the threshold helper |
| C6 | Given mock forecast df: CSV bytes start with the 4 `#`-prefixed header rows; filename slug matches expected pattern for "New York" and "Washington DC" | Tests the helper that builds CSV string + filename; `download_forecast` itself is Shiny-integration territory |

**Manual smoke test (post-commit-7, pre-commit-8):**

1. **Live path:** Restart Shiny with valid `OPENWEATHER_KEY`. Confirm: temp/bike chart subtitles end with `"Source: OpenWeather, refreshed HH:MM UTC"`; footer reads `"Powered by OpenWeather API"`; bike chart subtitle includes engine line.
2. **Demo path:** Rename `.Renviron` to break the key. Restart. Confirm: chart subtitles end with `"Source: Demo fallback — set OPENWEATHER_KEY..."`; footer reads `"Demo data — OPENWEATHER_KEY not set..."`; map popups still show `"[Demo data — weather API key not set]"` (pre-existing).
3. **Toggle USE_FASTAPI:** Restart with `USE_FASTAPI=true` then `USE_FASTAPI=false`. Confirm bike chart subtitle engine line flips.
4. **Per-city thresholds:** Eyeball Live Map for all 6 cities — colour distribution should now vary within each city (each city has its own 1/1/1 colour split across the 24h horizon, not always-red or always-green).
5. **Operator alert:** Eyeball Operator tab for all 6 cities — alert level should reflect actual fleet state, not the broken ratio. Should not be uniformly red.
6. **CSV download:** Download from Operator tab. Open in text editor. Confirm 4 header rows + correct filename slug + UTC stamp.

---

## 6. Doc sync (commit 8)

**README.md:**
- Phase 7D (Operator alert) retrospective updated: note alert rewrite, threshold constants, configurable post-observation.
- Phase 7E (CSV download) retrospective updated: note metadata header + timestamped filename.
- Quick Summary feature bullets: add "Per-city demand thresholds", "Engine indicator", "Honest data-source labelling end-to-end".
- Known Limitations: **remove** "operator alert is unit-mismatched ratio" (fixed by C5), **remove** "hardcoded city/forecast counts" (fixed by C3).

**PROJECT-STATUS.md:**
- Priority table Sprint 3 row strikethrough with completion date and commit range.
- Ecosystem own-hash bump.
- New feature lines under v1.6.0 entry.
- Workstream B+C marked ✅ Done.

**Companion ML repo:** No sync needed (Sprint 3 is Shiny-only; no ML behaviour changes).

**Pattern A-D sweep:** Mandatory before commit 8 per CLAUDE.md Rule 12.

---

## 7. v1.6.0 release framing

Sprint 3's ship completes the parent spec's Dashboard Honesty Pass. After commit 8:

- Tag `v1.6.0` on `bike-demand-prediction` `main`.
- Release notes follow Rule 11 canonical format:
  - Title: `v1.6.0 — Dashboard Honesty Pass`
  - What's included: tables covering Sprints 1 (GCP Stream poller, ML-side dependency), 2 (forecast freshness + diurnal demo), 3 (honest claims + meaningful comparisons).
  - Roadmap: `v1.7` placeholder (Manual Refresh button + shinytest2 reactive harness, per parent spec §9 out-of-scope items)
- `gh release create v1.6.0 --latest=legacy` (preferred default per Rule 11).
- ML repo's v3.1.0 (shipped during Sprint 1) stays unchanged.

---

## 8. Risks (delta from parent spec §8)

| Risk | Mitigation |
|---|---|
| `data_source` column added but missed in one generator function path → footer logic crashes on NA | testthat asserts column presence in both live and demo paths; renderer has `if (!"data_source" %in% colnames(df)) return("...")` defensive branch |
| Operator alert thresholds (25%/10%/20%) too tight or too loose in real GBFS data | Constants at top of server.R — easy single-line tune after a week of observation. Acceptable to ship at spec defaults; calibrate later. |
| Per-city quantile thresholds produce identical labels when all 8 slots are equal (degenerate quantile) | `case_when` with strict inequalities → all-equal collapses to all-"small". Tested explicitly. Acceptable degenerate behaviour; comment in code. |
| C1 reads `Sys.getenv("USE_FASTAPI")` once at function-scope → won't update mid-session if env var changes | Acceptable; env vars are set at session start. If user wants mid-session toggle, that's a future feature (not in scope). |
| Sprint 3's 7 commits each trigger CI — costs 7 × ~1m45s of GitHub Actions time | Within free tier headroom (2000 min/month). Trade-off accepted for per-commit traceability. |

---

## 9. Out of scope (carried from parent spec §9)

- Manual "Refresh Now" button on Live Map (defer to v1.7)
- shinytest2 reactive harness (Phase 8 backlog)
- New tabs or dashboard surfaces
- README rewrite for recruiter narrative (separate sprint, post v1.6.0)
- Recalibrating operator alert thresholds from observed data (do after one week of live observation)

---

## 10. Definition of done

1. All 7 items shipped via commits 1-7; testthat green at ~47-50 tests / ~80 assertions.
2. Manual smoke test (§5) passes across all 4 tabs and both live/demo paths.
3. Doc sync commit 8 lands with Pattern A-D sweep clean.
4. `v1.6.0` GitHub release published with canonical format and `--latest=legacy` flag.
5. PROJECT-STATUS.md ecosystem snapshot row reconciled to HEAD per cross-repo-sync-mandatory-closeout protocol (own-hash reconciliation, no cross-repo sync needed this sprint).

When `git log v1.6.0 --oneline` shows the 8 Sprint-3 commits on top of Sprint 2's tail, this spec is fulfilled and the parent spec's "Dashboard Honesty Pass" is complete.

---

## 11. References

- Parent spec: `docs/superpowers/specs/2026-05-24-dashboard-truth-and-freshness-design.md`
- Sprint 2 commits (B1, B2, B4 — B3 carry-over): `ea687f0`, `967c465`, `e8f4ddc`, `faef978`
- Cross-repo sync protocol: `[[feedback_cross_repo_sync_mandatory_closeout]]` memory
- GCP free-tier rules: `CLAUDE.md` Rule 12 (Sprint 3 has no GCP impact, no audit needed)
- Release format: `CLAUDE.md` Rule 11
- Commit message style: `~/.claude/skills/commit-style/SKILL.md`
