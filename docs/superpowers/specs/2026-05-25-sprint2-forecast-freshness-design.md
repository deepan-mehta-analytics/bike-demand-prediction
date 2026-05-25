# Sprint 2 — Forecast Freshness + Honest Demo: Design Spec

**Date:** 2026-05-25
**Author:** Deepan Mehta
**Scope:** `bike-demand-prediction` (Shiny repo only)
**Predecessor:** Sprint 1 (Workstream A — Cloud Run GBFS poller) shipped 2026-05-25.
**Parent spec:** `docs/superpowers/specs/2026-05-24-dashboard-truth-and-freshness-design.md` §5

---

## 1. Problem statement

Two truth gaps remain after Sprint 1:

1. **Frozen weather data.** `server.R:122` assigns `city_weather_bike_df` as a plain R variable at session start. All charts, map titles, bike predictions, and rider recommendations derive from that single startup snapshot and never update. A session running for 1+ hours shows the wrong forecast window in every chart title and the wrong "best time to ride" recommendation.

2. **Flat temperature line in demo fallback.** When the OpenWeather key is absent or the API call fails, `generate_demo_weather_data()` builds a `city_params` tibble with one constant TEMPERATURE per city (Paris = 16.0°C, London = 14.0°C, etc.) and replicates it across all 8 forecast slots via `cross_join`. The chart renders as a perfectly horizontal line — visually obvious as synthetic data.

A minor labelling gap from Sprint 1: `ui.R:719` still says "Dataflow pipeline" after the pipeline was replaced by Cloud Run.

---

## 2. Design constraints

Inherited from the parent spec:
- GCP free tier (Rule 12) — no new paid services
- Direct-to-main workflow — no branching
- Yeti Bootswatch base styles untouched
- Preserve existing BQ schema and Shiny query logic (already correct post Sprint 1)

---

## 3. Changes

### 3.1 B1 — Make weather data reactive (server.R)

**Root cause:** Lines 119–244 of `server.R` run eagerly at session start. `city_weather_bike_df`, `fmt_start`, `fmt_end`, and `cities_max_bike` are all plain variables — computed once, never refreshed.

**Fix:** Replace the eager block with four reactive declarations. Every downstream consumer automatically re-runs when the timer fires.

#### New reactive block (replaces lines 119–244)

```r
# ── Hourly weather refresh ───────────────────────────────────────────────────
# Fires once at session start (Shiny evaluates all reactive dependencies
# immediately on first access) and then every 3,600,000 ms (1 hour).
weather_timer <- reactiveTimer(3600000)            # 1-hour invalidation signal

# ── Main weather + prediction frame ─────────────────────────────────────────
# Wraps test_weather_data_generation() — the same tryCatch wrapper that tries
# live OpenWeather first and falls back to generate_demo_weather_data() on any
# failure. Re-runs on every weather_timer() tick.
city_weather_bike_df <- reactive({
  weather_timer()                                  # declare timer dependency
  df <- test_weather_data_generation()             # live → demo fallback
  df %>%
    mutate(FORECASTDATETIME_DT = as.POSIXct(       # parse FORECASTDATETIME string
      FORECASTDATETIME,
      format = "%Y-%m-%d %H:%M:%S",
      tz     = "UTC"
    ))
})

# ── Forecast window strings ───────────────────────────────────────────────────
# Derived from city_weather_bike_df(). Returns a named list so callers can
# destructure: w <- forecast_window(); w$fmt_start; w$fmt_end.
forecast_window <- reactive({
  df    <- city_weather_bike_df()
  start <- min(df$FORECASTDATETIME_DT, na.rm = TRUE)  # earliest forecast slot
  end   <- max(df$FORECASTDATETIME_DT, na.rm = TRUE)  # latest forecast slot
  list(
    fmt_start = format(start, "%d %b %Y %H:%M"),       # e.g. "25 May 2026 14:00"
    fmt_end   = format(end,   "%d %b %Y %H:%M")        # e.g. "26 May 2026 11:00"
  )
})

# ── One-row-per-city summary ──────────────────────────────────────────────────
# Peak demand and map metadata per city. Derived from city_weather_bike_df().
# Consumers must call cities_max_bike() with parens.
cities_max_bike <- reactive({
  city_weather_bike_df() %>%
    group_by(CITY_ASCII, LAT, LNG) %>%
    summarise(
      BIKE_PREDICTION       = max(BIKE_PREDICTION, na.rm = TRUE),
      BIKE_PREDICTION_LEVEL = BIKE_PREDICTION_LEVEL[which.max(BIKE_PREDICTION)],
      LABEL                 = LABEL[which.max(BIKE_PREDICTION)],
      DETAILED_LABEL        = DETAILED_LABEL[which.max(BIKE_PREDICTION)],
      .groups               = "drop"
    )
})
```

#### Consumer updates — city_weather_bike_df

All four locations change from `city_weather_bike_df %>%` to `city_weather_bike_df() %>%`:

| Line | Context | Change |
|------|---------|--------|
| 334 | `renderLeaflet` fallback (city-centre marker) | Add `()` |
| 471 | `selected_city_data` reactive | Add `()` |
| 701 | `operator_city_data` reactive | Add `()` |
| 957 | `rider_city_data` reactive | Add `()` |

#### Consumer updates — cities_max_bike

Seven locations change from `cities_max_bike` to `cities_max_bike()`:

| Line | Context |
|------|---------|
| 299 | `renderLeaflet` overview map filter |
| 325 | `renderLeaflet` city setView |
| 417 | `renderPlot` for `city_compare_chart` |
| 432 | `renderPlot` for `city_compare_chart_modal` |
| 437 | `renderTable` city summary table |
| 865 | `renderLeaflet` operator city setView |
| 1190 | `renderLeaflet` rider city setView |

#### Consumer updates — fmt_start / fmt_end

`fmt_start` and `fmt_end` are referenced in three build functions and one `renderUI`. They become arguments passed by callers; the plain-string definitions at lines 236–237 are deleted.

**Build function signature changes:**

```r
# Before:
build_temp_chart    <- function(df)        { ... subtitle = paste0("...", fmt_start, ...) }
build_bike_chart    <- function(df)        { ... subtitle = paste0("...", fmt_start, ...) }
build_compare_chart <- function(df)        { ... subtitle = paste0(fmt_start, ...) }

# After:
build_temp_chart    <- function(df, fmt_start, fmt_end) { ... }  # same body, fmt_* now args
build_bike_chart    <- function(df, fmt_start, fmt_end) { ... }  # same body
build_compare_chart <- function(df, fmt_start, fmt_end) { ... }  # same body
```

**Call site updates** (all callers are already in reactive/render contexts):

| Line | Before | After |
|------|--------|-------|
| 260 | `paste0("...", fmt_start, ...)` inside `renderUI` | `{ w <- forecast_window(); paste0("...", w$fmt_start, ...) }` |
| 417 | `build_compare_chart(cities_max_bike)` | `{ w <- forecast_window(); build_compare_chart(cities_max_bike(), w$fmt_start, w$fmt_end) }` |
| 432 | `build_compare_chart(cities_max_bike)` | same pattern |
| 563 | `build_temp_chart(selected_city_data())` | `{ w <- forecast_window(); build_temp_chart(selected_city_data(), w$fmt_start, w$fmt_end) }` |
| 568 | `build_bike_chart(selected_city_data())` | `{ w <- forecast_window(); build_bike_chart(selected_city_data(), w$fmt_start, w$fmt_end) }` |

> **Implementation note:** `forecast_window()` is called at most once per render block — assign to a local `w <- forecast_window()` rather than calling it twice within the same block. Shiny caches reactive values within a single reactive flush so the extra call is free, but one local assignment is cleaner.

---

### 3.2 B2 — Sinusoidal demo fallback (model_prediction.R)

**Root cause:** `generate_demo_weather_data()` builds `city_params` with one TEMPERATURE/HUMIDITY per city, then `cross_join(city_params, slots)` replicates those constants across all 8 time slots.

**Fix:** One `mutate()` immediately after `cross_join`, using the `HOURS` column already present in `slots` (integer 0–23):

```r
# ── Cross-join: 6 cities × 8 slots = 48 rows ────────────────────────────────
df <- cross_join(city_params, slots)                    # every city paired with every slot

# ── Apply diurnal variation ───────────────────────────────────────────────────
# TEMPERATURE peaks ~14:00 UTC, troughs ~02:00 UTC, amplitude ±5°C.
# HUMIDITY is inversely correlated (drops when temperature peaks).
# Both are bounded to realistic ranges.
df <- df %>%
  mutate(
    TEMPERATURE = TEMPERATURE + 5 * sin((as.numeric(HOURS) - 6) * pi / 12),
    HUMIDITY    = pmin(95L, pmax(35L, HUMIDITY + as.integer(
                    round(-8 * sin((as.numeric(HOURS) - 6) * pi / 12)))))
  )
```

**Curve properties:**
- At HOURS = 14 (2 pm): `sin((14-6)*pi/12) = sin(2pi/3) ≈ +0.866` → +4.3°C above city base
- At HOURS = 2 (2 am): `sin((2-6)*pi/12) = sin(-pi/3) ≈ -0.866` → -4.3°C below city base
- Paris (base 16°C) ranges ≈ 11.7–20.3°C
- Humidity inversely tracks: Paris (base 68%) ranges ≈ 61–75% (bounded by `pmin/pmax`)

The formula uses `HOURS` (already integer; coerced to numeric for arithmetic). `TEMPERATURE` and `HUMIDITY` still carry the city base values after the cross-join — the mutate adds the diurnal delta in-place.

**Why this is honest:** The existing popup label already says `[Demo — Clear]` / `[Demo data — weather API key not set]`. The chart is clearly not claiming real weather. Sinusoidal variation makes the chart look like plausible synthetic weather rather than obviously fake constants. The honesty label is the signal; the shape is the plausibility.

**Test update required:** Add one assertion to `tests/testthat/test-model-prediction.R` inside the existing `generate_demo_weather_data` block:

```r
test_that("generate_demo_weather_data: TEMPERATURE varies across slots within a city", {
  result <- suppressMessages(generate_demo_weather_data())
  paris_temps <- result$TEMPERATURE[result$CITY_ASCII == "Paris"]   # 8 values for Paris
  expect_gt(length(unique(paris_temps)), 1L)                        # must not all be the same
})
```

This is the minimum regression guard: if the flat-line bug is reintroduced, this assertion fails.

---

### 3.3 Hint text fix (ui.R + bigquery_client.R)

Two one-line edits. No logic change.

**ui.R line 719:**
```r
# Before:
"Only cities polled by the Dataflow pipeline are available here.",
" Seoul and Paris are not in the GCP pipeline."

# After:
"Only cities polled by the Cloud Run GBFS poller are available here.",
" Seoul and Paris are not in the GCP pipeline."
```

**bigquery_client.R line 4:**
```r
# Before:
# the table written by the Dataflow GBFS streaming pipeline.

# After:
# the table written by the Cloud Run GBFS poller (gbfs-poller Cloud Run service).
```

---

## 4. Files touched — complete list

| File | Change | Scope |
|------|--------|-------|
| `shiny_app/server.R` | B1: replace lines 119–244 with 4 reactive declarations; update 4 `city_weather_bike_df` consumers; update 7 `cities_max_bike` consumers; update 3 build function signatures + 5 call sites; update 1 `renderUI` for map title | Major |
| `shiny_app/model_prediction.R` | B2: add diurnal mutate after `cross_join` in `generate_demo_weather_data()` | Minor |
| `shiny_app/ui.R` | Hint text: 1-line wording change in `bq_city` helper text | Trivial |
| `shiny_app/bigquery_client.R` | Hint text: 1-line comment update | Trivial |
| `tests/testthat/test-model-prediction.R` | B2: add 1 new `test_that` block asserting TEMPERATURE varies | Trivial |

---

## 5. What is NOT in scope

- B3 (data_source column + chart subtitle badges + reactive footer) — deferred to Sprint 3
- Workstream C (operator alert rewrite, per-city thresholds, engine indicator, CSV metadata) — Sprint 3
- shinytest2 reactive harness — Phase 8 backlog
- Any new GCP resources or Python repo changes

---

## 6. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Missing a `cities_max_bike` consumer (7 sites) — leaves stale value silently | Implementation plan enumerates every line; post-commit grep confirms zero bare `cities_max_bike` (no parens) references remain |
| Missing a `city_weather_bike_df` consumer (4 sites) — same silent-stale risk | Same grep check |
| `fmt_start`/`fmt_end` in build functions become reactive-object strings instead of values | Signature change + passing values explicitly eliminates this. grep for `fmt_start` after implementation confirms no bare reference outside the definitions |
| `weather_timer` fires while user is mid-interaction (city dropdown selected) | All affected charts use existing `selected_city_data()` reactive which depends on `city_weather_bike_df()`. Shiny re-renders them atomically — no partial state visible |
| Demo fallback sinusoid diverges from live weather shape across city | Both paths use the same `FORECASTDATETIME` time grid; sinusoid is anchored to UTC hour. Shape is consistent across demo sessions |
| New `test_that` block for TEMPERATURE variation could be flaky | The sinusoid formula guarantees variation at every slot except where `sin ≈ 0` — only at HOURS = 6 or HOURS = 18 exactly. With 8 slots of 3-hour spacing, at most 1 slot can have near-zero delta. `length(unique()) > 1` holds unconditionally |

---

## 7. Definition of done

1. Restart Shiny (no `.Renviron` / demo fallback mode) → temperature chart shows a curved line, not a horizontal one, for every city
2. Chart subtitles show the current time window (within minutes of the actual current time)
3. After an hour, the map header and chart subtitles advance by ~1 hour
4. GCP Stream tab city selector hint reads "Cloud Run GBFS poller"
5. `testthat` suite passes with ≥ 63 assertions (62 existing + 1 new), zero failures
6. `shiny::runApp("shiny_app")` in VS Code R terminal: no R errors or warnings on startup

---

## 8. References

- Parent spec: `docs/superpowers/specs/2026-05-24-dashboard-truth-and-freshness-design.md`
- Sprint 1 plan (shipped): `docs/superpowers/plans/2026-05-24-sprint1-gbfs-poller-cloud-run.md`
- `shiny_app/server.R` — full reference map confirmed 2026-05-25: 4 `city_weather_bike_df` consumers, 7 `cities_max_bike` consumers, 3 `fmt_start`/`fmt_end` build-function closures + 2 `renderUI`/`renderPlot` call sites
