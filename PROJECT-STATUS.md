# Project Status — Bike Demand Prediction (R Shiny Dashboard)

> Re-entry command: `"resume bike demand prediction project"`
> Companion repo: `D:\OneDrive\Developer\Data Engineering\bike-demand-ml-system`

---

## 🌐 Ecosystem Snapshot

Both repos form a single portfolio system. Track them together here.

| Repo | Role | Current Phase | Status | Last Commit |
|------|------|--------------|--------|-------------|
| **bike_demand_prediction** (this repo) | R Shiny dashboard | v1.5.0 shipped — testthat suite + CI; v1.6.0 Sprint 1 (Workstream A) complete — GCP Stream tab now live via Cloud Run poller | ✅ Done | `feacd35` |
| **bike-demand-ml-system** | Python FastAPI + ML training | **v3.1.0 shipped (2026-05-25)** — `gbfs-poller` Cloud Run + `gbfs-poller-cron` Scheduler + BQ 7-day partitions, replacing the v3.0.0 Dataflow path at zero always-free-tier cost (joint cross-repo work tracked as Shiny v1.6.0 Sprint 1). v4.3.0 was Paris tz fix; v4.4.0 drift monitoring in design | ✅ Done | `7625f17` |

### Trained City Models (Python repo)

All RMSEs use a **chronological 80/20 split** (oldest 80% → train, newest 20% → test), matching `train.py` exactly.

| City | RMSE (bikes/hr) | Top Feature | Dashboard Cities | API Artifact |
|------|-----------------|-------------|-----------------|--------------|
| Seoul | **1,503.52** | HOUR (0.468) | Seoul | `artifacts/seoul/` |
| London | **316.56** | HOUR (0.71) | London | `artifacts/london/` |
| NYC | **470.76** | HOUR (0.52) | New York | `artifacts/nyc/` |
| Washington DC | **119.31** | HOUR (0.62) | Washington DC | `artifacts/dc/` ✅ |
| Paris | **20.51** | HOUR (0.708) | Paris | `artifacts/paris/` ✅ |
| Chicago | **202.99** | HOUR + TEMPERATURE (0.39 each) | Chicago | `artifacts/chicago/` ✅ |

### Next Milestones (Both Repos) — Priority Ordered

| Priority | Repo | Phase | Target Version | Dependency |
|----------|------|-------|---------------|------------|
| ~~1~~ | bike-demand-ml-system | ~~Phase 6 — Observability~~ | ~~v2.1.0~~ | **✅ Shipped** |
| ~~1~~ | bike-demand-ml-system | ~~Phase 4 — Pub/Sub + Dataflow~~ | ~~v3.0.0~~ | **✅ Shipped** |
| ~~1~~ | bike_demand_prediction | ~~Phase 7F — GCP Streaming Dashboard~~ | ~~v1.2.0~~ | **✅ Shipped** |
| ~~2~~ | bike-demand-ml-system | ~~Phase 5 — Vertex AI + MLflow~~ | ~~v4.0.0~~ | **✅ Shipped (2026-05-17)** |
| ~~3~~ | bike_demand_prediction | ~~Feed Health Alerting — sidebar GBFS status panel~~ | ~~v1.3.0~~ | **✅ Shipped (2026-05-17)** |
| ~~4~~ | bike_demand_prediction | ~~Backlog — Paris/Chicago models~~ | ~~v1.4.0~~ | **✅ Shipped (2026-05-18)** |
| ~~5~~ | bike_demand_prediction | ~~Backlog — testthat suite + CI~~ | ~~v1.5.0~~ | **✅ Shipped (2026-05-19)** |
| ~~5.5~~ | bike-demand-ml-system | ~~Seoul training data refresh (OA-15182 + Open-Meteo)~~ | ~~v4.2.0~~ | **✅ Shipped (2026-05-21)** |
| ~~5.6~~ | bike-demand-ml-system | ~~Paris timezone fix + Option B 2022 drop + cross-city table alignment~~ | ~~v4.3.0~~ | **✅ Shipped (2026-05-21)** |
| ~~6~~ | bike-demand-ml-system | ~~4-city analogous timezone bug fix (Paris/Chicago/NYC/DC)~~ | ~~v4.3.0~~ | **✅ Scope shrunk to Paris-only after code inspection (NYC/DC/Chicago parse datetimes naively); shipped as Paris-only in v4.3.0** |
| ~~7~~ | bike_demand_prediction | ~~Backlog — Seoul GBFS~~ | — | **✅ Integration shipped 2026-05-17 (commit `8682242`) on `sample` key; full-coverage upgrade demoted 2026-05-23 to runtime `.Renviron` config — see Shiny README "Optional — Seoul full-coverage upgrade"** |
| ~~8.0~~ | bike-demand-ml-system + bike_demand_prediction | ~~Sprint 1 — Cloud Run poller + BQ partitioning~~ | ~~v3.1.0 (ML) / v1.6.0 Sprint 1 (Shiny)~~ | **✅ Shipped 2026-05-25 — `gbfs-poller` Cloud Run + `gbfs-poller-cron` Scheduler live; BQ DAY-partitioned (7-day TTL); 6,032 rows confirmed across 4 cities in first cron window. ML release tag `v3.1.0`; Shiny tracks the same work as Sprint 1 of its v1.6.0 dashboard-truth-and-freshness ship.** |
| **8** | bike_demand_prediction | Backlog — City expansion (SF/Amsterdam) | — | Data sourcing required |

---

## ✅ Completed

### v1.0.0 — Released 2026-05-08 (GitHub release published)
* Seoul Bike Sharing data pipeline: ingestion → SQL EDA → six model benchmarks
* Best model: Random Forest R²=0.730, RMSE=333.89 bikes/hr (R pipeline)
* Shiny dashboard: OpenWeather 5-day forecast → 24-hr demand for 6 global cities
* Leaflet interactive map with colour-coded demand markers; 3-tab UI (Live Map, Operator UC1, Rider UC2)
* GBFS live station data: Capital Bikeshare v2 (DC), standard GBFS v2 (NYC/Paris/Chicago), TfL BikePoint (London)
* FastAPI integration: `httr::POST` to Python RF endpoint; per-city routing via `group_modify()`
* IBM Capstone graded tracks (R + Python notebooks)
* `renv.lock` — R 4.4.3, 139 packages pinned
* `Dockerfile.shiny` — `rocker/shiny:4.4.3`; renv restore via Posit PPM binaries
* CI: r-check + docker-compose-build with GHA apt + Docker layer caching
* MIT LICENSE + full GitHub release notes published
* Companion release: bike-demand-ml-system `v1.0.0` published same date

### v1.1 — Phases 7A–7H Complete

#### Phase 7A — City Replacement
* Replaced Suzhou (no GBFS) with Chicago (Divvy GBFS v2)
* `config/cities.yaml` — GBFS URLs, BigQuery datasets, timezones for all 5 cities
* `config/gcp_config.yaml` — Pub/Sub topic, BigQuery dataset, local-mode paths

#### Phase 7B — Live Station Data
* `shiny_app/gbfs_client.R` — GBFS v2 (NYC, Paris, Chicago) + TfL BikePoint (London)
* City drill-down map: station markers coloured by available bike count (green/yellow/red)
* Graceful fallback — GBFS failure never crashes the app

#### Phase 7C — FastAPI Integration
* `shiny_app/model_prediction.R`: `predict_bike_demand_fastapi()` via `httr::POST`
* `USE_FASTAPI=true` → Python RF (RMSE 173 bikes/hr); `false` → local model.csv (RMSE 334)
* `docker-compose.yml` — Shiny + FastAPI as co-located services

#### Phase 7C Fix — Per-City Routing (2026-05-07, commit dc9404b)
* Added `city` arg to `predict_bike_demand_fastapi()` — FastAPI now receives correct city
* Switched `generate_city_weather_bike_data()` from flat `mutate()` to `group_by(CITY_ASCII) %>% group_modify()` — one API call per city, each routed to its own RF artifact
* Previously: all 5 cities silently used Seoul model; now Seoul/London/NYC use city-specific models

#### Phase 7D — UC1 Operator Tab
* Fleet rebalancing alerts: predicted demand vs. available station bikes
* Demand heatmap layer on Leaflet map
* CSV export of 24-hr forecast for operations teams

#### Phase 7E — UC2 Rider Tab
* Demand score (Low / Medium / High) for next 3 hours at selected city
* "Best time to ride today" hour recommendation
* Natural-language availability summary

#### Phase 7G — Documentation
* README architecture diagram updated with full v1.1 stack
* Tech Stack and Roadmap updated; roadmap items ticked

#### Phase 7H — Containerisation & CI
* `Dockerfile.shiny` — `rocker/shiny:4.4.3`, renv restore via PPM, EXPOSE 3838
* `docker-compose.yml` — Shiny + FastAPI co-located (requires sibling Python repo)
* CI: `docker-compose-build` job + apt/Docker layer caching for fast runs

### v1.2.0 — Released 2026-05-16 (Phase 7F — GCP Streaming Dashboard)
* `shiny_app/bigquery_client.R` — BQ auth (service account via `GOOGLE_APPLICATION_CREDENTIALS`), `query_city_trend()` (2h rolling avg/min/max windowed by 5-min buckets), `query_latest_snapshot()` (newest window per city via ROW_NUMBER)
* `shiny_app/server.R` — BQ_AVAILABLE flag on startup; `reactiveTimer(300000)` for 5-min auto-refresh; manual refresh button; `bq_status_panel`, `bq_city_stats`, `bq_stream_chart` (ggplot2 ribbon + avg line)
* `shiny_app/ui.R` — 4th "GCP Stream" tab (glyphicon-signal) with city selector, status panel, status cards, and centre chart
* `renv.lock` — bigrquery 1.6.2 + 22 dependency packages added via `renv::record()` (182 total)
* Graceful degradation — GCP Stream tab shows 3-step setup instructions when `GOOGLE_APPLICATION_CREDENTIALS` is not set; never crashes the app

### v1.3.0 — Released 2026-05-17 (Feed Health Alerting Sprint — 11 tasks, commits 73822a2 → 1a7ed0d)
* `shiny_app/gbfs_client.R` — `get_city_live_stations()` enriched return: `list(df, row_count, error_msg)` — callers get structured metadata without re-querying
* `shiny_app/server.R` — `build_feed_status_text()` (LIVE/DELAYED/DOWN + minutes-ago age) + `update_feed_state()` (per-city failure counting; amber after 1-2, red after 3+) helper functions
* `shiny_app/server.R` — `reactiveTimer(300000)` auto-refresh; `feed_state` reactiveValues per city; `live_stations_df` reactiveVal (replaces startup-only static fetch)
* `shiny_app/server.R` — `output$feed_health_panel` renderUI: Bootstrap colour-coded panel per city (panel-success LIVE / panel-warning DELAYED / panel-danger DOWN)
* `shiny_app/server.R` — 3 shared chart reactives (`temp_chart_obj`, `bike_chart_obj`, `humidity_chart_obj`); modal expand titles now reactive to city dropdown
* `shiny_app/ui.R` — `dash-left` overflow scroll; chart-header ellipsis; `uiOutput("feed_health_panel")` wired in sidebar
* Bug fixes: `isolate()` on `feed_state` reads in `update_feed_state()` (prevented reactive self-invalidation loop); `tryCatch` + `generate_demo_weather_data()` fallback (prevented server crash when `OPENWEATHER_KEY` not set); `overflow:hidden` moved to inner div (fixed flex item height-collapse in column-flex container)
* Browser-verified: Seoul LIVE/5 demo stations, London LIVE/799, NYC LIVE/2406, Paris DELAYED/amber (DNS), Chicago LIVE/2000, DC LIVE/831; modal title reacts to city dropdown ✓

---

## ⚠️ Known Limitations

* Paris RMSE (20.51 post-v4.3.0; was 23.30 pre-tz-fix) reflects counter MEAN normalisation (~50–500/hr scale), not raw station volume — correct relative to training data; 2022 source export dropped as a data-quality gate in v4.3.0 (intrinsic provider-side aggregation anomaly; reversible)
* Reactive logic in `server.R` and `ui.R` not yet covered — would require `shinytest2` browser harness (out of scope for v1.5; candidate for a future phase)
* Seoul live-station coverage is sample-key-only by default — `parse_seoul_openapi()` ships and runs on the public `"sample"` key (5 real stations near Mapo-gu); full ~1,471-station coverage unlocks via `SEOUL_API_KEY` runtime config (see Shiny README "Optional — Seoul full-coverage upgrade")
* `USE_FASTAPI` is env-var controlled — no in-app toggle (by design for Docker simplicity)
* GCP Stream tab requires `GOOGLE_APPLICATION_CREDENTIALS` env var pointing to a GCP service account JSON for local development — tab shows 3-step setup instructions when credential is not set. Production pipeline runs live via Cloud Run + Cloud Scheduler (v1.6.0 Sprint 1, shipped 2026-05-25)

---

## 🔜 Roadmap

### Phase 7F — GCP Streaming Dashboard ✅ DONE (v1.2.0 — 2026-05-16; pipeline reactivated v1.6.0 Sprint 1 — 2026-05-25)
* `shiny_app/bigquery_client.R` — `bq_auth_safe()`, `query_city_trend()`, `query_latest_snapshot()`
* 4th "GCP Stream" tab in Shiny — live 5-min windowed avg/min/max bikes per city, auto-refresh every 5 min
* bigrquery 1.6.2 + 22 deps added to `renv.lock` via `renv::record()`
* Commits `9b1fd47` (code) + `1764b19` (renv.lock) pushed to origin/main
* **v1.6.0 Sprint 1 pipeline reactivation (2026-05-25):** Dataflow path superseded by `gbfs-poller` FastAPI Cloud Run service + `gbfs-poller-cron` Cloud Scheduler (5-min cron, OIDC auth); BQ table recreated with DAY partitioning and 7-day TTL; 6,032 rows confirmed across all 4 cities in first automated window

### ✅ Backlog — Paris/Chicago models (v1.4.0) — SHIPPED 2026-05-18
* Paris RF — Vélib' Métropole open data (2023–2024, 17,539 rows; 2022 dropped in v4.3.0 as a data-quality gate); RMSE 20.51; `artifacts/paris/`
* Chicago RF — Divvy quarterly CSVs (2019–2022, 32,720 rows); RMSE 202.99; `artifacts/chicago/`
* Seoul fallback proxy removed for both cities

### v1.5.0 — testthat suite + CI (shipped 2026-05-19)
* 36-test / 62-assertion testthat suite: `test-model-prediction.R` (20 assertions), `test-gbfs-client.R` (38), `test-bigquery-client.R` (4)
* HTTP layer fully stubbed via `mockery::stub()` — no network, no cassettes
* GitHub Actions `testthat` job (4th job in `ci.yml`) — mirrors `r-check`'s renv-restore pattern, shares its renv cache key
* Cold-cache run: ~5 min; warm-cache run: ~1 min (62 assertions in ~2 s once renv is restored)

### ~~Backlog — Priority 7: Seoul GBFS~~ — DEMOTED 2026-05-23
* Integration shipped in commit `8682242` (2026-05-17); `parse_seoul_openapi()` runs on Seoul Open API's public `"sample"` key returning 5 real stations near Mapo-gu (verified locally)
* Full ~1,471-station coverage is a `.Renviron` change (`SEOUL_API_KEY=<registered_key>`) — not a code release; documented in Shiny README under "Optional — Seoul full-coverage upgrade"
* ML repo's Seoul training data (OA-15182, Python `v4.2.0`) came from the same `data.seoul.go.kr` platform as a public dataset download — no auth ever needed; the personal key is only for the live-station endpoint
* No longer a backlog item — tracked as an optional runtime config

### Backlog — Priority 8: City expansion
* Expand to 8 cities — San Francisco (Ford GoBike) or Amsterdam (OV-fiets)
* Requires data sourcing and model training in Python repo

---

## 🚀 Next Step

**v1.5.0 shipped (2026-05-19) — testthat suite + CI.** Three test files (62 assertions across 36 `test_that` blocks), HTTP-mocked via `mockery`, enforced by a fourth GitHub Actions CI job that mirrors `r-check`'s renv pattern. All five acceptance criteria in the parent spec verified.

- Task 1 (`717bfd2`): `testthat` + `mockery` in renv.lock; `tests/testthat.R` entrypoint
- Task 2 (`401062a`): `tests/testthat/test-model-prediction.R` (16 test_that / 20 assertions)
- Task 3 (`7189030`): `tests/testthat/test-gbfs-client.R` (16 test_that / 38 assertions); helper-workdir.R; rprojroot setwd pattern; `pmax 0→0L` fix in model_prediction.R
- Task 4 (`cce5be9`): `tests/testthat/test-bigquery-client.R` (4 test_that / 4 assertions)
- Task 5 (`edd97e3`): `testthat` job appended to `ci.yml`; CI run 26079707740 green on all 4 jobs

*Latest v1.5 ship commit `9da4a6d` — docs(readme): polish staleness after v1.5 testthat ship (2026-05-19). Earlier same-day: `edd97e3` (testthat CI job), `c712d67` (CI refactor — R_VERSION env + cp guard), v1.5.0 release tag. Post-ship doc activity through 2026-05-23 listed in the ecosystem snapshot row above.*

**v4.2.0 shipped (2026-05-21) — Seoul training-data refresh in the ML repo.** UCI 2017-2018 baseline replaced with OA-15182 (Seoul Open Data Plaza, Jan 2022 – Dec 2024, 26,303 hourly rows joined with Open-Meteo historical weather). New Seoul RMSE 1,503.52 bikes/hr (vs UCI baseline 328.84). Shiny `README.md` Business Problem section synced this session; IBM Capstone Dataset section retained intact (UCI 8,760 is the historical evidence base for the R linear / Random Forest benchmarks in `data/processed/model.csv`).

**v4.3.0 shipped (2026-05-21) — Paris timezone fix + Option B 2022 drop + cross-city table alignment in the ML repo.** Scope corrected mid-spec from the original "4-city analogous bug" framing to Paris-only after code inspection confirmed NYC/DC/Chicago parse trip + weather datetimes naively (no `tz_convert` calls). Paris RMSE 20.51 (down from 23.30, −12.0%); 2022 source export dropped as a data-quality gate after the verification gate found it peaked 2h later than 2023+2024 in both AM and PM rush across DST seasons (intrinsic to the provider's aggregation pipeline; reversible single block in `fetch_paris_weather.py`). Bundled cosmetic follow-ups: `train.py` ASCII stdout (em-dash → `--`) + MAE/MSE rows added to NYC + DC RF tables (full cross-city alignment with Seoul post-v4.2.0 format). Tracked follow-ups block now empty for the first time since pre-v4.2.0.

**v1.6.0 Sprint 1 shipped (2026-05-25) — GCP Stream tab reactivated.** `gbfs-poller` Cloud Run service (FastAPI + uvicorn, `python:3.11-slim`, non-root) + `gbfs-poller-cron` Cloud Scheduler (5-min cron, OIDC auth, attempt-deadline 540 s) deployed to `us-central1`. BQ table recreated with DAY partitioning (7-day TTL); `6,032` rows confirmed across London / NYC / Paris / Chicago in first automated 05:50 UTC window. ML side shipped as release [`v3.1.0`](https://github.com/deepan-mehta-analytics/bike-demand-ml-system/releases/tag/v3.1.0) (commits `6d6e5a2` → `7625f17`); ML repo now uses dual-version notation for joint cross-repo work going forward to prevent the v1.4.0 / v1.6.0 mis-naming pattern that conflated Shiny sprint numbers with ML release numbers.

**Sprint 2 (Workstream B — Shiny forecast freshness + honest demo):** Brainstorming → writing-plans → executing-plans cycle pending.

**Sprint 3 (Workstream C — honest claims + meaningful comparisons):** Not yet started.

**Python v4.4.0 drift monitor** in design phase (S1 complete 2026-05-23 — spec `dac2990` + plan `e8d26bb`; S2 next on Python side). No Shiny code changes expected — drift monitor lives entirely in the Python repo.

Resume with: `"resume bike demand prediction project"`
