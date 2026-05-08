# Project Status — Bike Demand Prediction (R Shiny Dashboard)

> Re-entry command: `"resume bike demand prediction project"`
> Companion repo: `D:\OneDrive\Developer\Data Engineering\bike-demand-ml-system`

---

## 🌐 Ecosystem Snapshot

Both repos form a single portfolio system. Track them together here.

| Repo | Role | Current Phase | Status | Last Commit |
|------|------|--------------|--------|-------------|
| **bike_demand_prediction** (this repo) | R Shiny dashboard | Phase 7H complete — 6 cities; v1.0.0 released | ✅ Done | `432335d` |
| **bike-demand-ml-system** | Python FastAPI + ML training | Phase 3 in progress — GHCR publish wired; Cloud Run pending | 🔄 In Progress | `ce43e8a` |

### Trained City Models (Python repo)

| City | RMSE (bikes/hr) | Top Feature | Dashboard Cities | API Artifact |
|------|-----------------|-------------|-----------------|--------------|
| Seoul | **173.21** | TEMPERATURE (0.34) | Seoul | `artifacts/seoul/` |
| London | **228.58** | HOUR (0.71) | London | `artifacts/london/` |
| NYC | **345.69** | HOUR (0.52) | New York | `artifacts/nyc/` |
| Washington DC | **97.47** | HOUR (0.61) | Washington DC | `artifacts/dc/` ✅ |
| Paris | — | — (Seoul fallback) | Paris | Seoul proxy |
| Chicago | — | — (Seoul fallback) | Chicago | Seoul proxy |

### Next Milestones (Both Repos)

| Repo | Next Phase | Dependency |
|------|-----------|------------|
| bike_demand_prediction | Phase 7F — GCP Streaming Pipeline | Waits on Python Phase 4 (Pub/Sub + Dataflow) |
| bike-demand-ml-system | Phase 3 — Cloud Run Deployment | None — can start now |

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

---

## ⚠️ Known Limitations

* Paris and Chicago have no city-specific RF models — FastAPI falls back to Seoul model (proxy only; less accurate)
* No unit/integration tests (pytest / testthat) for ETL or model evaluation functions
* Seoul GBFS not integrated (requires free API key at data.seoul.go.kr)
* `USE_FASTAPI` is env-var controlled — no in-app toggle (by design for Docker simplicity)
* Phase 7F (GCP Streaming Pipeline) depends on Python repo Phase 4 being deployed first

---

## 🔜 Roadmap

### Phase 7F — GCP Streaming Pipeline ← **next (after Python Phase 4)**
* `pipeline/gbfs_to_pubsub.py` — GBFS poller → Pub/Sub topic (`USE_PUBSUB=false` for local)
* `pipeline/dataflow_job.py` — Apache Beam: Pub/Sub → BigQuery windowed aggregation
* Local mode: DirectRunner + DuckDB (no GCP account required for dev)
* **Lives in the Python repo** (`bike-demand-ml-system`), not here
* This repo: `config/gcp_config.yaml` already created (connection settings only)

### Backlog
* pytest / testthat unit tests for ETL and model evaluation functions
* Seoul GBFS integration (free API key at data.seoul.go.kr)
* Train Paris and Chicago models to replace Seoul proxy (requires sourcing data)
* Expand to 8 cities (San Francisco or Amsterdam — Washington DC already added)

---

## 🚀 Next Step

**Phase 7F — GCP Streaming Pipeline** (blocked until Python repo Phase 3/4 complete).
In the meantime: watch for Python repo Cloud Run deployment, then update `FASTAPI_URL`
env var in `docker-compose.yml` to point at the live Cloud Run URL.

Resume with: `"resume bike demand prediction project"`
