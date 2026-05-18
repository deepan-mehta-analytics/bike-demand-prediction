# testthat Suite Design — bike_demand_prediction

**Date:** 2026-05-18
**Status:** Approved

---

## Problem

The Shiny app has no automated test suite and no CI. The three core modules (`model_prediction.R`, `gbfs_client.R`, `bigquery_client.R`) contain business logic that breaks silently:

1. `calculate_bike_prediction_level()` boundary thresholds control map marker colours — a silent off-by-one changes every marker on the map
2. `predict_bike_demand()` looks up named coefficients from `model.csv` by exact string key — a renamed coefficient returns `NA` and `pmax` silently zeros all predictions
3. GBFS parsers map live JSON fields to a 10-column schema — any field rename in the upstream API produces wrong column types or dropped stations with no error raised
4. `get_city_live_stations()` enriched wrapper drives the Feed Health Alerting panel — its `status`/`row_count`/`message` contract is untested

No GitHub Actions CI means there is no enforcement gate. Bugs reach `main` unchecked.

---

## Design

Three test files covering pure functions, GBFS parser schema compliance (HTTP-mocked via `mockery`), and BigQuery lookup tables. One CI workflow enforcing the suite on every push and PR.

---

### File Structure

```
tests/
  testthat/
    test-model-prediction.R    ← pure function tests for model_prediction.R
    test-gbfs-client.R         ← schema + parser tests for gbfs_client.R
    test-bigquery-client.R     ← lookup table tests for bigquery_client.R
  testthat.R                   ← entrypoint: testthat::test_dir("testthat")
.github/
  workflows/
    ci.yml                     ← R 4.4 + renv::restore() + testthat on every push
```

**Scope boundary:**

| Module | Tested | Rationale |
|--------|--------|-----------|
| `model_prediction.R` | ✅ pure functions | All testable without network or credentials |
| `gbfs_client.R` | ✅ with `mockery` stubs | HTTP layer stubbed; schema + routing tested |
| `bigquery_client.R` | ✅ lookup tables only | `bq_auth_safe()` requires live GCP credentials — excluded |
| `server.R` / `ui.R` | ❌ | Shiny reactives require `shinytest2` browser harness — out of scope |

**Working directory:** All tests run from `shiny_app/` as working directory. This makes `model.csv` resolvable via the existing hardcoded `load_saved_model("model.csv")` path with no production code changes, matching how the app runs at runtime.

**New dependencies:** `testthat`, `mockery` — added to `renv.lock` via `renv::install()` + `renv::snapshot()`.

---

### Test File 1 — `test-model-prediction.R` (16 tests)

**`safe_val()` — 3 tests**

| Test | Input | Expected |
|------|-------|----------|
| NULL returns NA_real_ | `safe_val(NULL)` | `NA_real_` |
| NULL with custom default | `safe_val(NULL, default = 0.0)` | `0.0` |
| Non-NULL passes through | `safe_val(15.5)` | `15.5` |

**`calculate_bike_prediction_level()` — 6 tests**

Boundary conditions — these control map marker colours:

| Test | Input | Expected |
|------|-------|----------|
| Zero | `0` | `"small"` |
| Upper small (inclusive) | `1000` | `"small"` |
| Lower medium | `1001` | `"medium"` |
| Upper medium (inclusive) | `2999` | `"medium"` |
| Lower large | `3000` | `"large"` |
| Vectorised input | `c(0, 1500, 5000)` | `c("small", "medium", "large")` |

**`load_saved_model()` — 2 tests**

- Returns a named numeric vector (not a data frame, not a list)
- Names include all required lookup keys: `"Intercept"`, `"0"` through `"23"` (24 hour keys), `"SPRING"`, `"SUMMER"`, `"AUTUMN"`, `"WINTER"` — any missing key causes `predict_bike_demand()` to silently return `NA`

**`predict_bike_demand()` — 3 tests**

Uses real `model.csv` (resolved from `shiny_app/` working directory):

- Returns an integer vector of the same length as the input vectors
- All values ≥ 0 (`pmax(..., 0)` floor enforced — no negative predictions)
- Smoke test: `TEMPERATURE=15`, `HUMIDITY=60`, `WIND_SPEED=3`, `VISIBILITY=10000`, `SEASONS="SPRING"`, `HOURS=8` → result is a positive non-NA integer

**`generate_demo_weather_data()` — 2 tests**

- Returns exactly 48 rows (6 cities × 8 forecast slots = 48)
- Column names match the schema `server.R` expects: `CITY_ASCII`, `LNG`, `LAT`, `TEMPERATURE`, `HUMIDITY`, `BIKE_PREDICTION`, `BIKE_PREDICTION_LEVEL`, `LABEL`, `DETAILED_LABEL`, `FORECASTDATETIME`; all `BIKE_PREDICTION` values ≥ 0; all `BIKE_PREDICTION_LEVEL` values in `c("small", "medium", "large")`

---

### Test File 2 — `test-gbfs-client.R` (16 tests)

HTTP calls are stubbed using `mockery::stub()` — the same surgical pattern as the Python routing tests' `monkeypatch`. No cassette files, no network required.

A shared helper at the top of the file builds minimal GBFS v2 fixture data:

```r
fake_gbfs_info <- function() {
  list(data = list(stations = list(
    list(station_id = "1", name = "Test St",
         lat = 40.7, lon = -74.0, capacity = 20L),
    list(station_id = "2", name = "NA Coords",
         lat = NULL, lon = NULL, capacity = 10L)   # should be dropped by filter
  )))
}

fake_gbfs_status <- function() {
  list(data = list(stations = list(
    list(station_id = "1", num_bikes_available = 5L,
         num_docks_available = 15L, is_renting = 1L, last_reported = 1700000000L),
    list(station_id = "2", num_bikes_available = 3L,
         num_docks_available = 7L,  is_renting = 1L, last_reported = 1700000001L)
  )))
}
```

**`%||%` — 2 tests**
- `NULL %||% "fallback"` → `"fallback"`
- `"value" %||% "fallback"` → `"value"`

**`EMPTY_STATIONS_SCHEMA` — 2 tests**
- Has exactly 10 columns: `CITY_ASCII`, `STATION_ID`, `STATION_NAME`, `LAT`, `LNG`, `AVAILABLE_BIKES`, `AVAILABLE_DOCKS`, `CAPACITY`, `IS_RENTING`, `LAST_UPDATED`
- Has 0 rows; column types are `character`, `character`, `character`, `double`, `double`, `integer`, `integer`, `integer`, `logical`, `integer`

**`parse_standard_gbfs()` — 4 tests**

Stub: `mockery::stub(parse_standard_gbfs, "fetch_gbfs_json", function(url, ...) if (grepl("information", url)) fake_gbfs_info() else fake_gbfs_status())`

- Schema compliance: output column names match `names(EMPTY_STATIONS_SCHEMA)` exactly
- City propagation: every row has `CITY_ASCII == "New York"` when called with `city_name = "New York"`
- NA-coord filtering: station with `lat = NULL` (station_id `"2"`) is dropped; result has 1 row, not 2
- NULL fetch degrades gracefully: stub returns `NULL` → returns `EMPTY_STATIONS_SCHEMA` (0 rows, no error thrown)

**`parse_tfl_bikepoint()` — 3 tests**

Stub returns a 2-element list mimicking TfL BikePoint response:

```r
fake_tfl <- function() list(
  list(id = "BikePoints_1", commonName = "River St",
       lat = 51.53, lon = -0.11,
       additionalProperties = list(
         list(key = "NbBikes",      value = "4"),
         list(key = "NbEmptyDocks", value = "13"),
         list(key = "NbDocks",      value = "17")
       )),
  list(id = "BikePoints_2", commonName = "NA Coords",
       lat = NULL, lon = NULL,
       additionalProperties = list())
)
```

- Schema compliance: output column names match `names(EMPTY_STATIONS_SCHEMA)`
- Field extraction: `AVAILABLE_BIKES == 4L`, `AVAILABLE_DOCKS == 13L`, `CAPACITY == 17L` for station 1
- NULL fetch degrades gracefully: returns `EMPTY_STATIONS_SCHEMA`

**`parse_gbfs_stations()` — 2 tests**
- Unknown city name returns `EMPTY_STATIONS_SCHEMA` and emits a warning (not an error — app must not crash)
- `"London"` routes to TfL path: stub `parse_tfl_bikepoint` and assert it is called (not `parse_standard_gbfs`)

**`get_city_live_stations()` — 3 tests**

Stub `parse_gbfs_stations` to control what the enriched wrapper sees:

- On success (stub returns 2-row tibble): result is a list with fields `data`, `status`, `row_count`, `fetched_at`, `message`; `status == "ok"`, `row_count == 2L`, `message` is `NULL`
- On failure (stub returns 0-row `EMPTY_STATIONS_SCHEMA`): `status == "error"`, `row_count == 0L`, `message` is a non-empty character string
- `fetched_at` is `POSIXct` class (not `NULL`, not character)

---

### Test File 3 — `test-bigquery-client.R` (4 tests)

Pure named-vector assertions — no GCP calls:

- `BQ_CITY_SLUG_TO_NAME["nyc"]` == `"New York"`
- `BQ_CITY_SLUG_TO_NAME["dc"]` == `"Washington DC"`
- `BQ_CITY_SLUG_TO_NAME["london"]` == `"London"`
- `BQ_CITY_NAME_TO_SLUG["New York"]` == `"nyc"` (inverse mapping correct)

`bq_auth_safe()` is excluded — requires live `GOOGLE_APPLICATION_CREDENTIALS` not available in CI.

---

### CI Workflow — `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]

jobs:
  test:
    name: testthat
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.4"
      - uses: r-lib/actions/setup-renv@v1
      - name: Run testthat suite
        working-directory: shiny_app
        run: Rscript -e 'testthat::test_dir("../tests/testthat", reporter = "progress", stop_on_failure = TRUE)'
```

- `r-lib/actions/setup-renv@v1` calls `renv::restore()` from `renv.lock` — fully deterministic, no ad-hoc `install.packages()` in CI
- `working-directory: shiny_app` ensures `model.csv` and `selected_cities.csv` are resolvable with no production code changes
- `stop_on_failure = TRUE` makes the CI job exit non-zero on any test failure

No lintr job — the repo has no linting baseline yet; adding it without fixing existing warnings would fail CI on day 1. A separate lint phase is the right approach.

---

## Test Count Summary

| File | Tests |
|------|-------|
| `test-model-prediction.R` | 16 |
| `test-gbfs-client.R` | 16 |
| `test-bigquery-client.R` | 4 |
| **Total** | **36** |

---

## Out of Scope

- `server.R` / `ui.R` — Shiny reactive tests require `shinytest2` browser harness; separate phase
- `bq_auth_safe()` and BigQuery query functions — require live GCP credentials
- Lintr / style checks — no existing baseline; separate phase
- `predict_bike_demand_fastapi()` HTTP path — FastAPI service not available in CI; the fallback path to `predict_bike_demand()` is already covered by the model prediction tests
