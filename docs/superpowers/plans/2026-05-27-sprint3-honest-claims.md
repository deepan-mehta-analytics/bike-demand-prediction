# Sprint 3 — Honest Claims + B3 Carry-over Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the 7-item Sprint 3 scope (B3 carry-over + C1-C6) defined in [`docs/superpowers/specs/2026-05-27-sprint3-honest-claims-design.md`](../specs/2026-05-27-sprint3-honest-claims-design.md), closing out the v1.6.0 "Dashboard Honesty Pass" release.

**Architecture:** Each of the 7 items lands in its own commit via TDD (failing test → implement → green → commit). Where Shiny code is currently inline in renderUI/downloadHandler, extract pure helpers so unit tests can target them. Doc-sync commit at the end runs Pattern A-D sweep and tags v1.6.0.

**Tech Stack:** R 4.4.3, Shiny, testthat (3rd ed), withr (env-var mocking), dplyr, tidyr, scales, leaflet, ggplot2, Yeti Bootswatch 3.

---

## File map

| File | Tasks touching it | Net change |
|---|---|---|
| `shiny_app/model_prediction.R` | T1 (B3 data_source col), T2 (C4 quantile + group_by) | ~30 LOC |
| `shiny_app/server.R` | T1 (subtitle + footer helper + reactive), T3 (C5 alert helper + reactive), T4 (C1 engine subtitle), T5 (C2 smoother), T6 (C3 textOutput), T7 (C6 CSV helpers + handler) | ~120 LOC |
| `shiny_app/ui.R` | T1 (footer uiOutput), T6 (textOutput placeholders), T2 (legend wording) | ~10 LOC |
| `tests/testthat/test-model-prediction.R` | T1 (data_source col), T2 (quantile distribution) | ~30 LOC added |
| `tests/testthat/test-data-source-footer.R` (new) | T1 (footer helper) | ~50 LOC |
| `tests/testthat/test-build-bike-chart.R` (new) | T4 (engine subtitle) | ~40 LOC |
| `tests/testthat/test-stat-card.R` (new) | T6 (derived counts) | ~25 LOC |
| `tests/testthat/test-operator-alert.R` (new) | T3 (alert helper) | ~60 LOC |
| `tests/testthat/test-download-handler.R` (new) | T7 (CSV helpers) | ~40 LOC |
| `README.md` + `PROJECT-STATUS.md` | T8 (doc sync) | ~50 LOC |

**Order (risk + dependency):** T1 (B3 foundation, C6 depends on data_source) → T2 (C4) → T3 (C5 Critical) → T4 (C1) → T5 (C2) → T6 (C3) → T7 (C6) → T8 (docs + v1.6.0 release).

**Per-task TDD cycle:** write failing test → run + see RED → implement minimal code → run + see GREEN → commit. Each task = one git commit.

**Baseline test count to confirm before starting:** 37 tests / 63 assertions passing on `main` HEAD (per workflow_status). Run `Rscript -e 'library(testthat); test_dir("tests/testthat", reporter="summary")'` from repo root to confirm.

---

## Task 1: B3 — data_source column + reactive footer + chart subtitle source line

**Files:**
- Modify: `shiny_app/model_prediction.R` (both generators, add `data_source` column)
- Modify: `shiny_app/server.R` (extract `build_data_source_footer()` + `build_data_source_subtitle_line()` helpers; update `build_temp_chart` + `build_bike_chart`; add `output$data_source_footer` renderUI)
- Modify: `shiny_app/ui.R:388-391` (replace static string with `uiOutput("data_source_footer")`)
- Modify: `tests/testthat/test-model-prediction.R` (add data_source column assertions)
- Create: `tests/testthat/test-data-source-footer.R` (footer helper logic)

- [ ] **Step 1: Write failing tests for data_source column + footer helper**

Append to `tests/testthat/test-model-prediction.R`:

```r
test_that("generate_demo_weather_data adds data_source = 'demo_fallback' to every row", {
  df <- generate_demo_weather_data()
  expect_true("data_source" %in% colnames(df))
  expect_true(all(df$data_source == "demo_fallback"))
})
```

Create new file `tests/testthat/test-data-source-footer.R`:

```r
# Tests for build_data_source_footer() helper (B3)
# Helper takes a df with a data_source column and returns a character footer line.

library(testthat)                                                          # testthat framework
library(rprojroot)                                                         # repo-root resolution for source()
proj_root <- find_root(has_file("renv.lock"))                              # locate repo root from any wd
setwd(file.path(proj_root, "shiny_app"))                                   # match runtime working dir of Shiny app

source("server_helpers.R")                                                 # the helper module created in Task 1

test_that("build_data_source_footer returns OpenWeather-only message when all cities live", {
  df <- data.frame(
    CITY_ASCII  = c("Seoul", "London", "New York"),                        # 3 cities
    data_source = rep("openweather_live", 3L)                              # all live
  )
  out <- build_data_source_footer(df)                                      # call helper
  expect_match(out, "Powered by OpenWeather API")                          # base claim present
  expect_false(grepl("demo fallback", out, ignore.case = TRUE))            # no mixed-state suffix
  expect_false(grepl("not set", out, ignore.case = TRUE))                  # no all-demo suffix
})

test_that("build_data_source_footer reports mixed-state count when some cities on demo", {
  df <- data.frame(
    CITY_ASCII  = c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC"),
    data_source = c("openweather_live", "openweather_live", "demo_fallback",
                    "openweather_live", "openweather_live", "openweather_live")
  )
  out <- build_data_source_footer(df)
  expect_match(out, "Powered by OpenWeather API")                          # live claim retained
  expect_match(out, "1 of 6 cities on demo fallback")                      # explicit mixed-state count
})

test_that("build_data_source_footer reports all-demo message when no cities live", {
  df <- data.frame(
    CITY_ASCII  = c("Seoul", "London"),
    data_source = c("demo_fallback", "demo_fallback")
  )
  out <- build_data_source_footer(df)
  expect_match(out, "Demo data")                                           # all-demo claim
  expect_match(out, "OPENWEATHER_KEY not set")                             # actionable user hint
})

test_that("build_data_source_subtitle_line returns timestamped OpenWeather line for live source", {
  out <- build_data_source_subtitle_line("openweather_live", as.POSIXct("2026-05-27 14:30:00", tz = "UTC"))
  expect_match(out, "Source: OpenWeather")                                 # source name
  expect_match(out, "14:30 UTC")                                           # passed-in time formatted
})

test_that("build_data_source_subtitle_line returns demo hint for fallback source", {
  out <- build_data_source_subtitle_line("demo_fallback", Sys.time())      # time arg ignored for demo
  expect_match(out, "Demo fallback")                                       # source label
  expect_match(out, "OPENWEATHER_KEY")                                     # env var name in actionable hint
})
```

- [ ] **Step 2: Run tests; expect FAIL**

```powershell
Rscript -e "library(testthat); test_file('tests/testthat/test-data-source-footer.R')"
```

Expected: ERROR "cannot open file 'server_helpers.R'" (file doesn't exist yet) or "could not find function 'build_data_source_footer'". Both are RED.

```powershell
Rscript -e "library(testthat); test_file('tests/testthat/test-model-prediction.R')"
```

Expected: 1 new FAIL — `data_source` column not present in `generate_demo_weather_data()` output.

- [ ] **Step 3: Add data_source column to both generators**

In `shiny_app/model_prediction.R`, in `generate_city_weather_bike_data()` (line 479-531), inside the final `select()` call at line 518-527, add `data_source` to the kept columns AND add a `mutate(data_source = "openweather_live")` before the `select()`. Specifically, change:

```r
  cities_bike_pred <- cities_df %>%
    left_join(results) %>%
    select(
      CITY_ASCII,
      LNG, LAT,
      TEMPERATURE,
      HUMIDITY,
      BIKE_PREDICTION,
      BIKE_PREDICTION_LEVEL,
      LABEL,
      DETAILED_LABEL,
      FORECASTDATETIME
    )
```

to:

```r
  cities_bike_pred <- cities_df %>%
    left_join(results) %>%
    mutate(data_source = "openweather_live") %>%                            # B3: honest live-path source label
    select(
      CITY_ASCII,
      LNG, LAT,
      TEMPERATURE,
      HUMIDITY,
      BIKE_PREDICTION,
      BIKE_PREDICTION_LEVEL,
      LABEL,
      DETAILED_LABEL,
      FORECASTDATETIME,
      data_source                                                            # B3: carried through to consumers
    )
```

In `generate_demo_weather_data()`, after the final `mutate()` that produces `LABEL`/`DETAILED_LABEL` (around model_prediction.R:589-620), add a `mutate(data_source = "demo_fallback")` at the very end of the pipeline before the implicit return.

Locate the closing `%>%` of the last mutate and append:

```r
    mutate(data_source = "demo_fallback")                                    # B3: honest demo-path source label
```

- [ ] **Step 4: Create server_helpers.R with the two helpers**

Create new file `shiny_app/server_helpers.R`:

```r
# ============================================================================
# server_helpers.R — Pure helper functions consumed by server.R
# Extracted so testthat can unit-test them without spinning up a Shiny session.
# Each function takes plain inputs and returns plain strings.
# ============================================================================

# ── B3: Footer message based on live/demo split across cities ─────────────────
# Input:  df with CITY_ASCII and data_source columns
# Output: character string suitable for renderUI (HTML-safe plain text)
build_data_source_footer <- function(df) {
  if (nrow(df) == 0L || !"data_source" %in% colnames(df)) {                 # defensive: empty or malformed input
    return("Powered by OpenWeather API")                                    # fall back to historical default
  }
  per_city <- unique(df[, c("CITY_ASCII", "data_source")])                  # one row per city
  total    <- nrow(per_city)                                                # total cities in current frame
  demo_n   <- sum(per_city$data_source == "demo_fallback")                  # cities currently on fallback
  if (demo_n == 0L) return("Powered by OpenWeather API")                    # all live → simple claim
  if (demo_n == total) {                                                    # all demo → actionable hint
    return("Demo data — OPENWEATHER_KEY not set; live forecasts disabled")
  }
  sprintf("Powered by OpenWeather API — %d of %d cities on demo fallback",
          demo_n, total)                                                    # mixed-state count
}

# ── B3: Per-chart subtitle line indicating data source for the displayed city ─
# Input:  src       — "openweather_live" or "demo_fallback"
#         build_time — POSIXct timestamp (chart build moment, UTC-format applied)
# Output: character string for ggplot subtitle (single line)
build_data_source_subtitle_line <- function(src, build_time) {
  if (identical(src, "openweather_live")) {
    return(sprintf("Source: OpenWeather, refreshed %s UTC",
                   format(build_time, "%H:%M", tz = "UTC")))                # formatted HH:MM UTC
  }
  "Source: Demo fallback — set OPENWEATHER_KEY in .Renviron and restart"
}
```

- [ ] **Step 5: Wire helpers into server.R**

In `shiny_app/server.R`, near the top (just after the `library()` block), add:

```r
source("server_helpers.R")                                                  # B3: pure helpers, unit-tested separately
```

In `build_temp_chart` (server.R:517+) and `build_bike_chart` (server.R:542+), modify the `labs(...)` call's `subtitle` argument from:

```r
        subtitle = paste0("Next 24 Hours  •  ", fmt_start, " → ", fmt_end),
```

to:

```r
        subtitle = paste(
          paste0("Next 24 Hours  •  ", fmt_start, " → ", fmt_end),
          build_data_source_subtitle_line(unique(df$data_source)[1], Sys.time()),
          sep = "\n"                                                        # 2-line subtitle
        ),
```

Add the `output$data_source_footer` renderUI in the server function, near other renderUI blocks (anywhere logical — suggested location: just after the `city_weather_bike_df <- reactive(...)` block around server.R:140):

```r
  # ── B3: Reactive footer — reflects live/demo split each weather refresh ────
  output$data_source_footer <- renderUI({                                    # called from ui.R footer slot
    df <- city_weather_bike_df()                                             # () — reactive; re-runs on weather refresh
    HTML(build_data_source_footer(df))                                       # HTML() safe: helper returns plain text
  })
```

- [ ] **Step 6: Update ui.R footer**

In `shiny_app/ui.R:388-391`, change:

```r
                        tags$div(class = "dash-footer",
                                 "Powered by OpenWeather API", tags$br(),
                                 "IBM Data Analytics Capstone"
                        )
```

to:

```r
                        tags$div(class = "dash-footer",
                                 uiOutput("data_source_footer", inline = TRUE), tags$br(),  # B3: reactive source claim
                                 "IBM Data Analytics Capstone"
                        )
```

- [ ] **Step 7: Run tests; expect GREEN**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: All previous tests pass + 7 new tests pass (4 footer helper + 1 demo data_source + 2 subtitle helper). Test count moves 37 → 44, assertions 63 → ~74.

- [ ] **Step 8: Manual smoke check in browser**

In VS Code R terminal: `shiny::runApp("shiny_app")`. Open Live Map tab. Confirm footer reads `"Powered by OpenWeather API"` if key set, or `"Demo data — OPENWEATHER_KEY not set..."` if key missing. Open temp/bike charts via a city marker — confirm subtitle shows two lines, second line contains `"Source: OpenWeather, refreshed HH:MM UTC"` (live) or `"Source: Demo fallback..."` (demo).

- [ ] **Step 9: Commit**

```powershell
git add shiny_app/model_prediction.R shiny_app/server.R shiny_app/server_helpers.R shiny_app/ui.R tests/testthat/test-model-prediction.R tests/testthat/test-data-source-footer.R
git commit -m "feat(server): data_source column + reactive footer + chart subtitle source line (Sprint 3 B3)"
```

---

## Task 2: C4 — Per-city quantile thresholds for demand levels

**Files:**
- Modify: `shiny_app/model_prediction.R:451-462` (replace `calculate_bike_prediction_level` body with quantile logic)
- Modify: `shiny_app/model_prediction.R:503` and `:509` (wrap level call in `group_by(CITY_ASCII)`)
- Modify: `shiny_app/model_prediction.R` `generate_demo_weather_data` (wrap level call in `group_by(CITY_ASCII)`)
- Modify: `shiny_app/ui.R:347-362` (legend wording)
- Modify: `tests/testthat/test-model-prediction.R` (add quantile distribution tests)

- [ ] **Step 1: Write failing tests for quantile distribution**

Append to `tests/testthat/test-model-prediction.R`:

```r
test_that("calculate_bike_prediction_level returns 3 small / 2 medium / 3 large on linear 1..8", {
  out <- calculate_bike_prediction_level(1:8)                              # R default type=7 quantile
  expect_equal(sum(out == "small"),  3L)                                   # q33 = 3.31 → {1,2,3}
  expect_equal(sum(out == "medium"), 2L)                                   # (3.31, 5.69] → {4,5}
  expect_equal(sum(out == "large"),  3L)                                   # > 5.69 → {6,7,8}
})

test_that("calculate_bike_prediction_level is monotonically non-decreasing across sorted input", {
  out   <- calculate_bike_prediction_level(1:8)
  order <- c("small" = 1L, "medium" = 2L, "large" = 3L)                    # rank levels
  ranks <- order[out]
  expect_true(all(diff(ranks) >= 0L))                                       # no rank ever drops as inputs rise
})

test_that("calculate_bike_prediction_level returns all-small when all predictions equal (degenerate quantile)", {
  out <- calculate_bike_prediction_level(rep(500, 8))                      # all equal → q33 == q67 == 500
  expect_true(all(out == "small"))                                          # all values <= q33 by definition
})

test_that("calculate_bike_prediction_level handles NA gracefully", {
  out <- calculate_bike_prediction_level(c(1:7, NA))                       # one NA
  expect_equal(length(out), 8L)                                             # one output per input
  expect_true(is.na(out[8]))                                                # NA in → NA out
})
```

- [ ] **Step 2: Run tests; expect FAIL**

```powershell
Rscript -e "library(testthat); test_file('tests/testthat/test-model-prediction.R')"
```

Expected: 4 new FAILs — current implementation uses global 1000/3000 thresholds, so 1:8 yields all "small".

- [ ] **Step 3: Replace `calculate_bike_prediction_level` body**

In `shiny_app/model_prediction.R:451-462`, replace the entire function body:

```r
calculate_bike_prediction_level <- function(predictions) {                  # C4: per-group tertile split
  q33 <- quantile(predictions, 0.33, na.rm = TRUE)                          # 33rd percentile of input
  q67 <- quantile(predictions, 0.67, na.rm = TRUE)                          # 67th percentile of input
  dplyr::case_when(                                                         # vectorised; preserves NA
    is.na(predictions)     ~ NA_character_,                                 # NA in → NA out
    predictions <= q33     ~ "small",                                       # bottom tertile
    predictions <= q67     ~ "medium",                                      # middle tertile
    TRUE                   ~ "large"                                        # top tertile
  )
}
```

- [ ] **Step 4: Apply per-city in generate_city_weather_bike_data**

In `shiny_app/model_prediction.R`, both the `if (use_fastapi)` branch and the `else` branch (lines 493-510) currently call `calculate_bike_prediction_level(BIKE_PREDICTION)` at the end of a single ungrouped `mutate`. Wrap each in `group_by(CITY_ASCII)` so quantiles are city-local. Change:

```r
    results <- weather_df %>%
      group_by(CITY_ASCII) %>%
      group_modify(~ { ... }) %>%
      ungroup() %>%
      mutate(BIKE_PREDICTION_LEVEL = calculate_bike_prediction_level(BIKE_PREDICTION))
```

to:

```r
    results <- weather_df %>%
      group_by(CITY_ASCII) %>%
      group_modify(~ { ... }) %>%
      ungroup() %>%
      group_by(CITY_ASCII) %>%                                              # C4: regroup so tertiles are city-local
      mutate(BIKE_PREDICTION_LEVEL = calculate_bike_prediction_level(BIKE_PREDICTION)) %>%
      ungroup()
```

And in the `else` branch:

```r
    results <- weather_df %>%
      mutate(BIKE_PREDICTION = predict_bike_demand(...)) %>%
      group_by(CITY_ASCII) %>%                                              # C4: city-local quantiles
      mutate(BIKE_PREDICTION_LEVEL = calculate_bike_prediction_level(BIKE_PREDICTION)) %>%
      ungroup()
```

- [ ] **Step 5: Apply per-city in generate_demo_weather_data**

In `shiny_app/model_prediction.R`, in `generate_demo_weather_data()`, find the final pipeline that calls `calculate_bike_prediction_level()` (around line 595 in current code). Wrap in `group_by(CITY_ASCII)` similarly:

```r
  df %>%
    group_by(CITY_ASCII) %>%                                                # C4: city-local quantiles for demo path too
    mutate(
      BIKE_PREDICTION       = predict_bike_demand(
        TEMPERATURE, HUMIDITY, WIND_SPEED, VISIBILITY, SEASONS, HOURS
      ),
      BIKE_PREDICTION_LEVEL = calculate_bike_prediction_level(BIKE_PREDICTION),
      LABEL                 = paste0(...),
      DETAILED_LABEL        = paste0(...)
    ) %>%
    ungroup() %>%
    mutate(data_source = "demo_fallback")                                   # B3 (from Task 1) — preserved
```

- [ ] **Step 6: Update legend wording in ui.R**

In `shiny_app/ui.R:347-362`, replace the three legend rows' detail spans (the parts after `tags$strong("Low/Medium/High"), " — peak ..."`):

```r
                        tags$div(class = "dash-card",
                                 tags$h5("Demand Level"),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-green"),
                                          tags$div(tags$strong("Low"), " — bottom third of this city's 24h forecast")
                                 ),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-yellow"),
                                          tags$div(tags$strong("Medium"), " — middle third of this city's 24h forecast")
                                 ),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-red"),
                                          tags$div(tags$strong("High"), " — top third of this city's 24h forecast")
                                 )
                        ),
```

- [ ] **Step 7: Run tests; expect GREEN**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: All previous tests pass + 4 new tests pass. Total now ~48 tests / ~78 assertions.

- [ ] **Step 8: Manual smoke check**

Restart Shiny. On Live Map, eyeball marker colour distribution per city — each city should now show ~3 green / 2 yellow / 3 red across its 24h horizon, not always-red (NYC) or always-green (Seoul). Legend reads "bottom/middle/top third of this city's 24h forecast".

- [ ] **Step 9: Commit**

```powershell
git add shiny_app/model_prediction.R shiny_app/ui.R tests/testthat/test-model-prediction.R
git commit -m "feat(model_prediction): per-city quantile thresholds for demand levels (Sprint 3 C4)"
```

---

## Task 3: C5 — Operator alert rewrite (unit-mismatched ratio → zero-bike % thresholds)

**Files:**
- Modify: `shiny_app/server.R` (top of server function: add 3 named constants; replace alert logic block at lines 797-825 with helper call)
- Modify: `shiny_app/server_helpers.R` (add `compute_operator_alert_level()` pure helper)
- Create: `tests/testthat/test-operator-alert.R`

- [ ] **Step 1: Write failing tests for alert helper**

Create new file `tests/testthat/test-operator-alert.R`:

```r
library(testthat)
library(rprojroot)
proj_root <- find_root(has_file("renv.lock"))
setwd(file.path(proj_root, "shiny_app"))

source("server_helpers.R")                                                  # helper module from Task 1

# Thresholds the helper is parameterised on (mirrored from server.R constants):
RED_PCT   <- 0.25                                                           # red:   ≥25% stations have zero bikes
AMBER_PCT <- 0.10                                                           # amber: ≥10% stations have zero bikes
FILL_PCT  <- 0.20                                                           # amber: fleet fill rate <20%

test_that("returns 'red' when zero-bike fraction meets the 25% threshold", {
  out <- compute_operator_alert_level(
    n_stations         = 100L,
    n_empty_stations   = 25L,                                               # exactly 25%
    total_bikes        = 500L,
    total_capacity     = 1000L,                                             # 50% fill — not amber by itself
    red_pct = RED_PCT, amber_pct = AMBER_PCT, fill_pct = FILL_PCT
  )
  expect_equal(out, "red")
})

test_that("returns 'red' when zero-bike fraction exceeds 25%", {
  out <- compute_operator_alert_level(100L, 26L, 500L, 1000L,
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "red")
})

test_that("returns 'amber' when zero-bike fraction meets 10% but not 25%", {
  out <- compute_operator_alert_level(100L, 10L, 500L, 1000L,
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "amber")
})

test_that("returns 'amber' when fill rate drops below 20% even with few empty stations", {
  out <- compute_operator_alert_level(100L, 5L, 150L, 1000L,                # 15% fill, 5% empty
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "amber")
})

test_that("returns 'amber' at fill rate exactly 19% (just below threshold)", {
  out <- compute_operator_alert_level(100L, 0L, 190L, 1000L,
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "amber")
})

test_that("returns 'green' when fill rate at threshold (20%) and zero-bike under 10%", {
  out <- compute_operator_alert_level(100L, 5L, 200L, 1000L,                # 20% fill, 5% empty
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "green")
})

test_that("returns 'green' on healthy fleet", {
  out <- compute_operator_alert_level(100L, 3L, 600L, 1000L,                # 60% fill, 3% empty
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "green")
})

test_that("handles zero capacity edge case without divide-by-zero", {
  out <- compute_operator_alert_level(0L, 0L, 0L, 0L,
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "red")                                                  # no fleet → critical by convention
})
```

- [ ] **Step 2: Run tests; expect FAIL**

```powershell
Rscript -e "library(testthat); test_file('tests/testthat/test-operator-alert.R')"
```

Expected: ERROR "could not find function 'compute_operator_alert_level'". RED confirmed.

- [ ] **Step 3: Add helper to server_helpers.R**

Append to `shiny_app/server_helpers.R`:

```r
# ── C5: Operator alert level based on snapshot state (no forecast comparison) ─
# Inputs (all integers/numerics):
#   n_stations       — total stations in the city
#   n_empty_stations — stations with zero bikes available
#   total_bikes      — sum of bikes available across all stations
#   total_capacity   — sum of dock capacity across all stations
#   red_pct, amber_pct — zero-bike fraction thresholds
#   fill_pct         — fleet fill-rate threshold below which amber fires
# Output: one of "red", "amber", "green"
compute_operator_alert_level <- function(n_stations, n_empty_stations,
                                          total_bikes, total_capacity,
                                          red_pct, amber_pct, fill_pct) {
  if (n_stations == 0L || total_capacity == 0L) return("red")               # degenerate: no fleet → critical
  zero_frac <- n_empty_stations / n_stations                                # fraction of stations with 0 bikes
  fill_frac <- total_bikes / total_capacity                                 # fleet-wide fill rate
  if (zero_frac >= red_pct)                          return("red")          # critical: many empty stations
  if (zero_frac >= amber_pct || fill_frac < fill_pct) return("amber")       # warning: either condition
  "green"                                                                   # healthy
}
```

- [ ] **Step 4: Add named constants to server.R**

In `shiny_app/server.R`, near the top (just after the existing `source()` line for server_helpers.R added in Task 1), add:

```r
# ── C5: Operator alert thresholds (tune after one week of live observation) ──
OP_ALERT_RED_ZERO_PCT    <- 0.25                                            # red:   ≥25% stations empty
OP_ALERT_AMBER_ZERO_PCT  <- 0.10                                            # amber: ≥10% stations empty
OP_ALERT_AMBER_FILL_PCT  <- 0.20                                            # amber: fleet fill <20%
```

- [ ] **Step 5: Replace the alert reactive's if/elseif/else block**

In `shiny_app/server.R`, the block at lines 797-825 (starting with `ratio <- if (total > 0) peak / total else Inf` and ending with the `else` block setting "Supply Adequate") must be replaced. Find the variables `n` (total stations), `total` (total bikes available), and add a calculation for `total_capacity` from the same `gbfs` reactive. Specifically, replace the whole block from `ratio <- ...` through the closing `}` of the final else:

```r
    # ── C5: Compute fleet-state alert level (snapshot-based, not forecast-based) ──
    total_capacity <- sum(gbfs$CAPACITY %||% 0L, na.rm = TRUE)              # %||% from gbfs_client.R, default 0
    alert_level <- compute_operator_alert_level(
      n_stations       = n,
      n_empty_stations = empty,
      total_bikes      = total,
      total_capacity   = total_capacity,
      red_pct   = OP_ALERT_RED_ZERO_PCT,
      amber_pct = OP_ALERT_AMBER_ZERO_PCT,
      fill_pct  = OP_ALERT_AMBER_FILL_PCT
    )
    if (alert_level == "red") {                                             # critical: ≥25% stations empty
      panel_class <- "panel-danger"
      icon_glyph  <- "glyphicon-warning-sign"
      alert_title <- "Critical Supply Shortage"
      alert_body  <- paste0(
        round(empty / n * 100), "% of stations (", empty, " of ", n,
        ") have zero bikes. Immediate rebalancing required. ",
        "24h peak demand forecast: ", scales::comma(peak), " bikes — for capacity planning context."
      )
    } else if (alert_level == "amber") {                                    # warning: ≥10% empty OR <20% fill
      panel_class <- "panel-warning"
      icon_glyph  <- "glyphicon-exclamation-sign"
      alert_title <- "Low Supply Warning"
      fill_pct_disp <- if (total_capacity > 0L) round(total / total_capacity * 100) else 0L
      alert_body  <- paste0(
        round(empty / n * 100), "% of stations empty; fleet fill ",
        fill_pct_disp, "%. Proactive rebalancing advised. ",
        "24h peak demand forecast: ", scales::comma(peak), " bikes — for capacity planning context."
      )
    } else {                                                                # green: healthy
      panel_class <- "panel-success"
      icon_glyph  <- "glyphicon-ok-sign"
      alert_title <- "Supply Adequate"
      fill_pct_disp <- if (total_capacity > 0L) round(total / total_capacity * 100) else 0L
      alert_body  <- paste0(
        "Fleet is well-positioned. ", fill_pct_disp, "% fill rate, ",
        empty, " of ", n, " stations empty. ",
        "24h peak demand forecast: ", scales::comma(peak), " bikes — for capacity planning context."
      )
    }
```

- [ ] **Step 6: Run tests; expect GREEN**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: all previous + 8 new operator-alert tests pass. Total ~56 tests / ~86 assertions.

- [ ] **Step 7: Manual smoke check**

Restart Shiny. Operator tab: cycle through all 6 cities. Alert level should vary based on actual fleet state — e.g., Seoul (typically high availability) should show green; New York during commute hours might show amber. None should be uniformly "Critical Supply Shortage" all the time. Panel body should mention "24h peak demand forecast: X bikes — for capacity planning context".

- [ ] **Step 8: Commit**

```powershell
git add shiny_app/server.R shiny_app/server_helpers.R tests/testthat/test-operator-alert.R
git commit -m "fix(server): rewrite operator alert to zero-bike-station thresholds (Sprint 3 C5)"
```

---

## Task 4: C1 — Engine indicator on bike demand chart subtitle

**Files:**
- Modify: `shiny_app/server.R` `build_bike_chart` (append engine line to subtitle; read USE_FASTAPI env once)
- Create: `tests/testthat/test-build-bike-chart.R`

- [ ] **Step 1: Write failing tests for engine indicator**

Create new file `tests/testthat/test-build-bike-chart.R`:

```r
library(testthat)
library(withr)                                                              # for env-var isolation
library(rprojroot)
proj_root <- find_root(has_file("renv.lock"))
setwd(file.path(proj_root, "shiny_app"))

# We need a partial server context to define build_bike_chart.
# build_bike_chart lives inside the server function, so we re-define a thin
# test harness version here that mirrors the production signature + behaviour
# only for the engine-indicator subtitle line. Production code is verified
# manually post-implementation; the helper-extracted logic gets unit-tested.

source("server_helpers.R")                                                  # provides build_engine_subtitle_line() (added in Task 4)

test_that("build_engine_subtitle_line returns FastAPI label when USE_FASTAPI=true", {
  with_envvar(c(USE_FASTAPI = "true"), {                                    # isolate env var to this block
    out <- build_engine_subtitle_line()
    expect_equal(out, "Engine: FastAPI Random Forest")
  })
})

test_that("build_engine_subtitle_line returns local label when USE_FASTAPI=false", {
  with_envvar(c(USE_FASTAPI = "false"), {
    out <- build_engine_subtitle_line()
    expect_equal(out, "Engine: Local linear regression")
  })
})

test_that("build_engine_subtitle_line returns local label when USE_FASTAPI unset", {
  with_envvar(c(USE_FASTAPI = NA), {                                        # NA in with_envvar unsets the variable
    out <- build_engine_subtitle_line()
    expect_equal(out, "Engine: Local linear regression")
  })
})

test_that("build_engine_subtitle_line returns local label when USE_FASTAPI has unexpected value", {
  with_envvar(c(USE_FASTAPI = "yes"), {                                     # anything not exactly "true" → local
    out <- build_engine_subtitle_line()
    expect_equal(out, "Engine: Local linear regression")
  })
})
```

- [ ] **Step 2: Run tests; expect FAIL**

```powershell
Rscript -e "library(testthat); test_file('tests/testthat/test-build-bike-chart.R')"
```

Expected: ERROR "could not find function 'build_engine_subtitle_line'". RED.

- [ ] **Step 3: Add helper to server_helpers.R**

Append to `shiny_app/server_helpers.R`:

```r
# ── C1: Engine indicator line for bike-demand chart subtitle ─────────────────
# Reads USE_FASTAPI env var; returns appropriate engine label. No RMSE in UI.
build_engine_subtitle_line <- function() {
  if (identical(Sys.getenv("USE_FASTAPI", unset = "false"), "true")) {
    return("Engine: FastAPI Random Forest")
  }
  "Engine: Local linear regression"
}
```

- [ ] **Step 4: Wire helper into build_bike_chart**

In `shiny_app/server.R` `build_bike_chart` function (around line 542), find the existing `subtitle = paste(...)` (which after Task 1 already contains 2 lines: time + source). Append the engine line as a 3rd subtitle line. Change:

```r
        subtitle = paste(
          paste0("Next 24 Hours  •  ", fmt_start, " → ", fmt_end),
          build_data_source_subtitle_line(unique(df$data_source)[1], Sys.time()),
          sep = "\n"
        ),
```

to:

```r
        subtitle = paste(
          paste0("Next 24 Hours  •  ", fmt_start, " → ", fmt_end),
          build_data_source_subtitle_line(unique(df$data_source)[1], Sys.time()),
          build_engine_subtitle_line(),                                     # C1: engine indicator
          sep = "\n"                                                        # 3-line subtitle
        ),
```

- [ ] **Step 5: Run tests; expect GREEN**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: all previous + 4 new engine-line tests pass. Total ~60 tests / ~90 assertions.

- [ ] **Step 6: Manual smoke check**

Restart Shiny with `USE_FASTAPI=true` in `.Renviron`. Open bike demand chart for any city. Confirm chart subtitle has 3 lines, third reads `"Engine: FastAPI Random Forest"`. Restart with `USE_FASTAPI=false`. Confirm third line reads `"Engine: Local linear regression"`.

- [ ] **Step 7: Commit**

```powershell
git add shiny_app/server.R shiny_app/server_helpers.R tests/testthat/test-build-bike-chart.R
git commit -m "feat(server): engine indicator on bike demand chart subtitle (Sprint 3 C1)"
```

---

## Task 5: C2 — Humidity chart smoother (drop overfit poly(4))

**Files:**
- Modify: `shiny_app/server.R:566-588` (`build_humidity_chart`)

*No new tests — chart formula change is visual; geom_smooth method/formula isn't usefully unit-testable. Manual eyeball is the verification.*

- [ ] **Step 1: Update build_humidity_chart**

In `shiny_app/server.R:570-577`, change:

```r
      geom_smooth(method  = "lm",
                  formula = y ~ poly(x, 4),
                  color   = "red",
                  fill    = "lightpink",
                  alpha   = 0.3) +
      labs(
        title    = paste("Humidity vs Demand —", city),
        subtitle = "24-Hour forecast window",
```

to:

```r
      geom_smooth(method  = "lm",                                           # C2: linear; 8 points don't support poly(4)
                  color   = "red",
                  fill    = "lightpink",
                  alpha   = 0.3) +
      labs(
        title    = paste("Humidity vs Demand —", city),
        subtitle = "Linear trend across 8 forecast slots",                   # C2: subtitle reflects fit honestly
```

- [ ] **Step 2: Run full test suite; expect no regression**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: all tests still pass. No new tests added.

- [ ] **Step 3: Manual smoke check**

Restart Shiny. Live Map → click city marker → humidity chart should show a single straight line (not a wavy 4th-order curve). Subtitle should read "Linear trend across 8 forecast slots".

- [ ] **Step 4: Commit**

```powershell
git add shiny_app/server.R
git commit -m "refactor(server): replace humidity poly(4) smoother with linear (Sprint 3 C2)"
```

---

## Task 6: C3 — Derive stat-card counts (kill hardcoded "6"/"24")

**Files:**
- Modify: `shiny_app/ui.R:337,341` (replace literals with `textOutput`)
- Modify: `shiny_app/server.R` (add 2 `renderText` outputs)
- Create: `tests/testthat/test-stat-card.R`

- [ ] **Step 1: Write failing tests for stat-card helper**

Create new file `tests/testthat/test-stat-card.R`:

```r
library(testthat)
library(rprojroot)
proj_root <- find_root(has_file("renv.lock"))
setwd(file.path(proj_root, "shiny_app"))

source("server_helpers.R")                                                  # provides count_unique_cities()

test_that("count_unique_cities returns 6 for a 6-city frame", {
  df <- data.frame(CITY_ASCII = c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC"))
  expect_equal(count_unique_cities(df), 6L)
})

test_that("count_unique_cities deduplicates within a city (8-slot forecast)", {
  df <- data.frame(CITY_ASCII = rep(c("Seoul", "London"), each = 8L))      # 16 rows, 2 cities
  expect_equal(count_unique_cities(df), 2L)
})

test_that("count_unique_cities returns 0 for empty input", {
  df <- data.frame(CITY_ASCII = character(0))
  expect_equal(count_unique_cities(df), 0L)
})

test_that("FORECAST_HOURS_CONSTANT equals 24", {
  expect_equal(FORECAST_HOURS_CONSTANT, "24")                               # documented constant, not data-derived
})
```

- [ ] **Step 2: Run tests; expect FAIL**

```powershell
Rscript -e "library(testthat); test_file('tests/testthat/test-stat-card.R')"
```

Expected: 4 FAILs / errors. RED.

- [ ] **Step 3: Add helper + constant to server_helpers.R**

Append to `shiny_app/server_helpers.R`:

```r
# ── C3: Stat-card helpers — derived city count + documented forecast horizon ──
count_unique_cities <- function(df) {                                       # used by renderText for stat_cities
  if (nrow(df) == 0L) return(0L)
  length(unique(df$CITY_ASCII))
}

# Forecast horizon is genuinely fixed: OpenWeather 5-day/3-hour API yields
# 8 slots × 3 hours = 24 hours. Documented as a string for direct render.
FORECAST_HOURS_CONSTANT <- "24"
```

- [ ] **Step 4: Update ui.R stat card**

In `shiny_app/ui.R:336-344`, replace the hardcoded values:

```r
                                 tags$div(class = "stat-row",
                                          tags$div(class = "stat-box stat-cities",
                                                   tags$div(class = "stat-num", textOutput("stat_cities", inline = TRUE)),  # C3
                                                   tags$div(class = "stat-lbl", "Cities")
                                          ),
                                          tags$div(class = "stat-box stat-days",
                                                   tags$div(class = "stat-num", textOutput("stat_hours", inline = TRUE)),  # C3
                                                   tags$div(class = "stat-lbl", "Hr Forecast")
                                          )
                                 )
```

- [ ] **Step 5: Add renderText outputs in server.R**

In `shiny_app/server.R`, near the other simple outputs (suggested location: right next to the `data_source_footer` renderUI added in Task 1):

```r
  # ── C3: Stat-card derived counts ────────────────────────────────────────────
  output$stat_cities <- renderText({ count_unique_cities(city_weather_bike_df()) })   # data-driven city count
  output$stat_hours  <- renderText({ FORECAST_HOURS_CONSTANT })                       # documented constant
```

- [ ] **Step 6: Run tests; expect GREEN**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: all previous + 4 new stat-card tests pass. Total ~64 tests / ~94 assertions.

- [ ] **Step 7: Manual smoke check**

Restart Shiny. Live Map sidebar Coverage card should still show "6" cities + "24" Hr Forecast. Visual is unchanged — but the numbers are now data-driven; adding a city to `selected_cities.csv` would automatically update the "6" to "7".

- [ ] **Step 8: Commit**

```powershell
git add shiny_app/ui.R shiny_app/server.R shiny_app/server_helpers.R tests/testthat/test-stat-card.R
git commit -m "refactor(ui): derive stat-card city/forecast counts (Sprint 3 C3)"
```

---

## Task 7: C6 — CSV download metadata + timestamped filename

**Files:**
- Modify: `shiny_app/server.R:963-979` (downloadHandler `filename` and `content` callbacks)
- Modify: `shiny_app/server_helpers.R` (add `build_csv_filename()` + `build_csv_header_block()`)
- Create: `tests/testthat/test-download-handler.R`

- [ ] **Step 1: Write failing tests for CSV helpers**

Create new file `tests/testthat/test-download-handler.R`:

```r
library(testthat)
library(rprojroot)
proj_root <- find_root(has_file("renv.lock"))
setwd(file.path(proj_root, "shiny_app"))

source("server_helpers.R")                                                  # provides the 2 CSV helpers

test_that("build_csv_filename lowercases and dash-joins city + UTC stamp", {
  out <- build_csv_filename("New York", as.POSIXct("2026-05-27 14:30:00", tz = "UTC"))
  expect_equal(out, "bike-demand-forecast-new-york-20260527-1430.csv")
})

test_that("build_csv_filename handles multi-word city with mixed case", {
  out <- build_csv_filename("Washington DC", as.POSIXct("2026-05-27 09:05:00", tz = "UTC"))
  expect_equal(out, "bike-demand-forecast-washington-dc-20260527-0905.csv")
})

test_that("build_csv_filename handles single-word city", {
  out <- build_csv_filename("Seoul", as.POSIXct("2026-05-27 23:59:00", tz = "UTC"))
  expect_equal(out, "bike-demand-forecast-seoul-20260527-2359.csv")
})

test_that("build_csv_header_block returns 4 commented lines with metadata", {
  out <- build_csv_header_block(
    city        = "Paris",
    source      = "openweather_live",
    fmt_start   = "27 May 2026 14:00",
    fmt_end     = "28 May 2026 11:00",
    exported_at = as.POSIXct("2026-05-27 14:30:00", tz = "UTC")
  )
  lines <- strsplit(out, "\n", fixed = TRUE)[[1]]
  expect_equal(length(lines), 4L)                                           # exactly 4 header lines
  expect_match(lines[1], "^# Bike Demand 24h Forecast — exported 2026-05-27 14:30 UTC$")
  expect_match(lines[2], "^# City: Paris$")
  expect_match(lines[3], "^# Source: openweather_live$")
  expect_match(lines[4], "^# Forecast horizon: 27 May 2026 14:00 -> 28 May 2026 11:00$")
})

test_that("build_csv_header_block reports demo_fallback source verbatim", {
  out <- build_csv_header_block("Seoul", "demo_fallback", "now", "later",
                                 as.POSIXct("2026-05-27 00:00:00", tz = "UTC"))
  expect_match(out, "# Source: demo_fallback")                              # exact source label preserved
})
```

- [ ] **Step 2: Run tests; expect FAIL**

```powershell
Rscript -e "library(testthat); test_file('tests/testthat/test-download-handler.R')"
```

Expected: ERROR "could not find function 'build_csv_filename'" / 'build_csv_header_block'. RED.

- [ ] **Step 3: Add helpers to server_helpers.R**

Append to `shiny_app/server_helpers.R`:

```r
# ── C6: CSV download helpers ─────────────────────────────────────────────────
# Filename pattern: bike-demand-forecast-<city-slug>-<YYYYMMDD-HHMM>.csv (UTC)
build_csv_filename <- function(city, exported_at) {
  slug <- tolower(gsub("\\s+", "-", trimws(city)))                          # "Washington DC" → "washington-dc"
  stamp <- format(exported_at, "%Y%m%d-%H%M", tz = "UTC")                   # UTC timestamp YYYYMMDD-HHMM
  sprintf("bike-demand-forecast-%s-%s.csv", slug, stamp)
}

# Header block: 4 commented lines prepended to CSV body
build_csv_header_block <- function(city, source, fmt_start, fmt_end, exported_at) {
  paste(
    sprintf("# Bike Demand 24h Forecast — exported %s UTC",
            format(exported_at, "%Y-%m-%d %H:%M", tz = "UTC")),
    sprintf("# City: %s", city),
    sprintf("# Source: %s", source),
    sprintf("# Forecast horizon: %s -> %s", fmt_start, fmt_end),
    sep = "\n"
  )
}
```

- [ ] **Step 4: Update downloadHandler in server.R**

In `shiny_app/server.R:963-979`, replace the entire `output$download_forecast <- downloadHandler(...)` block:

```r
  output$download_forecast <- downloadHandler(                              # C6: timestamped filename + metadata header
    filename = function() {
      build_csv_filename(input$operator_city, Sys.time())                   # helper: UTC-stamped slug
    },
    content = function(file) {
      df <- operator_city_data()                                            # 8 forecast slots for selected city
      src <- if (nrow(df) > 0L && "data_source" %in% colnames(df)) df$data_source[1] else "unknown"
      w   <- forecast_window()                                              # reactive window strings
      header <- build_csv_header_block(                                     # helper: 4 commented lines
        city        = input$operator_city,
        source      = src,
        fmt_start   = w$fmt_start,
        fmt_end     = w$fmt_end,
        exported_at = Sys.time()
      )
      writeLines(header, con = file)                                        # write 4 header lines first
      df %>%                                                                # then append CSV body
        select(CITY_ASCII, FORECASTDATETIME, TEMPERATURE, HUMIDITY,
               WIND_SPEED, BIKE_PREDICTION, BIKE_PREDICTION_LEVEL) %>%
        write.table(file, sep = ",", row.names = FALSE,                    # append; header column row
                    append = TRUE, col.names = TRUE)
    }
  )
```

- [ ] **Step 5: Run tests; expect GREEN**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: all previous + 5 new download tests pass. Total ~69 tests / ~99 assertions.

- [ ] **Step 6: Manual smoke check**

Restart Shiny. Operator tab → select a city → click "Download 24h CSV". Open the downloaded file in a text editor. Confirm:
1. Filename matches pattern `bike-demand-forecast-<city>-YYYYMMDD-HHMM.csv` with UTC stamp.
2. First 4 lines begin with `#` and contain export timestamp, city, source, forecast horizon.
3. Line 5 is the CSV column header row (`"CITY_ASCII","FORECASTDATETIME",...`).
4. Lines 6+ are the 8 forecast slots.

- [ ] **Step 7: Commit**

```powershell
git add shiny_app/server.R shiny_app/server_helpers.R tests/testthat/test-download-handler.R
git commit -m "feat(server): timestamped CSV export with source metadata (Sprint 3 C6)"
```

---

## Task 8: Doc sync + v1.6.0 release

**Files:**
- Modify: `README.md` (Phase 7D/7E retrospectives; Quick Summary feature bullets; Known Limitations; v1.6.0 badge)
- Modify: `PROJECT-STATUS.md` (Sprint 3 priority row; ecosystem own-hash bump; v1.6.0 entry)
- Run: Pattern A-D sweep per CLAUDE.md Rule 12
- Tag: v1.6.0 GitHub release

- [ ] **Step 1: Full testthat suite confirmation**

```powershell
Rscript -e "library(testthat); test_dir('tests/testthat', reporter='summary')"
```

Expected: All tests pass (~69 tests / ~99 assertions).

- [ ] **Step 2: Manual end-to-end smoke test across all 4 tabs**

Run through `spec §5 manual smoke test` checklist:
1. Live path: confirm chart subtitles end with `"Source: OpenWeather, refreshed HH:MM UTC"` + engine line; footer reads `"Powered by OpenWeather API"`.
2. Demo path: rename `.Renviron`, restart, confirm subtitle/footer reflect demo state; map popups show demo flag.
3. Toggle `USE_FASTAPI`: engine indicator flips between FastAPI/Local labels.
4. Per-city thresholds: marker colour distribution varies within each city.
5. Operator alert: not uniformly red; reflects actual fleet state.
6. CSV download: 4 metadata header rows + UTC-stamped filename.

- [ ] **Step 3: Pattern A-D sweep on README + PROJECT-STATUS**

Run the four canonical staleness sweep commands per CLAUDE.md Rule 12 §Step 1.5:

```powershell
# Pattern A — count drift
$readmeFiles = git ls-files '*README*' 'PROJECT-STATUS.md'
Select-String -Path $readmeFiles -Pattern '[0-9]+ (cities|cit|packages?|jobs?|tests?|rows?|models?|files?)' -CaseSensitive
# Pattern B — pending-vs-done framing rot
Select-String -Path $readmeFiles -Pattern '(needs to|will be|to be added|pending)' -CaseSensitive
# Pattern C — Known Limitations cross-doc drift (manual diff)
# Pattern D — sections changed in this release
git diff v1.5.0..HEAD --stat -- $readmeFiles
```

Fix any drift found before commit. Specifically expect to find and fix:
- Old `Known Limitations` bullets referencing the unit-mismatched operator alert (now fixed by C5)
- Old `Known Limitations` bullets referencing hardcoded city/forecast counts (now fixed by C3)
- Test count claims `36/62` or `37/63` (now ~69/99)
- Phase status labels for Phase 7D/7E

- [ ] **Step 4: Update README.md**

Make these edits (verify exact line locations with `git grep` first):
- Phase 7D (Operator alert) retrospective: note rewrite to zero-bike-% thresholds with configurable constants
- Phase 7E (CSV download) retrospective: note metadata header + UTC timestamped filename
- Quick Summary feature bullets: add 3 lines for "Per-city demand thresholds", "Engine indicator on bike chart", "Honest end-to-end data-source labelling (chart + footer + popup + CSV)"
- Known Limitations: **remove** entries about unit-mismatched operator alert (fixed by C5); **remove** entries about hardcoded city/forecast counts (fixed by C3)
- v1.6.0 badge: bump `In_Development` → `Released` if currently shown as in-dev
- Test count claims: update to actual current numbers (annotate historical-block counts per Pattern A historical-block exception if needed)

- [ ] **Step 5: Update PROJECT-STATUS.md**

- Sprint 3 priority row: strike through with completion date `2026-05-27` and commit range
- Ecosystem ROW own-hash: bump to HEAD
- v1.6.0 entry under "Released": add Sprint 3 commits + feature lines
- Workstream B and C marked ✅ Done
- "Next move" prose: reframe from "Sprint 3 in design" to "v1.6.0 shipped; v1.7 planning"

- [ ] **Step 6: Commit doc sync**

```powershell
git add README.md PROJECT-STATUS.md
git commit -m "docs(sprint3): close v1.6.0 Dashboard Honesty Pass"
```

- [ ] **Step 7: Push all 8 commits to origin/main**

```powershell
git push origin main
```

- [ ] **Step 8: Verify CI green (Rule 10 Step 7)**

```powershell
gh run list --branch main --limit 1                                          # get latest run ID
gh run watch <run-id> --exit-status --interval 30                            # block until done; non-zero on failure
```

If CI fails: diagnose root cause (Rule 12 systematic debugging applies), fix, push again, verify final run.

- [ ] **Step 9: Tag v1.6.0 GitHub release**

```powershell
gh release create v1.6.0 --title "v1.6.0 — Dashboard Honesty Pass" --latest=legacy --notes "$(cat <<'EOF'
## 🚲 Bike Demand Prediction Dashboard — v1.6.0

Closes the cross-repo Dashboard Truth and Freshness initiative: every claim on the dashboard is now grounded in current data with explicit source attribution.

---

### What's included

**Workstream A — GCP Stream live again** (shipped via companion `bike-demand-ml-system` v3.1.0)
- Cloud Run `gbfs-poller` service polling GBFS every 5 minutes
- Cloud Scheduler `gbfs-poller-cron` triggers; BQ load jobs (free tier)
- 7-day partitioned `station_snapshots` table

**Workstream B — Forecast freshness + honest demo**
- Hourly `reactiveTimer` refreshes weather across all 6 cities mid-session
- Diurnal sinusoid in demo fallback (temperature ±5°C, humidity ±8 pp, bounded)
- Reactive `forecast_window` so map title rolls forward each hour
- Per-chart `data_source` line in subtitle; reactive footer adapts to live/mixed/demo state

**Workstream C — Honest claims + meaningful comparisons**
- Per-city quantile thresholds for demand level (no more "NYC always red, Seoul always green")
- Operator alert rewritten to snapshot-based zero-bike-station %: 25% red / 10% amber / <20% fill amber (tunable constants at top of `server.R`)
- Engine indicator on bike chart: FastAPI RF vs Local linear, driven by `USE_FASTAPI` env var
- Humidity smoother: linear (8 points don't support poly(4))
- Stat card city/forecast counts derived from data, not hardcoded
- CSV download: 4-row metadata header + UTC-timestamped filename

**Tests + CI**
| Item | Before | After |
|---|---|---|
| testthat tests | 37 | ~69 |
| testthat assertions | 63 | ~99 |
| CI jobs | 4 (lint, r-check, build, testthat) | 4 (unchanged) |

---

### Roadmap

- `v1.7` — Manual "Refresh Now" button on Live Map; shinytest2 reactive harness
- `v1.8` — Recruiter-narrative README rewrite + portfolio polish

---
EOF
)"
```

- [ ] **Step 10: Update workflow_status.md + PROJECT-STATUS.md own-hash for the release commit**

After v1.6.0 tag lands, the doc-sync commit's PROJECT-STATUS own-hash is one commit behind HEAD. Reconcile per cross-repo-sync-mandatory-closeout protocol:

```powershell
# Bump PROJECT-STATUS.md ecosystem own-hash row to current HEAD
# Edit the row; commit:
git add PROJECT-STATUS.md
git commit -m "docs(status): reconcile own hash post-v1.6.0 ship"
git push origin main
```

Update `C:\Users\deepa\.claude\projects\D--OneDrive-Developer-DataAnalytics-R-projects-bike-demand-prediction\memory\workflow_status.md`:
- Status line: `Sprint 3 SHIPPED 2026-05-27 — v1.6.0 Dashboard Honesty Pass released`
- Last Session block: 7 commits + 1 doc + 1 reconcile = 9 commits this session
- Next action: `v1.7 brainstorming (Manual Refresh button + shinytest2 reactive harness) OR portfolio polish phase`
- Re-entry command: `"start v1.7 brainstorming"` or `"resume bike demand"`

---

## Plan self-review

After writing this plan, scanned for:

1. **Spec coverage** — Each of 7 items in spec §2 has a dedicated Task:
   - B3 → Task 1 ✅
   - C4 → Task 2 ✅
   - C5 → Task 3 ✅
   - C1 → Task 4 ✅
   - C2 → Task 5 ✅
   - C3 → Task 6 ✅
   - C6 → Task 7 ✅
   - Doc sync + release → Task 8 ✅

2. **Placeholder scan** — No "TBD" / "TODO" / "implement later" in the plan. All code blocks are complete. Manual smoke check steps reference specific UI elements to inspect.

3. **Type consistency** — All helpers referenced in later tasks are defined in earlier tasks: `build_data_source_footer` + `build_data_source_subtitle_line` (T1), `compute_operator_alert_level` (T3), `build_engine_subtitle_line` (T4), `count_unique_cities` + `FORECAST_HOURS_CONSTANT` (T6), `build_csv_filename` + `build_csv_header_block` (T7). All live in `shiny_app/server_helpers.R` created in T1.

4. **TDD ordering** — Each task writes the failing test FIRST, runs to confirm RED, then implements, then runs to confirm GREEN. No task skips this cycle except T5 (humidity smoother — visual only, no unit test possible).

5. **File-path consistency** — Tests use `rprojroot::find_root(has_file("renv.lock"))` + `setwd("shiny_app")` pattern matching the existing `helper-workdir.R` convention from the v1.5 testthat work (see `feedback_session_workflow` + Sprint 1 plan task 3 testing pattern).
