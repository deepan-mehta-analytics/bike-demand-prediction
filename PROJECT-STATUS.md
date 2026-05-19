# Project Status — Bike Demand Prediction (R Shiny Dashboard)

> Re-entry command: `"resume bike demand prediction project"`
> Companion repo: `D:\OneDrive\Developer\Data Engineering\bike-demand-ml-system`

---

## 🌐 Ecosystem Snapshot

Both repos form a single portfolio system. Track them together here.

| Repo | Role | Current Phase | Status | Last Commit |
|------|------|--------------|--------|-------------|
| **bike_demand_prediction** (this repo) | R Shiny dashboard | v1.5.0 shipped — testthat suite (36 tests / 62 assertions) + GitHub Actions CI | ✅ Done | `edd97e3` |
| **bike-demand-ml-system** | Python FastAPI + ML training | v4.1.0 — 6-city pytest suite shipped (27 tests, CI Job 7) | ✅ Done | `dfcf872` |

### Trained City Models (Python repo)

All RMSEs use a **chronological 80/20 split** (oldest 80% → train, newest 20% → test), matching `train.py` exactly.

| City | RMSE (bikes/hr) | Top Feature | Dashboard Cities | API Artifact |
|------|-----------------|-------------|-----------------|--------------|
| Seoul | **328.84** | TEMPERATURE (0.40) | Seoul | `artifacts/seoul/` |
| London | **316.56** | HOUR (0.71) | London | `artifacts/london/` |
| NYC | **470.76** | HOUR (0.52) | New York | `artifacts/nyc/` |
| Washington DC | **119.31** | HOUR (0.62) | Washington DC | `artifacts/dc/` ✅ |
| Paris | **23.30** | HOUR (0.634) | Paris | `artifacts/paris/` ✅ |
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
| **6** | bike_demand_prediction | Backlog — Seoul GBFS | — | External API key |
| **7** | bike_demand_prediction | Backlog — City expansion (SF/Amsterdam) | — | Data sourcing required |

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

* Paris RMSE (23.30) reflects counter MEAN normalisation (~50–500/hr scale), not raw station volume — correct relative to training data
* Reactive logic in `server.R` and `ui.R` not yet covered — would require `shinytest2` browser harness (out of scope for v1.5; candidate for a future phase)
* Seoul GBFS not integrated (requires free API key at data.seoul.go.kr)
* `USE_FASTAPI` is env-var controlled — no in-app toggle (by design for Docker simplicity)
* GCP Stream tab requires `GOOGLE_APPLICATION_CREDENTIALS` env var pointing to a GCP service account JSON — not configured by default; tab shows setup instructions when not set

---

## 🔜 Roadmap

### Phase 7F — GCP Streaming Dashboard ✅ DONE (v1.2.0 — 2026-05-16)
* `shiny_app/bigquery_client.R` — `bq_auth_safe()`, `query_city_trend()`, `query_latest_snapshot()`
* 4th "GCP Stream" tab in Shiny — live 5-min windowed avg/min/max bikes per city, auto-refresh every 5 min
* bigrquery 1.6.2 + 22 deps added to `renv.lock` via `renv::record()`
* Commits `9b1fd47` (code) + `1764b19` (renv.lock) pushed to origin/main

### ✅ Backlog — Paris/Chicago models (v1.4.0) — SHIPPED 2026-05-18
* Paris RF — Vélib' Métropole open data (2022–2024, 26,297 rows); RMSE 23.30; `artifacts/paris/`
* Chicago RF — Divvy quarterly CSVs (2019–2022, 32,720 rows); RMSE 202.99; `artifacts/chicago/`
* Seoul fallback proxy removed for both cities

### v1.5.0 — testthat suite + CI (shipped 2026-05-19)
* 36-test / 62-assertion testthat suite: `test-model-prediction.R` (20 assertions), `test-gbfs-client.R` (38), `test-bigquery-client.R` (4)
* HTTP layer fully stubbed via `mockery::stub()` — no network, no cassettes
* GitHub Actions `testthat` job (4th job in `ci.yml`) — mirrors `r-check`'s renv-restore pattern, shares its renv cache key
* Cold-cache run: ~5 min; warm-cache run: ~1 min (62 assertions in ~2 s once renv is restored)

### Backlog — Priority 7: Seoul GBFS
* Seoul live station markers (free API key required at data.seoul.go.kr)
* External dependency — low ROI until key is obtained

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

*Latest commit `edd97e3` — ci: add GitHub Actions testthat job to ci.yml (2026-05-19).*

**Next move:** v1.5.0 GitHub release covering the testthat suite milestone, then decide between Priority 6 (Seoul GBFS key registration) or Phase 8 (shinytest2 for server.R / ui.R reactives).

Resume with: `"resume bike demand prediction project"`
