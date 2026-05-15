# Project Status — Bike Demand Prediction (R Shiny Dashboard)

> Re-entry command: `"resume bike demand prediction project"`
> Companion repo: `D:\OneDrive\Developer\Data Engineering\bike-demand-ml-system`

---

## 🌐 Ecosystem Snapshot

Both repos form a single portfolio system. Track them together here.

| Repo | Role | Current Phase | Status | Last Commit |
|------|------|--------------|--------|-------------|
| **bike_demand_prediction** (this repo) | R Shiny dashboard | Phase 7H complete — 6 cities; v1.0.0 released | ✅ Done | `e45ced8` |
| **bike-demand-ml-system** | Python FastAPI + ML training | Phase 4 in progress — GBFS poller + Dataflow scaffolding committed (v3.0.0) | 🔄 In Progress | `0b22378` |

### Trained City Models (Python repo)

| City | RMSE (bikes/hr) | Top Feature | Dashboard Cities | API Artifact |
|------|-----------------|-------------|-----------------|--------------|
| Seoul | **173.21** | TEMPERATURE (0.34) | Seoul | `artifacts/seoul/` |
| London | **228.58** | HOUR (0.71) | London | `artifacts/london/` |
| NYC | **345.69** | HOUR (0.52) | New York | `artifacts/nyc/` |
| Washington DC | **97.47** | HOUR (0.61) | Washington DC | `artifacts/dc/` ✅ |
| Paris | — | — (Seoul fallback) | Paris | Seoul proxy |
| Chicago | — | — (Seoul fallback) | Chicago | Seoul proxy |

### Next Milestones (Both Repos) — Priority Ordered

| Priority | Repo | Phase | Target Version | Dependency |
|----------|------|-------|---------------|------------|
| ~~1~~ | bike-demand-ml-system | ~~Phase 6 — Observability~~ | ~~v2.1.0~~ | **✅ Shipped** |
| **1** | bike-demand-ml-system | Phase 4 — Pub/Sub + Dataflow | v3.0.0 | None — unblocked |
| **2** | bike_demand_prediction | Phase 7F — GCP Streaming Dashboard | v1.2.0 | Waits on Python Phase 4 |
| **3** | bike-demand-ml-system | Phase 5 — Vertex AI + MLflow | v4.0.0 | Best after streaming data exists |
| **4** | bike_demand_prediction | Backlog — Paris/Chicago models | v1.3.0 | Data sourcing required |
| **5** | Both | Backlog — testthat / pytest | — | None |
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

---

## ⚠️ Known Limitations

* Paris and Chicago have no city-specific RF models — FastAPI falls back to Seoul model (proxy only; less accurate)
* No unit/integration tests (pytest / testthat) for ETL or model evaluation functions
* Seoul GBFS not integrated (requires free API key at data.seoul.go.kr)
* `USE_FASTAPI` is env-var controlled — no in-app toggle (by design for Docker simplicity)
* Phase 7F (GCP Streaming Pipeline) depends on Python repo Phase 4 being deployed first

---

## 🔜 Roadmap

### Phase 7F — GCP Streaming Dashboard ← Priority 3 (v1.2.0 — after Python Phase 4)
* `pipeline/gbfs_to_pubsub.py` — GBFS poller → Pub/Sub topic (`USE_PUBSUB=false` for local)
* `pipeline/dataflow_job.py` — Apache Beam: Pub/Sub → BigQuery windowed aggregation
* Local mode: DirectRunner + DuckDB (no GCP account required for dev)
* **Pipeline lives in the Python repo** (`bike-demand-ml-system`); this repo integrates BigQuery output into Shiny dashboard
* This repo: `config/gcp_config.yaml` already created (connection settings only)

### Backlog — Priority 5: Paris/Chicago models (v1.3.0)
* Train Paris RF model — source Vélib' Métropole open data (Paris OpenData portal)
* Train Chicago RF model — source Divvy trip data (Chicago Data Portal)
* Removes Seoul fallback proxy for both cities; improves prediction accuracy

### Backlog — Priority 6: Testing
* pytest / testthat unit tests for ETL and model evaluation functions
* Engineering rigour; fill-in work between major phases

### Backlog — Priority 7: Seoul GBFS
* Seoul live station markers (free API key required at data.seoul.go.kr)
* External dependency — low ROI until key is obtained

### Backlog — Priority 8: City expansion
* Expand to 8 cities — San Francisco (Ford GoBike) or Amsterdam (OV-fiets)
* Requires data sourcing and model training in Python repo

---

## 🚀 Next Step

**This repo is waiting on Python repo Priority 1 (Phase 4 — Pub/Sub + Dataflow, v3.0.0).** Once Phase 4 is deployed, Phase 7F (Priority 2, v1.2.0) becomes the next active task here — integrating the Dataflow → BigQuery output into the Shiny dashboard.

*Python repo Phase 4 is in progress — GBFS poller + Dataflow pipeline scaffolding committed 2026-05-15 (commit `0b22378`). GCP provisioning step remains before end-to-end verification.*

Resume with: `"resume bike demand prediction project"`
