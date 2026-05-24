# Dashboard Truth and Freshness — Design Spec

**Date:** 2026-05-24
**Author:** Deepan Mehta
**Scope:** Cross-repo (`bike-demand-prediction` + `bike-demand-ml-system`)
**Driver:** Pre-mortem audit on 2026-05-24 identified 14 truth gaps across all 4 dashboard tabs. The root cause for most is a single non-reactive startup fetch (`server.R:122 city_weather_bike_df <- test_weather_data_generation()`) plus a paused upstream pipeline (Dataflow streaming job stopped on 2026-05-15 for cost). User direction: "we can't leave any truth gaps else the dashboard can be considered flawed."

---

## 1. Problem statement

A recruiter-facing live dashboard must satisfy two invariants:
1. **Veracity** — every displayed value must be what it claims to be (live data labelled live; demo data labelled demo; predictions labelled with their engine).
2. **Freshness** — values labelled "Live" must not be more than one refresh-cycle stale.

The current dashboard violates both. Headline failures:
- **GCP Stream tab** has been showing "No data in last 24 hours" for every city since 2026-05-15 because the upstream Dataflow pipeline is paused for cost and no replacement is wired in.
- **Temperature chart** silently displays a flat city-constant when the OpenWeather demo fallback fires — appears live but isn't.
- **Map header / chart badges** read "Live • 24h" while underlying data is fetched once at session start and never refreshed.
- **Operator "Critical Supply Shortage"** alert mechanically compares a 3-hour-window forecast prediction against an instantaneous live bike count — a unit-mismatched ratio dressed up as a decision tool.
- **Rider "Best time to ride"** becomes deterministic (always the same hour per city) under demo fallback because all weather inputs are constant.

Twelve more issues of similar character were identified across the four tabs. The full inventory and severity ranking is in §10 below.

---

## 2. Design constraints

- **GCP free tier (Rule 12)** — no Dataflow, no Cloud Monitoring metric writes, no Vertex AI training at runtime. Cloud Run, Cloud Scheduler (3 jobs free), BigQuery load jobs, Artifact Registry stay within free tier.
- **No new branching workflow** — direct-to-main per the workflow constraints.
- **Preserve existing BQ schema** (`bike-demand-ml-system.bike_demand.station_snapshots`) so no Shiny query changes are needed for Workstream A.
- **Preserve existing Shiny visual hierarchy** — fixes should restructure trust, not redesign the look. Yeti Bootswatch base styles untouched.
- **Each workstream ships independently** — user picked "Ship in Tracks" so design must keep work decoupled across the three sprints.

---

## 3. Sprint plan (ship-in-tracks)

Three sprints, each with its own writing-plans → executing-plans cycle. Each ends in one commit (one PR per sprint) and a user-verified outcome.

| Sprint | Workstream | Repo | Est | User gate to ship |
|---|---|---|---|---|
| **1** | A — GCP Stream Cloud Run poller | `bike-demand-ml-system` | 2-3 h | Run scheduler once manually; verify Shiny GCP Stream tab shows fresh data |
| **2** | B — Forecast freshness + honest demo | `bike-demand-prediction` | 1-2 h | Restart Shiny; verify hourly weather refresh fires; check Paris temp chart is varying (not flat 16°C) |
| **3** | C — Honest claims + meaningful comparisons | `bike-demand-prediction` | 2-3 h | Eyeball each visual change in Shiny; download CSV with new metadata; toggle USE_FASTAPI to confirm engine badge updates |

Sprints 2 and 3 can run in either order or be combined if user prefers. Sprint 1 is structurally first because it sits in a different repo and unlocks the GCP Stream tab's "BigQuery • Live" claim.

---

## 4. Workstream A — GCP Stream Cloud Run poller

**Lives in:** `bike-demand-ml-system`
**Fixes gaps:** #20 (false "Data flows: GBFS → Pub/Sub → Dataflow → BigQuery" claim), #21 ("BigQuery • Live" badge over stale table)

### 4.1 Architecture

```
┌──────────────────┐  POST /poll (OIDC)   ┌──────────────────────────────┐
│ Cloud Scheduler  │ ───────────────────▶ │ Cloud Run service            │
│ gbfs-poller-cron │  cron: */5 * * * *   │ gbfs-poller                  │
│ us-central1      │  attempt_deadline=540│  python:3.11-slim            │
│ retries: 0       │                       │  max-instances=1             │
└──────────────────┘                       │  request-timeout=540s        │
                                            │  mem=256Mi cpu=1            │
                                            │  SA: gbfs-poller-sa@        │
                                            └────┬───────────────────────┘
                                                 │ floor(now, 5min) → window_start
                                                 │ for i in 1..5:
                                                 │   poll_once(cfg)          ← imported as-is
                                                 │   fold into accumulator
                                                 │   sleep 60 (skip on i=5)
                                                 ▼
                                ┌─────────────────────────────────┐
                                │ accumulator (in-memory):        │
                                │  key = (city, station_id, name) │
                                │  agg = avg/min/max/count        │
                                └─────────────┬───────────────────┘
                                              │ flatten ~4,257 rows
                                              ▼
                                ┌─────────────────────────────────┐
                                │ bq_client.load_table_from_json()│
                                │ → bike_demand.station_snapshots │
                                │   WRITE_APPEND (atomic, free)   │
                                └─────────────────────────────────┘
```

### 4.2 Component inventory (new files)

| File | Purpose |
|---|---|
| `pipeline/gbfs_poller_service.py` | FastAPI app with `POST /poll` + `GET /health`. Imports `poll_once` from existing `gbfs_to_pubsub.py` with **zero modifications** to that module. |
| `pipeline/window_agg.py` | Plain-Python `aggregate_window(records_iter, window_start, window_end)` helper. Mirrors `WindowedAgg`'s avg/min/max/count math but is a clean independent implementation — not extracted from `dataflow_job.py`. Low coupling so the Dataflow path stays untouched and resurrection-capable. |
| `Dockerfile.poller` | Slim image: `python:3.11-slim` + `requirements-poller.txt`. ~150 MB. ~3s cold start. |
| `requirements-poller.txt` | Minimal deps: `requests`, `pyyaml`, `google-cloud-bigquery`, `fastapi`, `uvicorn`. No ML deps, no Apache Beam, no scikit-learn. |
| `tests/test_window_agg.py` | Unit tests for the aggregation helper with synthetic snapshots, mirroring existing pytest pattern in the repo. |

### 4.3 GCP resources to create

| Resource | Spec |
|---|---|
| Service account | `gbfs-poller-sa@bike-demand-ml-system.iam.gserviceaccount.com` |
| IAM binding (project) | `roles/bigquery.dataEditor` on dataset `bike-demand-ml-system.bike_demand` only |
| IAM binding (Cloud Run service) | Grant `roles/run.invoker` on `gbfs-poller` to Cloud Scheduler's default SA |
| Cloud Run service | `gbfs-poller` in `us-central1`, image from `us-central1-docker.pkg.dev/bike-demand-ml-system/bike-demand-repo/gbfs-poller:latest`, `--no-allow-unauthenticated`, `--max-instances=1`, `--memory=256Mi`, `--cpu=1`, `--timeout=540`, `--service-account=gbfs-poller-sa@` |
| Cloud Scheduler job | `gbfs-poller-cron` in `us-central1`, cron `*/5 * * * *`, HTTP POST target to Cloud Run service URL, OIDC token, `--attempt-deadline=540s`, `--max-retry-attempts=0` |
| BQ table option | `ALTER TABLE bike_demand.station_snapshots SET OPTIONS (partition_expiration_days = 7)` |

### 4.4 Data flow per 5-min cycle

1. Cloud Scheduler fires at `:00`, `:05`, `:10`, ... on UTC clock.
2. POST to `https://gbfs-poller-<hash>-uc.a.run.app/poll` with OIDC token.
3. Cloud Run starts (cold or warm), FastAPI handler:
   a. Compute `window_start = floor(now, 5min)`, `window_end = window_start + 5min`
   b. Loop `i in 1..5`:
      - `records_by_city = poll_once(config)` from `gbfs_to_pubsub.py`
      - For each city, for each station record: fold into accumulator keyed by `(city, station_id, station_name)`
      - `sleep(60)` (skip on `i=5`)
   c. Convert accumulator to list of dicts matching `BQ_SCHEMA`:
      - `city, station_id, station_name, window_start, window_end, avg_bikes_available, min_bikes_available, max_bikes_available, total_snapshots`
   d. `bq_client.load_table_from_json(rows, table_ref, write_disposition=WRITE_APPEND)`
   e. Return JSON `{"status": "ok", "rows_written": N, "window_start": "...", "window_end": "..."}`

Total wall time per cycle: ~270s (4 × 60s sleep + 5 × ~5s polls + ~5s BQ load + small overhead).

### 4.5 Error handling

| Scenario | Handler |
|---|---|
| One city's GBFS endpoint returns 5xx in one iteration | `poll_once` already swallows and returns `[]` for that city for that iteration. Other cities and other iterations proceed. |
| All 5 iterations fail for one city | Accumulator has no entries for that city → that city writes 0 rows this cycle. Other cities unaffected. Logged as a structured warning. |
| BQ `load_table_from_json` raises | Handler returns 500 to Scheduler. Scheduler `retry_count=0` → no retry → no duplicate-write risk. Next cron fires in 5 min, fresh window. |
| Cold start delays first poll by ~3s | Absorbed by the 540s timeout budget. |
| Scheduler skips a fire (e.g., previous run exceeded attempt_deadline) | Acceptable. Gap of 5-10 min in the table. Shiny tab handles gaps gracefully. |

### 4.6 Idempotency

Load jobs are atomic — either all rows for a cycle land or none do. With Scheduler `retry_count=0`, the only path to duplicate rows is a manual re-run, which is intentional. Out of scope: per-row dedup. If ever needed later, add a `cycle_id` UUID column.

### 4.7 Testing

| Level | Approach |
|---|---|
| Unit | `tests/test_window_agg.py` — synthetic `{(city, station_id, name): [records]}` → assert avg/min/max/count math, edge case of empty input, edge case of single snapshot per station (avg=min=max=value). |
| Local integration | Run `uvicorn pipeline.gbfs_poller_service:app --port 8000` with env var `DRY_RUN=true` (skips BQ write, returns row count in response). `curl localhost:8000/poll` and inspect response. |
| First-deploy e2e | After Cloud Run deploy, run `gcloud scheduler jobs run gbfs-poller-cron` manually. ~5 min later: `bq query "SELECT MAX(window_start), COUNT(*) FROM ... WHERE window_start > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)"`. Expect `window_start` within last 10 min and rows ≈ `4,257`. Then check Shiny GCP Stream tab — status panel should show "4 cities with recent data". |

### 4.8 Cost (Rule 12 audit)

| Resource | Monthly usage | Free tier | Status |
|---|---|---|---|
| Cloud Run | 8,640 invocations × ~270s × 256 MiB ≈ ~600 GB-s | 2M req + 360k GB-s | ✅ ample headroom |
| Cloud Scheduler | 2 jobs (existing `bike-demand-weekly-retrain` + new `gbfs-poller-cron`) | 3 jobs/month | ✅ |
| BigQuery load jobs | 8,640/mo = 288/day | 1500/day/table | ✅ |
| BigQuery storage | 7-day rolling × ~5 GB/mo growth ≈ ~1.2 GB on disk | 10 GB | ✅ |
| Artifact Registry | ~150 MB image | 10 GB | ✅ |
| Cloud Logging stdout | minor structured logs | 50 GiB/mo | ✅ |
| **Total** | | | **$0/mo** |

### 4.9 Shiny-side consequences

**None required.** Schema preserved. `query_city_trend` and `query_latest_snapshot` continue to work unchanged — they just start finding rows again. The "BigQuery • Live" badge and "5-min windows" claim become accurate.

---

## 5. Workstream B — Forecast freshness + honest demo

**Lives in:** `bike-demand-prediction` (Shiny repo)
**Fixes gaps:** #1, #2, #3, #9, #12, #14, #15, #19. *Adjacent to #10 — makes the forecast number in that alert non-stale, but the unit-mismatched ratio itself is fully rewritten in Workstream C.*

### 5.1 Root cause being addressed

`server.R:122` runs `city_weather_bike_df <- test_weather_data_generation()` exactly once at session start. The variable is **not a reactive**, so every chart, alert, prediction, badge, and map title that derives from it is frozen at session-start state for the entire session life.

Additionally, `generate_demo_weather_data()` (the fallback when OpenWeather fails) uses a single `TEMPERATURE` constant per city (`model_prediction.R:550`) and replicates it across all 8 forecast slots via `cross_join`. Result: flat horizontal line, visually obvious as fake.

### 5.2 Changes

**B1. Make weather a reactive that refreshes hourly.**

```r
# server.R — replace the line-122 non-reactive with:
weather_timer <- reactiveTimer(3600000)  # 1 hour

city_weather_bike_df <- reactive({
  weather_timer()                          # dependency: re-runs every hour
  test_weather_data_generation()           # same function, called inside reactive
})
```

Every downstream consumer of `city_weather_bike_df` (currently ~12 reactives/renderers) must change from direct reference to `city_weather_bike_df()` invocation. The `cities_max_bike` derived frame and `fmt_start`/`fmt_end` strings must move inside a `reactive({...})` block so they recompute when weather refreshes.

**B2. Diurnal variation in demo fallback.**

In `generate_demo_weather_data()`, replace constant city-level TEMPERATURE/HUMIDITY with slot-varying expressions. Specifically:

```r
# inside the cross-joined df, after slot_times are defined:
HOURS_NUMERIC = as.numeric(format(slot_times, "%H", tz = "UTC")),
TEMPERATURE   = city_base_temp + 5 * sin((HOURS_NUMERIC - 6) * pi / 12),  # peaks ~14:00, troughs ~02:00
HUMIDITY      = pmin(95L, pmax(35L, city_base_humidity + as.integer(-8 * sin((HOURS_NUMERIC - 6) * pi / 12))))
```

Choice of curve: simple sinusoid with peak at 14:00, amplitude 5°C, anchored to the existing city-base value (so Paris's mean stays 16°C but ranges 11-21°C across the day). Humidity inversely correlated. This is meteorologically plausible and visually distinct from a flat line.

**B3. Honest data-source label on every chart that consumes weather.**

Add a `data_source` column to both the live and demo paths in `generate_city_weather_bike_data()` and `generate_demo_weather_data()`. Values: `"openweather_live"` vs `"demo_fallback"`. Pass through `selected_city_data()`.

In each chart's subtitle, append a small badge:
- Live: subtitle ends with `(Source: OpenWeather, refreshed HH:MM UTC)`
- Demo: subtitle ends with `(Source: Demo fallback — set OPENWEATHER_KEY in .Renviron and restart)`

The footer text `"Powered by OpenWeather API"` becomes conditional — reactive that reads the current `data_source`.

**B4. Reactive date-range in map title.**

`fmt_start` / `fmt_end` move inside a reactive so the map header `24-Hour Bike Demand Forecast • 12:00 → 09:00 next day` updates on every hourly refresh.

### 5.3 Files touched

| File | Change |
|---|---|
| `shiny_app/server.R` | Wrap weather fetch in reactive; convert `cities_max_bike` and `fmt_start`/`fmt_end` to reactives; update ~12 consumers to call as `()`; add reactive footer |
| `shiny_app/model_prediction.R` | Add slot-varying temperature/humidity to `generate_demo_weather_data`; add `data_source` column to both live and demo paths |
| `shiny_app/ui.R` | Convert footer to `uiOutput("footer_text")` so it can respond to data_source |

### 5.4 Testing

| Level | Approach |
|---|---|
| Unit | testthat `test-model-prediction.R` — assert `generate_demo_weather_data()` returns 8 rows per city with `TEMPERATURE` varying within ±5 of base; assert `data_source` column present in both paths with correct values |
| Manual | Restart Shiny with valid `.Renviron` → confirm "Source: OpenWeather, refreshed HH:MM" subtitle on temp chart; rename `.Renviron` to break the API → restart → confirm subtitle says "Demo fallback" and the curve has a sinusoid shape, not a flat line |
| Time-based manual | Open Shiny, wait 1 hour, observe map header date-range advances + temp chart timeline advances by an hour (next forecast slot rolls in) |

### 5.5 Out of scope for Workstream B

- Changing the OpenWeather call cadence (still 1 call per city per hour via the refresh; well under 1000/day free tier across 6 cities)
- A manual "Refresh Now" button on the Live Map (not in C either — defer to a future v1.7 if user demand surfaces)
- Reworking the underlying forecast source — still OpenWeather 5-day/3-hour

---

## 6. Workstream C — Honest claims + meaningful comparisons

**Lives in:** `bike-demand-prediction` (Shiny repo)
**Fixes gaps:** #4 (engine indicator), #5 (humidity smoother), #6 (hardcoded city/forecast counts), #7 (global thresholds), #10 (unit-mismatched operator alert), plus surfaces #16-18 as already-correct.

### 6.1 Changes

**C1. Engine indicator on bike demand chart.**

`build_bike_chart` reads `Sys.getenv("USE_FASTAPI")` once at function scope, appends to subtitle:
- USE_FASTAPI=true → `"Engine: FastAPI Random Forest"`
- USE_FASTAPI=false → `"Engine: Local linear regression"`

No RMSE quoted in UI (RMSE belongs in README/PROJECT-STATUS — quoting in real-time UI invites drift).

**C2. Humidity chart — drop the overfit smoother.**

Replace `geom_smooth(method = "lm", formula = y ~ poly(x, 4))` with `geom_smooth(method = "lm")` (linear) and update subtitle from "24-Hour forecast window" to `"Linear trend across 8 forecast slots"`. Eight data points support a linear trend honestly; a 4th-order polynomial does not.

**C3. Derive city/forecast counts.**

`ui.R:337-342` stat card replaces hardcoded `"6"` and `"24"` with `textOutput("stat_cities")` and `textOutput("stat_hours")`. Server renders them from `length(unique(city_weather_bike_df()$CITY_ASCII))` and a constant `24` (the 24-hour forecast horizon is genuinely fixed in the API call, so it stays a constant but is documented as such).

**C4. Per-city demand thresholds.**

Current `calculate_bike_prediction_level()` uses global thresholds `<1000` / `1000-3000` / `>3000`. Result: NYC always red, Seoul always green — meaningless cross-city signal.

Replace with per-city quantiles computed from that city's own 24-hour forecast:
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

This must be called **inside a `group_by(CITY_ASCII)`** in `generate_city_weather_bike_data` so each city's slots are levelled against that city's own range. Legend updates to: *"Low / Medium / High — relative to this city's 24h forecast range"*.

**C5. Operator "Critical Supply Shortage" — fix unit mismatch.**

Current alert compares `peak_24h_demand` (forecast units, ~hundreds to thousands depending on city) against `current_total_bikes` (live snapshot units, same scale by coincidence in some cities). The ratio is incoherent.

Replacement: a coherent operator dashboard alert based on **current snapshot state**, not future forecast:
- Critical (red): `≥ 25% of stations have zero bikes`
- Warning (amber): `≥ 10% of stations have zero bikes` OR fleet fill rate `< 20%`
- Healthy (green): otherwise

Forecast peak is still shown in the panel body as context (`"24h peak demand forecast: X bikes — for capacity planning context"`) but does not drive the alert level.

**C6. CSV download metadata.**

`download_forecast` handler prepends header rows to the CSV:
```
# Bike Demand 24h Forecast — exported YYYY-MM-DD HH:MM UTC
# City: <city_name>
# Source: <openweather_live | demo_fallback>
# Forecast horizon: <start> -> <end>
```

Filename pattern: `bike-demand-forecast-<city>-<YYYYMMDD-HHMM>.csv` (includes UTC stamp).

### 6.2 Files touched

| File | Change |
|---|---|
| `shiny_app/server.R` | C1, C5, C6 changes — chart subtitle, operator alert reactive, download handler |
| `shiny_app/ui.R` | C3 — replace hardcoded stat numbers with textOutput |
| `shiny_app/model_prediction.R` | C2 (chart formula), C4 (per-city threshold function + grouped application) |
| `shiny_app/README.md` (no — not in this sprint) | Will be updated in post-sprint doc sync (Rule 11) |

### 6.3 Testing

| Level | Approach |
|---|---|
| Unit | testthat for per-city quantile thresholds — assert each city's 8 slots split ~3/3/2 into small/medium/large; assert operator alert returns red when zero-bike count ≥ 25%, amber at 10%, green otherwise |
| Manual | Toggle USE_FASTAPI → confirm chart subtitle changes accordingly; download CSV → open in Excel → confirm metadata rows; eyeball Operator alert across all 6 cities — should now show meaningful variation (Seoul currently green/many bikes, etc.) |

---

## 7. Cross-workstream concerns

### 7.1 Order independence

Sprints can theoretically ship in any order but the natural order is A → B → C because:
- A's success enables the GCP Stream tab claims to be true (no Shiny code change needed)
- B's hourly refresh enables every chart to actually be "live", which makes C's per-cycle accuracy improvements meaningful (otherwise C is polishing stale data)
- C's per-city thresholds depend on B's reactive `city_weather_bike_df()` being non-stale

### 7.2 README + PROJECT-STATUS impact (Rule 11)

After each sprint:
- **Sprint 1 ship** — README "Known Limitations" Phase 7F entry updated; PROJECT-STATUS GCP Stream row marked v1.6.0 candidate; companion ML-repo README + PROJECT-STATUS updated with new Cloud Run service entry
- **Sprint 2 ship** — README Phase 7B/7C limitations updated; v1.6.0 In Development → Released label flip if 2 ships at this point; new "Honest demo fallback" feature line
- **Sprint 3 ship** — Phase 7D/7E retrospectives updated; new "Per-city demand thresholds" + "Engine indicator" feature lines

### 7.3 Version planning

This work bundles into a **v1.6.0 release** of `bike-demand-prediction` titled *"Dashboard Honesty Pass"*. Workstream A ships a corresponding minor bump in `bike-demand-ml-system` (v4.4.0 if the Python-side spec hasn't shipped yet, else v4.5.0).

### 7.4 Cross-repo doc sync

Both repos' ecosystem snapshot rows must update after each sprint, per the cross-repo-sync-mandatory-closeout protocol.

---

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Cloud Run cold start makes first poll iteration take >30s → window math drifts | Compute `window_start = floor(now_at_handler_entry, 5min)` before the loop, not before each iteration. Drift becomes a sub-second concern. |
| OpenWeather quota cap hit by hourly polling | 6 cities × 24 hourly fetches × 30 days = 4,320 calls/mo. Free tier is 1000/day = 30,000/mo. Massive headroom. |
| Per-city quantile thresholds make Seoul's "medium" badge red on a still-quiet day | The legend wording clarifies *"relative to this city's 24h forecast range"* — this is the correct semantic. A user reading "high" understands it as "peak of today for this city", not "global high." |
| Operator alert thresholds (25% / 10% empty stations) too tight or too loose in real GBFS data | Thresholds are configurable constants at the top of `server.R`. Easy to tune after a week of live observation. |
| User starts Shiny before `.Renviron` exists; B1 reactive fires hourly but `Sys.getenv("OPENWEATHER_KEY")` is empty all session | B3's source badge will display "Demo fallback — set OPENWEATHER_KEY in .Renviron and restart". Demo path now has diurnal variation so charts look plausible. User sees the badge, fixes their env, restarts. No silent failure. |
| Workstream B touches ~12 reactive consumers — risk of missing one | testthat unit tests + manual smoke test across all four tabs after Sprint 2 commit. Each tab must render without error and show non-flat data. |

---

## 9. Out of scope

- Replacing OpenWeather as the forecast source
- Adding Paris/Seoul to the GCP Stream tab (the Pub/Sub configs don't include them — would need Workstream A to expand its config first)
- Refreshing GBFS station data more often than every 5 minutes (already at 5-min in Sprint 1; existing Shiny GBFS poll is also 5-min)
- Adding historical playback / time-travel views
- shinytest2 reactive harness for the new reactives (existing testthat covers pure functions; reactive testing is Phase 8 backlog)
- New tabs or new dashboard surfaces
- Recruiter-narrative README rewrite (separate sprint, post v1.6.0 ship)

---

## 10. Full gap inventory (from 2026-05-24 pre-mortem)

Severity scale: 🔴 Critical (contradicts reality) · 🟠 High (misleading in common case) · 🟡 Medium (correct but conceptually fragile) · 🟢 Already correct

### Live Map tab

| # | Claim | Source | Severity | Sprint |
|---|---|---|---|---|
| 1 | "Live • 24h" badge | Weather fetched once at session start | 🔴 | B |
| 2 | "24-Hour Bike Demand Forecast • DD MMM HH:MM → ..." map title | `fmt_start`/`fmt_end` frozen at session start | 🔴 | B |
| 3 | Temperature trend chart | Demo fallback = single constant × 8 slots | 🔴 | B |
| 4 | Bike demand chart | One of two engines (USE_FASTAPI env var) with no UI indicator | 🟠 | C |
| 5 | Humidity vs Demand scatter | `poly(x, 4)` smoother fit to 8 points | 🟡 | C |
| 6 | "6 Cities · 24 Hr Forecast" stat card | Hardcoded literals | 🟡 | C |
| 7 | Legend "Low <1k / Med 1k-3k / High >3k" | Global thresholds across cities with 20× peak-range variation | 🟡 | C |
| 8 | "[Demo — Clear]" / "[Demo data — weather API key not set]" in popups | Honest demo flag in popup HTML | 🟢 already honest | — |
| 9 | "Powered by OpenWeather API" footer | Only true on live path | 🟠 | B |

### Operator tab

| # | Claim | Source | Severity | Sprint |
|---|---|---|---|---|
| 10 | "Critical Supply Shortage" alert (peak vs current ratio) | Unit-mismatched comparison: forecast 3h window vs instantaneous snapshot | 🔴 | C |
| 11 | "X% fleet capacity" progress bar | `sum(AVAILABLE_BIKES)/sum(CAPACITY)` from live GBFS | 🟢 | — |
| 12 | "Download 24h CSV" export | Exports session-start forecast with no timestamp | 🟠 | C |
| 13 | Map markers (size = capacity, colour = fill-rate) | Live GBFS | 🟢 | — |

### Rider tab

| # | Claim | Source | Severity | Sprint |
|---|---|---|---|---|
| 14 | "Demand Score — Next 9 Hours" | First 3 slots of startup-fetched forecast | 🟠 | B |
| 15 | "Best Time to Ride Today: Around HH:MM" | `slot_min(BIKE_PREDICTION)` — under demo, deterministic per city | 🔴 | B |
| 16 | "X bikes available across Y open stations" | Live GBFS | 🟢 | — |
| 17 | Top Stations table | Live GBFS, sorted by bikes | 🟢 | — |
| 18 | Rider map markers | Live GBFS | 🟢 | — |
| 19 | "Quietest window today: HH:MM" hint | Same as #15 | 🔴 | B |

### GCP Stream tab

| # | Claim | Source | Severity | Sprint |
|---|---|---|---|---|
| 20 | "Data flows: GBFS → Pub/Sub → Dataflow → BigQuery every 5 minutes" | Pipeline paused since 2026-05-15 | 🔴 | A |
| 21 | "BigQuery • Live" chart badge | BQ table 206h stale | 🔴 | A |
| 22 | "Auto-refreshes every 5 minutes" hint | reactiveTimer correctly wired | 🟢 (truth restored by A) | A |
| 23 | "N cities with recent data" status panel | Real BQ count over last 24h | 🟢 already honest | — |

### Feed Health panel (Live Map left sidebar)

| # | Claim | Source | Severity | Sprint |
|---|---|---|---|---|
| 24 | "LIVE / DELAYED / UNAVAILABLE" colour-coded city rows | Real `get_city_live_stations()` results with failure-count state machine | 🟢 already correct (shipped 2026-05-17 in Feed Health Alerting sprint) | — |

**Severity tally:** 7 🔴 Critical · 4 🟠 High · 3 🟡 Medium · 10 🟢 already correct

---

## 11. Definition of done (across all three sprints)

A reviewer or recruiter exercising the dashboard for the first time encounters:

1. Every chart, badge, alert, prediction, and label states **what data source** it is showing.
2. Every "Live" label is true — data is at most one refresh cycle stale.
3. Every comparison between two numbers compares two compatible quantities.
4. Every recommendation ("Best time to ride", "Critical Supply Shortage") is grounded in coherent math.
5. Demo fallbacks, when they fire, look like plausible weather (not flat lines) and identify themselves in the UI.
6. The GCP Stream tab actually streams.

When `git log v1.6.0 --oneline` reads cleanly across both repos, this spec is fulfilled.

---

## 12. References

- Pre-mortem audit transcript: in-conversation 2026-05-24
- Cross-repo sync protocol: `[[cross-repo-sync-mandatory-closeout]]` memory
- GCP free-tier rules: `CLAUDE.md` Rule 12
- Existing Cloud Run trigger pattern: `pipeline/vertex_trigger.py` (`bike-demand-ml-system`)
- Existing GBFS poll function being reused: `pipeline/gbfs_to_pubsub.py::poll_once` (`bike-demand-ml-system`)
- Existing aggregation logic being mirrored: `pipeline/dataflow_job.py::WindowedAgg` (`bike-demand-ml-system`)
