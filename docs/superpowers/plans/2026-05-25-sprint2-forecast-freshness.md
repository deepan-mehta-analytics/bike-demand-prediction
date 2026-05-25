# Sprint 2 — Forecast Freshness + Honest Demo: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two factual truth gaps in the Shiny dashboard — frozen weather data and a flat temperature demo line — plus update one stale UI hint left over from Sprint 1.

**Architecture:** Three targeted edits: (1) wrap the weather fetch in a 1-hour `reactiveTimer` so charts refresh automatically, propagating to all derived frame and string consumers; (2) add a sinusoidal temperature/humidity mutate to the demo fallback so the chart shows a realistic diurnal curve instead of a horizontal line; (3) two one-line text changes to reflect Cloud Run replacing Dataflow.

**Tech Stack:** R 4.4.3, Shiny, ggplot2, dplyr, testthat 3.x

---

## File map

| File | Role | Tasks |
|------|------|-------|
| `shiny_app/server.R` | Main server logic — weather reactive, build functions, all consumers | T3, T4, T5, T6 |
| `shiny_app/model_prediction.R` | Demo weather data generator | T1, T2 |
| `shiny_app/ui.R` | City selector hint text for GCP Stream tab | T7 |
| `shiny_app/bigquery_client.R` | Comment-only: remove Dataflow reference | T7 |
| `tests/testthat/test-model-prediction.R` | Regression guard for sinusoidal variation | T1, T2 |

---

## Task 1: Write failing test for sinusoidal TEMPERATURE variation

**Files:**
- Modify: `tests/testthat/test-model-prediction.R`

- [ ] **Step 1: Open the test file and find the generate_demo_weather_data section**

  The section starts around line 114 with the comment:
  ```
  # ── generate_demo_weather_data() ──────────────────────────────────────────────
  ```
  There are already two `test_that` blocks for this function. Add a **third** block immediately after the second one.

- [ ] **Step 2: Add the failing test**

  Append after the existing two generate_demo_weather_data tests:
  ```r
  test_that("generate_demo_weather_data: TEMPERATURE varies across slots within a city", {
    result      <- suppressMessages(generate_demo_weather_data())          # 6 cities x 8 forecast slots
    paris_temps <- result$TEMPERATURE[result$CITY_ASCII == "Paris"]        # 8 temperature values for Paris
    expect_gt(length(unique(paris_temps)), 1L)                             # must not all be identical
  })
  ```

- [ ] **Step 3: Run the test file and confirm it FAILS**

  In the VS Code R terminal (working directory must be `shiny_app/` for the source calls to find model.csv — but the helper-workdir.R pattern handles this):
  ```r
  testthat::test_file("tests/testthat/test-model-prediction.R")
  ```
  Expected output includes a failure line like:
  ```
  Failure (test-model-prediction.R:XX): generate_demo_weather_data: TEMPERATURE varies...
  length(unique(paris_temps)) > 1 is not TRUE
  ```
  If it passes instead of failing, the flat-line bug has somehow already been fixed — re-read `model_prediction.R` to confirm.

---

## Task 2: Implement sinusoidal variation in generate_demo_weather_data()

**Files:**
- Modify: `shiny_app/model_prediction.R`

- [ ] **Step 1: Find the cross_join call in generate_demo_weather_data()**

  In `model_prediction.R`, find this exact block (around line 573):
  ```r
    # ── Cross-join: 6 cities × 8 slots = 48 rows ────────────────────────────────
    df <- cross_join(city_params, slots)                                # every city paired with every slot

    # ── Bike demand prediction + HTML popup labels ───────────────────────────────
    df %>%
  ```

- [ ] **Step 2: Insert the diurnal mutate between cross_join and the bike prediction block**

  Replace the block found in Step 1 with:
  ```r
    # ── Cross-join: 6 cities × 8 slots = 48 rows ────────────────────────────────
    df <- cross_join(city_params, slots)                                # every city paired with every slot

    # ── Apply diurnal temperature/humidity variation ──────────────────────────────
    # Replaces the city-constant TEMPERATURE and HUMIDITY from city_params with
    # slot-varying sinusoids so the chart shows a realistic curve instead of a flat line.
    # TEMPERATURE peaks ~14:00 UTC, troughs ~02:00 UTC, amplitude ±5 °C.
    # HUMIDITY inversely correlated, amplitude ±8 pp, bounded to 35–95 %.
    # HOURS is already an integer 0-23 column in df from the slots tibble.
    df <- df %>%
      mutate(
        TEMPERATURE = TEMPERATURE + 5 * sin((as.numeric(HOURS) - 6) * pi / 12),   # diurnal cycle
        HUMIDITY    = pmin(95L, pmax(35L, HUMIDITY + as.integer(                   # inverse, bounded
                        round(-8 * sin((as.numeric(HOURS) - 6) * pi / 12)))))
      )

    # ── Bike demand prediction + HTML popup labels ───────────────────────────────
    df %>%
  ```

- [ ] **Step 3: Run the test file and confirm the new test PASSES**

  ```r
  testthat::test_file("tests/testthat/test-model-prediction.R")
  ```
  Expected: all tests pass including the new variation test. If the new test still fails, check that the mutate is positioned BEFORE `df %>% mutate(BIKE_PREDICTION = ...)` — the sinusoid must replace the constant before BIKE_PREDICTION is computed.

- [ ] **Step 4: Run the full test suite to confirm no regressions**

  ```r
  testthat::test_dir("tests/testthat")
  ```
  Expected: 63 passed, 0 failed, 0 warnings (62 pre-existing + 1 new).

- [ ] **Step 5: Commit**

  ```
  git add shiny_app/model_prediction.R tests/testthat/test-model-prediction.R
  git commit -m "fix(model_prediction): add diurnal variation to demo weather fallback"
  ```

---

## Task 3: B1 — Replace startup block with reactive declarations (server.R)

**Files:**
- Modify: `shiny_app/server.R`

The current server.R has the weather data fetched as a plain assignment on one line at session start. This task replaces that single line with four reactive declarations (`weather_timer`, `city_weather_bike_df`, `forecast_window`, `cities_max_bike`), then deletes the old derived-variable block that follows the GBFS feed code.

- [ ] **Step 1: Replace the startup comment + assignment (lines ~118-122)**

  Find this exact block in server.R:
  ```r
    # ---------------------------------------------------------------------------
    # Forecast data fetched once on startup; station data refreshes via reactiveTimer every 5 min
    # Each city now has 8 rows (8 x 3-hour slots = next 24 hours)
    # ---------------------------------------------------------------------------
    city_weather_bike_df <- test_weather_data_generation()
  ```

  Replace it with:
  ```r
    # ---------------------------------------------------------------------------
    # Hourly weather reactive block — replaces the startup-time plain assignment.
    # weather_timer fires every hour; all derived reactives (forecast_window,
    # cities_max_bike) recompute automatically. Consumers call city_weather_bike_df()
    # and cities_max_bike() with parentheses — they are reactive expressions, not frames.
    # ---------------------------------------------------------------------------

    # ── 1-hour refresh timer ─────────────────────────────────────────────────────
    weather_timer <- reactiveTimer(3600000)                        # fires every 3 600 000 ms = 1 hour

    # ── Main weather + prediction frame ──────────────────────────────────────────
    # Re-runs each time weather_timer() invalidates (hourly) and on session start.
    # test_weather_data_generation() tries live OpenWeather first; falls back to
    # generate_demo_weather_data() on any error (missing key, network failure, etc.).
    city_weather_bike_df <- reactive({
      weather_timer()                                              # declare timer dependency
      df <- test_weather_data_generation()                         # live → demo fallback
      df %>%
        mutate(FORECASTDATETIME_DT = as.POSIXct(                  # parse string → POSIXct UTC
          FORECASTDATETIME,
          format = "%Y-%m-%d %H:%M:%S",
          tz     = "UTC"
        ))
    })

    # ── Forecast window strings ───────────────────────────────────────────────────
    # Returns a named list: list(fmt_start = "...", fmt_end = "...").
    # Callers: w <- forecast_window(); then use w$fmt_start and w$fmt_end.
    forecast_window <- reactive({
      df    <- city_weather_bike_df()                              # read latest weather frame
      start <- min(df$FORECASTDATETIME_DT, na.rm = TRUE)          # earliest forecast slot
      end   <- max(df$FORECASTDATETIME_DT, na.rm = TRUE)          # latest forecast slot
      list(
        fmt_start = format(start, "%d %b %Y %H:%M"),              # e.g. "25 May 2026 14:00"
        fmt_end   = format(end,   "%d %b %Y %H:%M")               # e.g. "26 May 2026 11:00"
      )
    })

    # ── One-row-per-city summary frame ────────────────────────────────────────────
    # Peak demand slot per city; used by the overview map and compare chart.
    # Consumers call cities_max_bike() with parentheses.
    cities_max_bike <- reactive({
      city_weather_bike_df() %>%                                   # read latest weather frame
        group_by(CITY_ASCII, LAT, LNG) %>%
        summarise(
          BIKE_PREDICTION       = max(BIKE_PREDICTION, na.rm = TRUE),               # peak slot demand
          BIKE_PREDICTION_LEVEL = BIKE_PREDICTION_LEVEL[which.max(BIKE_PREDICTION)],# level at peak
          LABEL                 = LABEL[which.max(BIKE_PREDICTION)],                 # map popup (short)
          DETAILED_LABEL        = DETAILED_LABEL[which.max(BIKE_PREDICTION)],        # map popup (full)
          .groups               = "drop"
        )
    })
  ```

- [ ] **Step 2: Delete the old derived-variable block (lines ~224-249)**

  After the GBFS / feed-health code block (which ends around line 222 with `tagList(header, city_rows, footer)`), find and delete this entire block:
  ```r
    # Parse FORECASTDATETIME once globally so date range calculations work
    city_weather_bike_df <- city_weather_bike_df %>%
      mutate(FORECASTDATETIME_DT = as.POSIXct(FORECASTDATETIME,
                                              format = "%Y-%m-%d %H:%M:%S",
                                              tz = "UTC"))
    
    # Compute the actual forecast window from the data
    # These drive the dynamic map header title
    forecast_start <- min(city_weather_bike_df$FORECASTDATETIME_DT, na.rm = TRUE)
    forecast_end   <- max(city_weather_bike_df$FORECASTDATETIME_DT, na.rm = TRUE)
    
    # Formatted date strings used in all titles — e.g. "22 Apr 2026 09:00"
    fmt_start <- format(forecast_start, "%d %b %Y %H:%M")
    fmt_end   <- format(forecast_end,   "%d %b %Y %H:%M")
    
    # One-row-per-city aggregated data for the overview map and compare chart
    cities_max_bike <- city_weather_bike_df %>%
      group_by(CITY_ASCII, LAT, LNG) %>%
      summarise(
        BIKE_PREDICTION       = max(BIKE_PREDICTION, na.rm = TRUE),
        BIKE_PREDICTION_LEVEL = BIKE_PREDICTION_LEVEL[which.max(BIKE_PREDICTION)],
        LABEL                 = LABEL[which.max(BIKE_PREDICTION)],
        DETAILED_LABEL        = DETAILED_LABEL[which.max(BIKE_PREDICTION)],
        .groups = "drop"
      )
  ```

  Replace with just a blank line and a short comment:
  ```r

    # city_weather_bike_df, forecast_window, and cities_max_bike are reactive
    # expressions defined in the hourly weather block above.

  ```

---

## Task 4: B1 — Update build function signatures (server.R)

**Files:**
- Modify: `shiny_app/server.R`

Three chart builder functions close over `fmt_start`/`fmt_end` from the old enclosing scope. Those plain strings are gone; the functions must now receive them as explicit parameters.

- [ ] **Step 1: Update build_compare_chart signature**

  Find:
  ```r
    build_compare_chart <- function(data) {
  ```
  Replace with:
  ```r
    build_compare_chart <- function(data, fmt_start, fmt_end) {   # fmt_start/fmt_end passed by caller
  ```
  The function body is unchanged — `fmt_start` and `fmt_end` are now parameters, not closures, so they still resolve correctly on line 402.

- [ ] **Step 2: Update build_temp_chart signature**

  Find:
  ```r
    build_temp_chart <- function(df) {
  ```
  Replace with:
  ```r
    build_temp_chart <- function(df, fmt_start, fmt_end) {         # fmt_start/fmt_end passed by caller
  ```

- [ ] **Step 3: Update build_bike_chart signature**

  Find:
  ```r
    build_bike_chart <- function(df) {
  ```
  Replace with:
  ```r
    build_bike_chart <- function(df, fmt_start, fmt_end) {         # fmt_start/fmt_end passed by caller
  ```

  `build_humidity_chart` does NOT use `fmt_start`/`fmt_end` — leave it unchanged.

---

## Task 5: B1 — Update all consumers (server.R)

**Files:**
- Modify: `shiny_app/server.R`

All direct consumers of `city_weather_bike_df`, `cities_max_bike`, and `fmt_start`/`fmt_end` must be updated. Work through them section by section.

### 5a — Map date-title renderUI

- [ ] **Step 1: Update output$map_date_title**

  Find:
  ```r
    output$map_date_title <- renderUI({
      tags$div(
        class = "map-title",
        tags$i(class = "glyphicon glyphicon-globe", style = "margin-right:7px;"),
        paste0("24-Hour Bike Demand Forecast  •  ", fmt_start, "  →  ", fmt_end)
      )
    })
  ```
  Replace with:
  ```r
    output$map_date_title <- renderUI({
      w <- forecast_window()                                        # read current fmt_start / fmt_end
      tags$div(
        class = "map-title",
        tags$i(class = "glyphicon glyphicon-globe", style = "margin-right:7px;"),
        paste0("24-Hour Bike Demand Forecast  •  ", w$fmt_start, "  →  ", w$fmt_end)
      )
    })
  ```

### 5b — city_weather_bike_df consumers (add parentheses)

Each of the following is a direct `city_weather_bike_df %>%` reference that must become `city_weather_bike_df() %>%`. Make each replacement one at a time.

- [ ] **Step 2: Leaflet fallback marker (inside renderLeaflet — "All cities" else-branch)**

  Find:
  ```r
          selected_city <- city_weather_bike_df %>% filter(CITY_ASCII == input$city_dropdown)
  ```
  Replace with:
  ```r
          selected_city <- city_weather_bike_df() %>% filter(CITY_ASCII == input$city_dropdown)  # () — reactive
  ```

- [ ] **Step 3: selected_city_data reactive**

  Find:
  ```r
    city_weather_bike_df %>%
      filter(CITY_ASCII == input$city_dropdown) %>%
      mutate(
  ```
  Replace with:
  ```r
    city_weather_bike_df() %>%                                     # () — reactive expression
      filter(CITY_ASCII == input$city_dropdown) %>%
      mutate(
  ```

- [ ] **Step 4: operator_city_data reactive**

  Find:
  ```r
    city_weather_bike_df %>%                                                # full 5-city 24h forecast frame
      filter(CITY_ASCII == input$operator_city)                             # keep only the operator's chosen city
  ```
  Replace with:
  ```r
    city_weather_bike_df() %>%                                              # () — reactive; full 5-city 24h frame
      filter(CITY_ASCII == input$operator_city)                             # keep only the operator's chosen city
  ```

- [ ] **Step 5: rider_city_data reactive**

  Find:
  ```r
    city_weather_bike_df %>%                                               # full 5-city 24h frame
      filter(CITY_ASCII == input$rider_city) %>%                          # filter to chosen city
      arrange(FORECASTDATETIME_DT)                                        # ensure chronological order
  ```
  Replace with:
  ```r
    city_weather_bike_df() %>%                                             # () — reactive; full 5-city 24h frame
      filter(CITY_ASCII == input$rider_city) %>%                          # filter to chosen city
      arrange(FORECASTDATETIME_DT)                                        # ensure chronological order
  ```

### 5c — cities_max_bike consumers (add parentheses)

- [ ] **Step 6: Overview map — filtered demand levels**

  Find:
  ```r
        filtered <- cities_max_bike %>%
          filter(BIKE_PREDICTION_LEVEL %in% active_levels())
  ```
  Replace with:
  ```r
        filtered <- cities_max_bike() %>%                          # () — reactive
          filter(BIKE_PREDICTION_LEVEL %in% active_levels())
  ```

- [ ] **Step 7: City drill-down — setView coordinates**

  Find:
  ```r
        selected_city_coords <- cities_max_bike %>% filter(CITY_ASCII == input$city_dropdown)  # city centre for setView
  ```
  Replace with:
  ```r
        selected_city_coords <- cities_max_bike() %>% filter(CITY_ASCII == input$city_dropdown)  # () — reactive; city centre
  ```

- [ ] **Step 8: Compare chart call site (sidebar)**

  Find:
  ```r
    output$city_compare_chart <- renderPlot({ build_compare_chart(cities_max_bike) })
  ```
  Replace with:
  ```r
    output$city_compare_chart <- renderPlot({                      # rebuild when weather or city changes
      w <- forecast_window()                                        # read current window strings
      build_compare_chart(cities_max_bike(), w$fmt_start, w$fmt_end)
    })
  ```

- [ ] **Step 9: Compare chart call site (modal)**

  Find:
  ```r
    output$city_compare_chart_modal <- renderPlot({ build_compare_chart(cities_max_bike) })
  ```
  Replace with:
  ```r
    output$city_compare_chart_modal <- renderPlot({                # modal must stay in sync with sidebar
      w <- forecast_window()                                        # read current window strings
      build_compare_chart(cities_max_bike(), w$fmt_start, w$fmt_end)
    })
  ```

- [ ] **Step 10: City summary table**

  Find:
  ```r
      tbl <- cities_max_bike %>%
  ```
  Replace with:
  ```r
      tbl <- cities_max_bike() %>%                                 # () — reactive
  ```

- [ ] **Step 11: Operator city setView**

  Find:
  ```r
      city_coords <- cities_max_bike %>%                                     # city centre row for setView
  ```
  Replace with:
  ```r
      city_coords <- cities_max_bike() %>%                                   # () — reactive; city centre
  ```

- [ ] **Step 12: Rider city setView**

  Find:
  ```r
      city_coords <- cities_max_bike %>% filter(CITY_ASCII == input$rider_city)
  ```
  Replace with:
  ```r
      city_coords <- cities_max_bike() %>% filter(CITY_ASCII == input$rider_city)  # () — reactive
  ```

### 5d — Build function call sites (pass fmt_start/fmt_end)

- [ ] **Step 13: temp_chart_obj reactive**

  Find:
  ```r
    temp_chart_obj <- reactive({                                       # temperature trend; invalidates on city change
      req(input$city_dropdown != "All")
      build_temp_chart(selected_city_data())
    })
  ```
  Replace with:
  ```r
    temp_chart_obj <- reactive({                                       # temperature trend; invalidates on city/timer change
      req(input$city_dropdown != "All")
      w <- forecast_window()                                           # read current window strings
      build_temp_chart(selected_city_data(), w$fmt_start, w$fmt_end)  # pass fmt args explicitly
    })
  ```

- [ ] **Step 14: bike_chart_obj reactive**

  Find:
  ```r
    bike_chart_obj <- reactive({                                       # bike demand forecast
      req(input$city_dropdown != "All")
      build_bike_chart(selected_city_data())
    })
  ```
  Replace with:
  ```r
    bike_chart_obj <- reactive({                                       # bike demand forecast; invalidates on city/timer change
      req(input$city_dropdown != "All")
      w <- forecast_window()                                           # read current window strings
      build_bike_chart(selected_city_data(), w$fmt_start, w$fmt_end)  # pass fmt args explicitly
    })
  ```

---

## Task 6: B1 — Verify and commit

**Files:**
- Modify: `shiny_app/server.R` (verification only)

- [ ] **Step 1: Parse check — confirm no syntax errors**

  In the VS Code R terminal:
  ```r
  tryCatch(parse(file = "shiny_app/server.R"), error = function(e) cat("ERROR:", conditionMessage(e), "\n"))
  cat("parse OK\n")
  ```
  Expected output: `parse OK`

  If you see an error like `unexpected ')'` or `object 'fmt_start' not found`, re-check the edits in Tasks 3–5 — a common miss is a `cities_max_bike` reference without parens.

- [ ] **Step 2: Confirm no bare city_weather_bike_df references remain**

  Run in the PowerShell terminal (from the repo root):
  ```powershell
  Select-String -Path "shiny_app\server.R" -Pattern "city_weather_bike_df[^(]" | Where-Object { $_ -notmatch "reactive\(\{" -and $_ -notmatch "weather_timer" } | Select-Object LineNumber, Line
  ```
  Expected: zero results (or only lines inside the reactive declaration itself). Any hit is a missed consumer.

- [ ] **Step 3: Confirm no bare cities_max_bike references remain**

  ```powershell
  Select-String -Path "shiny_app\server.R" -Pattern "cities_max_bike[^(]" | Where-Object { $_ -notmatch "reactive\(\{" } | Select-Object LineNumber, Line
  ```
  Expected: zero results. Any hit is a missed consumer.

- [ ] **Step 4: Smoke test — start the app and check the R console for errors**

  In the VS Code R terminal:
  ```r
  shiny::runApp("shiny_app")
  ```
  Expected:
  - No red R errors in the console
  - App opens in the browser (or RStudio viewer)
  - Temperature chart for Paris shows a *curved* line (peaks in the afternoon hours), not a flat horizontal line
  - Chart subtitle shows today's date in the "Next 24 Hours • DD MMM YYYY HH:MM → ..." format

  Stop the app with Ctrl+C / Escape after confirming. A full e2e session test is not required here.

- [ ] **Step 5: Run full testthat suite**

  ```r
  testthat::test_dir("tests/testthat")
  ```
  Expected: 63 passed, 0 failed.

- [ ] **Step 6: Commit**

  ```
  git add shiny_app/server.R
  git commit -m "feat(server): make weather data reactive with 1-hour refresh timer (Sprint 2 B1)"
  ```

---

## Task 7: Hint text fixes + final commit

**Files:**
- Modify: `shiny_app/ui.R`
- Modify: `shiny_app/bigquery_client.R`

- [ ] **Step 1: Update GCP Stream city selector hint (ui.R)**

  Find in `shiny_app/ui.R`:
  ```r
                                   "Only cities polled by the Dataflow pipeline are available here.",
                                   " Seoul and Paris are not in the GCP pipeline."
  ```
  Replace with:
  ```r
                                   "Only cities polled by the Cloud Run GBFS poller are available here.",
                                   " Seoul and Paris are not in the GCP pipeline."
  ```

- [ ] **Step 2: Update comment in bigquery_client.R**

  Find in `shiny_app/bigquery_client.R` (line 4):
  ```r
  # the table written by the Dataflow GBFS streaming pipeline.
  ```
  Replace with:
  ```r
  # the table written by the Cloud Run GBFS poller (gbfs-poller Cloud Run service).
  ```

- [ ] **Step 3: Run full testthat suite one final time**

  ```r
  testthat::test_dir("tests/testthat")
  ```
  Expected: 63 passed, 0 failed.

- [ ] **Step 4: Commit**

  ```
  git add shiny_app/ui.R shiny_app/bigquery_client.R
  git commit -m "fix(ui): update GCP Stream hint text to reflect Cloud Run poller (Sprint 1 follow-up)"
  ```

- [ ] **Step 5: Push both commits**

  ```
  git push origin main
  ```

---

## Post-implementation verification checklist

Run these checks after all commits are pushed, confirming Sprint 2 definition of done:

- [ ] Shiny started with no `.Renviron` (demo mode) → Temperature Trend chart shows a curved sinusoid for every city
- [ ] Chart subtitle "Next 24 Hours • DD MMM YYYY HH:MM → ..." shows today's actual date, not a stale date from weeks ago
- [ ] GCP Stream tab city selector hint reads "Cloud Run GBFS poller"
- [ ] `testthat::test_dir("tests/testthat")` → 63 passed, 0 failed
- [ ] `git log --oneline -3` shows the two new commits above the Sprint 1 cross-repo sync

---

## References

- Spec: `docs/superpowers/specs/2026-05-25-sprint2-forecast-freshness-design.md`
- Parent spec (full truth-gap inventory): `docs/superpowers/specs/2026-05-24-dashboard-truth-and-freshness-design.md`
- Consumer reference map (confirmed 2026-05-25): 4 × `city_weather_bike_df`, 7 × `cities_max_bike`, 3 build function signatures, 5 call sites
