# testthat Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 36-test testthat suite covering model prediction, GBFS parsing, and BigQuery lookup tables, enforced by a GitHub Actions CI workflow on every push and PR.

**Architecture:** Three test files in `tests/testthat/`, each sourcing the module under test from `shiny_app/` as the working directory. HTTP calls in GBFS parsers are stubbed using `mockery::stub()` — no network access, no cassettes. CI uses `r-lib/actions/setup-renv@v2` for deterministic dependency restore from `renv.lock`.

**Tech Stack:** R 4.4, testthat 3.x, mockery, r-lib/actions/setup-r@v2, r-lib/actions/setup-renv@v2

---

### Task 1: Bootstrap testthat + mockery

**Files:**
- Create: `tests/testthat.R`
- Modify: `renv.lock` (via `renv::install()` + `renv::snapshot()`)

- [ ] **Step 1: Install testthat and mockery into the renv library**

Open an R console in the repo root (or run via Rscript):

```r
renv::install(c("testthat", "mockery"))
renv::snapshot()
```

Expected: `renv.lock` updated with `testthat` and `mockery` entries. Both packages appear under `renv/library/`.

- [ ] **Step 2: Create the tests/ directory structure**

```bash
mkdir -p tests/testthat
```

- [ ] **Step 3: Create `tests/testthat.R` — local run entrypoint**

```r
# tests/testthat.R
# Run from repo root: Rscript tests/testthat.R
# Or from shiny_app/: Rscript -e 'testthat::test_dir("../tests/testthat")'
library(testthat)                                     # load test framework
setwd("shiny_app")                                    # all source() calls resolve relative to shiny_app/
testthat::test_dir(                                   # discover and run all test-*.R files
  "../tests/testthat",
  reporter  = "progress",                             # show each test as it runs
  stop_on_failure = TRUE                              # exit non-zero on first failure
)
```

- [ ] **Step 4: Verify the empty suite runs without error**

Run from repo root:

```bash
Rscript tests/testthat.R
```

Expected output:
```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 0 ]
```

No errors. Exit code 0.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat.R renv.lock
git commit -m "test(config): bootstrap testthat + mockery; add tests/ entrypoint"
```

---

### Task 2: test-model-prediction.R (16 tests)

**Files:**
- Create: `tests/testthat/test-model-prediction.R`

All tests run from `shiny_app/` as working directory. `model.csv` is resolved via the existing hardcoded path in `load_saved_model("model.csv")` — no production code changes needed.

- [ ] **Step 1: Create `tests/testthat/test-model-prediction.R`**

```r
# tests/testthat/test-model-prediction.R
# Working directory when run: shiny_app/
# Source resolves to shiny_app/model_prediction.R
library(testthat)                                              # test framework
suppressMessages(source("model_prediction.R"))                 # load module under test; suppress package load msgs


# ── safe_val() ───────────────────────────────────────────────────────────────

test_that("safe_val: NULL returns NA_real_ by default", {
  expect_identical(safe_val(NULL), NA_real_)                  # default = NA_real_ when input is NULL
})

test_that("safe_val: NULL with custom default returns that default", {
  expect_identical(safe_val(NULL, default = 0.0), 0.0)        # custom default honoured for NULL
})

test_that("safe_val: non-NULL value passes through unchanged", {
  expect_identical(safe_val(15.5), 15.5)                      # non-NULL bypasses default entirely
})


# ── calculate_bike_prediction_level() ────────────────────────────────────────

test_that("calculate_bike_prediction_level: 0 is small", {
  expect_equal(calculate_bike_prediction_level(0), "small")   # floor boundary
})

test_that("calculate_bike_prediction_level: 1000 is small (inclusive upper bound)", {
  expect_equal(calculate_bike_prediction_level(1000), "small") # inclusive: 0–1000 = small
})

test_that("calculate_bike_prediction_level: 1001 is medium", {
  expect_equal(calculate_bike_prediction_level(1001), "medium") # first medium value
})

test_that("calculate_bike_prediction_level: 2999 is medium", {
  expect_equal(calculate_bike_prediction_level(2999), "medium") # last medium value
})

test_that("calculate_bike_prediction_level: 3000 is large", {
  expect_equal(calculate_bike_prediction_level(3000), "large")  # first large value
})

test_that("calculate_bike_prediction_level: vectorised input returns correct-length result", {
  result <- calculate_bike_prediction_level(c(0, 1500, 5000))  # one from each bucket
  expect_equal(result, c("small", "medium", "large"))           # preserves order and length
})


# ── load_saved_model() ────────────────────────────────────────────────────────

test_that("load_saved_model: returns a named numeric vector", {
  model <- load_saved_model("model.csv")                       # reads shiny_app/model.csv
  expect_true(is.numeric(model))                               # coefficients are numeric
  expect_false(is.null(names(model)))                          # names must be present for lookup
})

test_that("load_saved_model: names include all keys used by predict_bike_demand", {
  model <- load_saved_model("model.csv")                       # reads shiny_app/model.csv
  required_keys <- c(
    "Intercept",                                               # baseline term
    as.character(0:23),                                        # 24 hour-of-day keys
    "SPRING", "SUMMER", "AUTUMN", "WINTER"                    # 4 season keys
  )
  missing <- setdiff(required_keys, names(model))              # keys present in spec but absent from CSV
  expect_equal(
    length(missing), 0L,
    label = paste("Missing model keys:", paste(missing, collapse = ", "))
  )
})


# ── predict_bike_demand() ─────────────────────────────────────────────────────

test_that("predict_bike_demand: returns integer vector same length as input", {
  result <- predict_bike_demand(
    TEMPERATURE = c(15.0, 20.0),                               # two rows of input
    HUMIDITY    = c(60L,  55L),
    WIND_SPEED  = c(3.0,  4.0),
    VISIBILITY  = c(10000L, 9000L),
    SEASONS     = c("SPRING", "SUMMER"),
    HOURS       = c(8L, 12L)
  )
  expect_true(is.integer(result))                              # pmax(as.integer(...)) guarantees integer
  expect_length(result, 2L)                                    # one prediction per input row
})

test_that("predict_bike_demand: all values are non-negative", {
  result <- predict_bike_demand(
    TEMPERATURE = -10.0,                                       # cold conditions may produce low raw prediction
    HUMIDITY    = 90L,
    WIND_SPEED  = 10.0,
    VISIBILITY  = 500L,
    SEASONS     = "WINTER",
    HOURS       = 3L                                           # 3 AM — very low demand
  )
  expect_true(all(result >= 0L, na.rm = TRUE))                 # pmax floor must prevent negatives
})

test_that("predict_bike_demand: smoke test — peak spring morning is a positive integer", {
  result <- predict_bike_demand(
    TEMPERATURE = 15.0,
    HUMIDITY    = 60L,
    WIND_SPEED  = 3.0,
    VISIBILITY  = 10000L,
    SEASONS     = "SPRING",
    HOURS       = 8L                                           # morning commute peak
  )
  expect_true(is.integer(result) && result > 0L && !is.na(result))  # must be a real positive prediction
})


# ── generate_demo_weather_data() ──────────────────────────────────────────────

test_that("generate_demo_weather_data: returns exactly 48 rows", {
  result <- suppressMessages(generate_demo_weather_data())     # 6 cities x 8 forecast slots
  expect_equal(nrow(result), 48L)
})

test_that("generate_demo_weather_data: schema and prediction values are valid", {
  result <- suppressMessages(generate_demo_weather_data())
  expected_cols <- c(                                          # columns server.R expects
    "CITY_ASCII", "LNG", "LAT",
    "TEMPERATURE", "HUMIDITY",
    "BIKE_PREDICTION", "BIKE_PREDICTION_LEVEL",
    "LABEL", "DETAILED_LABEL", "FORECASTDATETIME"
  )
  expect_equal(names(result), expected_cols)                   # schema must match server.R contract
  expect_true(all(result$BIKE_PREDICTION >= 0L))               # no negative predictions
  expect_true(all(result$BIKE_PREDICTION_LEVEL %in% c("small", "medium", "large")))  # valid levels only
})
```

- [ ] **Step 2: Run the test file and verify all 16 pass**

```bash
cd shiny_app
Rscript -e 'testthat::test_file("../tests/testthat/test-model-prediction.R")'
```

Expected:
```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]
```

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-model-prediction.R
git commit -m "test(model): add 16 pure-function tests for model_prediction.R"
```

---

### Task 3: test-gbfs-client.R (16 tests)

**Files:**
- Create: `tests/testthat/test-gbfs-client.R`

Uses `mockery::stub()` to patch `fetch_gbfs_json` inside each parser function — no live HTTP calls. `stub(f, "name", replacement)` replaces the binding of `"name"` inside `f`'s environment for the duration of the calling test.

- [ ] **Step 1: Create `tests/testthat/test-gbfs-client.R`**

```r
# tests/testthat/test-gbfs-client.R
# Working directory when run: shiny_app/
library(testthat)                                              # test framework
library(mockery)                                               # stub() for HTTP call patching
library(tibble)                                                # tibble() for fixture construction
library(dplyr)                                                 # bind_rows(), filter()
suppressMessages(source("gbfs_client.R"))                      # load module; defines all functions + constants


# ── Shared fixtures ───────────────────────────────────────────────────────────
# Minimal GBFS v2 + TfL JSON structures. Station "2" has NULL coordinates in
# both fixtures — used to verify NA-coord filtering in parsers.

fake_gbfs_info <- function() {                                 # mimics station_information.json structure
  list(data = list(stations = list(
    list(station_id = "1", name = "Test St",
         lat = 40.7, lon = -74.0, capacity = 20L),
    list(station_id = "2", name = "NA Coords",                 # NULL coords — should be dropped
         lat = NULL,  lon = NULL,  capacity = 10L)
  )))
}

fake_gbfs_status <- function() {                               # mimics station_status.json structure
  list(data = list(stations = list(
    list(station_id = "1", num_bikes_available = 5L,
         num_docks_available = 15L, is_renting = 1L, last_reported = 1700000000L),
    list(station_id = "2", num_bikes_available = 3L,
         num_docks_available = 7L,  is_renting = 1L, last_reported = 1700000001L)
  )))
}

fake_tfl <- function() {                                       # mimics TfL BikePoint response array
  list(
    list(                                                      # station with full data
      id = "BikePoints_1", commonName = "River St",
      lat = 51.53, lon = -0.11,
      additionalProperties = list(
        list(key = "NbBikes",      value = "4"),               # bikes available
        list(key = "NbEmptyDocks", value = "13"),              # empty docks
        list(key = "NbDocks",      value = "17")               # total docks
      )
    ),
    list(                                                      # station with NULL coords — should be dropped
      id = "BikePoints_2", commonName = "NA Coords",
      lat = NULL, lon = NULL,
      additionalProperties = list()
    )
  )
}

make_station_tibble <- function(n = 2L) {                      # helper: build n-row station tibble
  tibble(
    CITY_ASCII      = rep("New York", n),
    STATION_ID      = as.character(seq_len(n)),
    STATION_NAME    = paste("Station", seq_len(n)),
    LAT             = rep(40.7, n),
    LNG             = rep(-74.0, n),
    AVAILABLE_BIKES = rep(5L, n),
    AVAILABLE_DOCKS = rep(15L, n),
    CAPACITY        = rep(20L, n),
    IS_RENTING      = rep(TRUE, n),
    LAST_UPDATED    = rep(1700000000L, n)
  )
}


# ── %||% ─────────────────────────────────────────────────────────────────────

test_that("%||%: NULL returns fallback", {
  expect_equal(NULL %||% "fallback", "fallback")               # NULL left-hand side → use right
})

test_that("%||%: non-NULL value returned unchanged", {
  expect_equal("value" %||% "fallback", "value")               # non-NULL left-hand side → ignore right
})


# ── EMPTY_STATIONS_SCHEMA ─────────────────────────────────────────────────────

test_that("EMPTY_STATIONS_SCHEMA has the correct 10 column names", {
  expected <- c(
    "CITY_ASCII", "STATION_ID", "STATION_NAME",
    "LAT", "LNG",
    "AVAILABLE_BIKES", "AVAILABLE_DOCKS", "CAPACITY",
    "IS_RENTING", "LAST_UPDATED"
  )
  expect_equal(names(EMPTY_STATIONS_SCHEMA), expected)         # exact names; order matters for bind_rows()
})

test_that("EMPTY_STATIONS_SCHEMA has 0 rows and correct column types", {
  expect_equal(nrow(EMPTY_STATIONS_SCHEMA), 0L)                # zero rows — it is a schema, not data
  expect_type(EMPTY_STATIONS_SCHEMA$CITY_ASCII,      "character")
  expect_type(EMPTY_STATIONS_SCHEMA$STATION_ID,      "character")
  expect_type(EMPTY_STATIONS_SCHEMA$STATION_NAME,    "character")
  expect_type(EMPTY_STATIONS_SCHEMA$LAT,             "double")
  expect_type(EMPTY_STATIONS_SCHEMA$LNG,             "double")
  expect_type(EMPTY_STATIONS_SCHEMA$AVAILABLE_BIKES, "integer")
  expect_type(EMPTY_STATIONS_SCHEMA$AVAILABLE_DOCKS, "integer")
  expect_type(EMPTY_STATIONS_SCHEMA$CAPACITY,        "integer")
  expect_type(EMPTY_STATIONS_SCHEMA$IS_RENTING,      "logical")
  expect_type(EMPTY_STATIONS_SCHEMA$LAST_UPDATED,    "integer")
})


# ── parse_standard_gbfs() ─────────────────────────────────────────────────────

test_that("parse_standard_gbfs: output column names match EMPTY_STATIONS_SCHEMA", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(url, ...) {   # patch HTTP call
    if (grepl("information", url)) fake_gbfs_info() else fake_gbfs_status()
  })
  result <- parse_standard_gbfs("New York",
                                 "http://x/information.json",
                                 "http://x/status.json")
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))    # schema must match exactly
})

test_that("parse_standard_gbfs: CITY_ASCII propagated to every output row", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(url, ...) {
    if (grepl("information", url)) fake_gbfs_info() else fake_gbfs_status()
  })
  result <- parse_standard_gbfs("New York",
                                 "http://x/information.json",
                                 "http://x/status.json")
  expect_true(all(result$CITY_ASCII == "New York"))            # city name must appear on every row
})

test_that("parse_standard_gbfs: drops stations with NULL/NA coordinates", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(url, ...) {
    if (grepl("information", url)) fake_gbfs_info() else fake_gbfs_status()
  })
  result <- parse_standard_gbfs("New York",
                                 "http://x/information.json",
                                 "http://x/status.json")
  expect_equal(nrow(result), 1L)                               # station "2" (NULL coords) must be dropped
  expect_equal(result$STATION_ID, "1")                         # only station "1" survives
})

test_that("parse_standard_gbfs: returns EMPTY_STATIONS_SCHEMA when fetch returns NULL", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(...) NULL)  # simulate network failure
  result <- suppress_warnings(
    parse_standard_gbfs("New York",
                         "http://x/information.json",
                         "http://x/status.json")
  )
  expect_equal(nrow(result), 0L)                               # degrade gracefully — no rows
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))    # schema intact even on failure
})


# ── parse_tfl_bikepoint() ─────────────────────────────────────────────────────

test_that("parse_tfl_bikepoint: output column names match EMPTY_STATIONS_SCHEMA", {
  stub(parse_tfl_bikepoint, "fetch_gbfs_json", function(...) fake_tfl())
  result <- parse_tfl_bikepoint("https://api.tfl.gov.uk/bikepoint")
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))    # schema must match exactly
})

test_that("parse_tfl_bikepoint: extracts NbBikes, NbEmptyDocks, NbDocks correctly", {
  stub(parse_tfl_bikepoint, "fetch_gbfs_json", function(...) fake_tfl())
  result <- parse_tfl_bikepoint("https://api.tfl.gov.uk/bikepoint")
  row1   <- result[result$STATION_ID == "BikePoints_1", ]      # isolate known station
  expect_equal(row1$AVAILABLE_BIKES, 4L)                       # NbBikes = "4" → 4L
  expect_equal(row1$AVAILABLE_DOCKS, 13L)                      # NbEmptyDocks = "13" → 13L
  expect_equal(row1$CAPACITY,        17L)                      # NbDocks = "17" → 17L
})

test_that("parse_tfl_bikepoint: returns EMPTY_STATIONS_SCHEMA when fetch returns NULL", {
  stub(parse_tfl_bikepoint, "fetch_gbfs_json", function(...) NULL)  # simulate network failure
  result <- suppress_warnings(
    parse_tfl_bikepoint("https://api.tfl.gov.uk/bikepoint")
  )
  expect_equal(nrow(result), 0L)                               # degrade gracefully
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))
})


# ── parse_gbfs_stations() ─────────────────────────────────────────────────────

test_that("parse_gbfs_stations: unknown city returns EMPTY_STATIONS_SCHEMA with warning", {
  expect_warning(
    result <- parse_gbfs_stations("Atlantis"),                 # not in CITY_GBFS_CONFIG
    regexp = "No GBFS config"                                  # warning message must mention config
  )
  expect_equal(nrow(result), 0L)
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))
})

test_that("parse_gbfs_stations: London routes to parse_tfl_bikepoint (not standard GBFS)", {
  mock_tfl <- mock(EMPTY_STATIONS_SCHEMA)                      # mock records calls and returns value
  stub(parse_gbfs_stations, "parse_tfl_bikepoint", mock_tfl)
  parse_gbfs_stations("London")
  expect_called(mock_tfl, 1L)                                  # must be called exactly once
})


# ── get_city_live_stations() ──────────────────────────────────────────────────

test_that("get_city_live_stations: success path returns enriched list with status=ok", {
  stub(get_city_live_stations, "parse_gbfs_stations",
       function(...) make_station_tibble(2L))                  # stub returns 2-row tibble
  result <- get_city_live_stations("New York")
  expect_true(all(c("data", "status", "row_count", "fetched_at", "message") %in% names(result)))
  expect_equal(result$status,    "ok")                         # non-empty result → ok
  expect_equal(result$row_count, 2L)                           # matches nrow of stub return
  expect_null(result$message)                                  # message is NULL on success
})

test_that("get_city_live_stations: failure path returns status=error with non-empty message", {
  stub(get_city_live_stations, "parse_gbfs_stations",
       function(...) EMPTY_STATIONS_SCHEMA)                    # stub returns 0-row tibble → failure
  result <- get_city_live_stations("New York")
  expect_equal(result$status,    "error")                      # 0 rows → error
  expect_equal(result$row_count, 0L)
  expect_true(nchar(result$message) > 0L)                      # must include a human-readable reason
})

test_that("get_city_live_stations: fetched_at is POSIXct", {
  stub(get_city_live_stations, "parse_gbfs_stations",
       function(...) EMPTY_STATIONS_SCHEMA)
  result <- get_city_live_stations("New York")
  expect_s3_class(result$fetched_at, "POSIXct")               # timestamp class required by server.R
})
```

- [ ] **Step 2: Run the test file and verify all 16 pass**

```bash
cd shiny_app
Rscript -e 'testthat::test_file("../tests/testthat/test-gbfs-client.R")'
```

Expected:
```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]
```

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-gbfs-client.R
git commit -m "test(gbfs): add 16 schema + routing tests for gbfs_client.R using mockery stubs"
```

---

### Task 4: test-bigquery-client.R (4 tests)

**Files:**
- Create: `tests/testthat/test-bigquery-client.R`

Pure named-vector assertions — no GCP credentials required. `bq_auth_safe()` is excluded from testing since it requires live credentials not available in CI.

- [ ] **Step 1: Create `tests/testthat/test-bigquery-client.R`**

```r
# tests/testthat/test-bigquery-client.R
# Working directory when run: shiny_app/
# Only tests pure lookup table constants — no GCP auth tested.
library(testthat)                                              # test framework
suppressMessages(source("bigquery_client.R"))                  # defines BQ_CITY_SLUG_TO_NAME + BQ_CITY_NAME_TO_SLUG


# ── BQ_CITY_SLUG_TO_NAME ──────────────────────────────────────────────────────

test_that("BQ_CITY_SLUG_TO_NAME: nyc maps to New York", {
  expect_equal(unname(BQ_CITY_SLUG_TO_NAME["nyc"]), "New York")   # unname() strips the key from comparison
})

test_that("BQ_CITY_SLUG_TO_NAME: dc maps to Washington DC", {
  expect_equal(unname(BQ_CITY_SLUG_TO_NAME["dc"]), "Washington DC")
})

test_that("BQ_CITY_SLUG_TO_NAME: london maps to London", {
  expect_equal(unname(BQ_CITY_SLUG_TO_NAME["london"]), "London")
})


# ── BQ_CITY_NAME_TO_SLUG ──────────────────────────────────────────────────────

test_that("BQ_CITY_NAME_TO_SLUG: New York maps to nyc (inverse mapping correct)", {
  expect_equal(unname(BQ_CITY_NAME_TO_SLUG["New York"]), "nyc")   # reverse of BQ_CITY_SLUG_TO_NAME
})
```

- [ ] **Step 2: Run the test file and verify all 4 pass**

```bash
cd shiny_app
Rscript -e 'testthat::test_file("../tests/testthat/test-bigquery-client.R")'
```

Expected:
```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 4 ]
```

- [ ] **Step 3: Run the full suite and verify all 36 pass**

```bash
cd shiny_app
Rscript -e 'testthat::test_dir("../tests/testthat")'
```

Expected:
```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 36 ]
```

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/test-bigquery-client.R
git commit -m "test(bigquery): add 4 lookup table tests for bigquery_client.R"
```

---

### Task 5: GitHub Actions CI + README badge

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `README.md`

- [ ] **Step 1: Create `.github/workflows/ci.yml`**

```bash
mkdir -p .github/workflows
```

```yaml
# .github/workflows/ci.yml
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

      - uses: r-lib/actions/setup-renv@v2

      - name: Run testthat suite
        working-directory: shiny_app
        run: Rscript -e 'testthat::test_dir("../tests/testthat", reporter = "progress", stop_on_failure = TRUE)'
```

- [ ] **Step 2: Add the CI badge to `README.md`**

Find the existing `## 🏷️ Project Badges` section in `README.md`. Add this badge immediately after the existing CI badge line (or as the first badge if none exists):

```markdown
[![CI](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml/badge.svg)](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml)
```

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/ci.yml README.md
git commit -m "ci: add GitHub Actions testthat job; add CI badge to README"
git push origin main
```

- [ ] **Step 4: Verify CI passes on GitHub**

Navigate to: `https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions`

Expected: the `CI / testthat` job shows green. All 36 tests pass. The CI badge on README renders green.

If the job fails, the most likely causes are:
- `renv.lock` does not include `testthat` or `mockery` → re-run `renv::install(c("testthat", "mockery"))` + `renv::snapshot()` locally and push the updated lockfile
- `working-directory: shiny_app` not resolving `model.csv` → confirm `model.csv` is committed in `shiny_app/` and not gitignored
- `source("bigquery_client.R")` fails on missing `bigrquery` → `bigrquery` must be in `renv.lock`; run `renv::snapshot()` locally to verify

---

## Summary

| Task | Tests Added | Commit message |
|------|-------------|----------------|
| 1 — Bootstrap | 0 | `test(config): bootstrap testthat + mockery; add tests/ entrypoint` |
| 2 — model-prediction | 16 | `test(model): add 16 pure-function tests for model_prediction.R` |
| 3 — gbfs-client | 16 | `test(gbfs): add 16 schema + routing tests for gbfs_client.R using mockery stubs` |
| 4 — bigquery-client | 4 | `test(bigquery): add 4 lookup table tests for bigquery_client.R` |
| 5 — CI + badge | 0 | `ci: add GitHub Actions testthat job; add CI badge to README` |
| **Total** | **36** | |
