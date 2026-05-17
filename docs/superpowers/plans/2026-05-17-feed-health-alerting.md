# Feed Health Alerting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a colour-coded Feed Health sidebar panel to the Live Map tab showing per-city live-feed status in plain English, backed by a 5-minute reactive refresh timer; also fix the modal expand charts to stay in sync with the city dropdown.

**Architecture:** `gbfs_client.R` gains a new `get_city_live_stations()` function that wraps the existing dispatcher and returns an enriched named list (data + status + metadata). `server.R` replaces the one-time static station fetch with a `reactiveTimer`-driven per-city fetch loop that updates both a `reactiveVal` holding the combined station data and a `reactiveValues` object tracking per-city failure counts. `ui.R` receives two CSS fixes and a new `uiOutput` slot for the panel.

**Tech Stack:** R 4.x, Shiny 1.x, shinyjs, ggplot2, leaflet, httr, dplyr, tibble

**Spec:** `docs/superpowers/specs/2026-05-17-feed-health-alerting-design.md`

---

## File Map

| File | Change |
|---|---|
| `shiny_app/gbfs_client.R` | Add `get_city_live_stations()` after Section 5 (~line 475) |
| `shiny_app/server.R` | Add helper fns + feed_state + reactiveTimer + renderUI (feed panel + modal titles); refactor shared chart reactives; update 3 `live_stations_df` call sites |
| `shiny_app/ui.R` | 2 CSS additions; insert `uiOutput("feed_health_panel")`; update 3 modal `showModal` title args |

---

## Task 1: `gbfs_client.R` — Add per-city enriched return function

**Files:**
- Modify: `shiny_app/gbfs_client.R` after line 475 (end of `parse_gbfs_stations`)

The current `parse_gbfs_stations()` returns a bare tibble. Callers in `server.R` can't tell
whether empty means "failed" or "0 stations". The new wrapper captures that distinction at
the source and surfaces it as structured metadata.

- [ ] **Step 1: Insert `get_city_live_stations()` after line 475**

Open `shiny_app/gbfs_client.R`. After the closing `}` of `parse_gbfs_stations` (line 475)
and before the `# SECTION 6` comment (line 478), insert this block:

```r
# =============================================================================
# SECTION 5b — Per-city enriched fetch
# =============================================================================

# get_city_live_stations()
# -------------------------
# Wraps parse_gbfs_stations() and returns a named list instead of a bare tibble.
# The list carries status metadata so server.R can track feed health without
# inferring success/failure from nrow().
#
# Arguments:
#   city_name — CITY_ASCII string (must be a key in CITY_GBFS_CONFIG)
#
# Returns: named list with fields:
#   data       — tibble matching EMPTY_STATIONS_SCHEMA (rows on success, 0 rows on failure)
#   status     — "ok" | "error"
#   row_count  — integer; nrow(data)
#   fetched_at — POSIXct; Sys.time() at moment of return
#   message    — NULL on success; plain-English string on failure

get_city_live_stations <- function(city_name) {

  result_tbl <- tryCatch(                                          # catch unexpected runtime errors
    parse_gbfs_stations(city_name),                               # routes to correct parser for this city
    error = function(e) {
      warning(paste("Unexpected error fetching", city_name, ":", conditionMessage(e)))
      EMPTY_STATIONS_SCHEMA                                       # degrade gracefully
    }
  )

  success <- nrow(result_tbl) > 0L                                # TRUE if parser returned ≥ 1 station row

  list(                                                           # enriched return — never a bare tibble
    data       = result_tbl,                                      # station rows (zero-row tibble on failure)
    status     = if (success) "ok" else "error",                  # machine-readable state
    row_count  = nrow(result_tbl),                                # 0 on failure
    fetched_at = Sys.time(),                                      # timestamp for staleness calculation
    message    = if (success) NULL                                # NULL on success
                 else paste("No station data returned for", city_name)  # plain-English failure reason
  )
}
```

- [ ] **Step 2: Verify the file still sources cleanly**

Open a terminal in the project root and run:
```r
Rscript -e "source('shiny_app/gbfs_client.R'); r <- get_city_live_stations('Paris'); cat(r$status, r$row_count, '\n')"
```
Expected output: `ok` followed by a non-zero integer (e.g. `ok 1427`).
If Paris API is unreachable the output will be `error 0` — either is acceptable; the point is no R error.

- [ ] **Step 3: Commit**

```
git add shiny_app/gbfs_client.R
git commit -m "feat(gbfs): add get_city_live_stations() enriched return wrapper"
```

---

## Task 2: `server.R` — Add `build_feed_status_text()` and `update_feed_state()` helpers

**Files:**
- Modify: `shiny_app/server.R` — insert before the `shinyServer(` call (around line 33)

These are plain R functions (not reactives). Defining them outside `shinyServer` means
they are evaluated once on load and available to all sessions.

- [ ] **Step 1: Insert helper functions before `shinyServer(` (line 33)**

```r
# =============================================================================
# Feed Health helpers
# =============================================================================

# build_feed_status_text()
# -------------------------
# Returns a plain-English string for a city's current feed status.
# Never exposes HTTP codes, R error messages, or API jargon to the user.
#
# Arguments:
#   r — named list: city, status, failures, row_count, fetched_at, message

build_feed_status_text <- function(r) {
  if (r$status == "loading")                                         # first load; not yet fetched
    return("Connecting to station data…")

  if (r$status == "green") {
    if (r$city == "Seoul" && r$row_count <= 5L)                      # sample key returns only 5 rows
      return("Showing 5 demo stations (sample key). Full data requires a Seoul API key.")
    return(paste0("All ", format(r$row_count, big.mark = ","), " stations reporting normally."))
  }

  mins_ago <- if (!is.null(r$fetched_at))                            # minutes since last successful data
    as.integer(difftime(Sys.time(), r$fetched_at, units = "mins"))
  else NA_integer_

  if (r$status == "amber") {
    if (!is.na(mins_ago) && mins_ago > 0L)
      return(paste0(
        "Station data is being refreshed — last update ",
        mins_ago, " minute", if (mins_ago != 1L) "s" else "", " ago. Forecast is unaffected."
      ))
    return("Waiting for station data — retrying shortly. Forecast is unaffected.")
  }

  # red
  "Station map is temporarily unavailable. Your 24-hour forecast is still running."
}


# update_feed_state()
# --------------------
# Mutates feed_state[[city]] in place based on the enriched result from
# get_city_live_stations(). Increments failure count on error; resets on success.
#
# Arguments:
#   feed_state — reactiveValues object (defined inside shinyServer)
#   city       — CITY_ASCII string matching a key in feed_state
#   result     — named list returned by get_city_live_stations()

update_feed_state <- function(feed_state, city, result) {
  if (result$status == "ok") {                                       # successful fetch → green
    feed_state[[city]] <- list(
      failures   = 0L,                                               # reset failure counter
      status     = "green",
      row_count  = result$row_count,
      fetched_at = result$fetched_at,
      message    = NULL
    )
  } else {                                                           # failed fetch → amber or red
    prev <- feed_state[[city]]$failures %||% 0L                      # guard: handle loading state
    new_failures <- prev + 1L                                        # increment consecutive failure count
    feed_state[[city]] <- list(
      failures   = new_failures,
      status     = if (new_failures >= 3L) "red" else "amber",       # 1-2 fails = amber; 3+ = red
      row_count  = 0L,
      fetched_at = result$fetched_at,
      message    = result$message
    )
  }
}
```

- [ ] **Step 2: Verify syntax**

```r
Rscript -e "source('shiny_app/gbfs_client.R'); source('shiny_app/server.R')" 2>&1 | head -5
```
Expected: no parse errors (may warn about missing Shiny context — that is fine).

- [ ] **Step 3: Commit**

```
git add shiny_app/server.R
git commit -m "feat(server): add feed health helper functions"
```

---

## Task 3: `server.R` — Replace static fetch with `reactiveTimer` + `feed_state`

**Files:**
- Modify: `shiny_app/server.R` lines 41–51 (the startup `live_stations_df` block)

Currently, station data is fetched **once** at app startup into a static variable.
This task replaces that with a `reactiveVal` (so the map re-renders on new data) and
a `reactiveTimer` observer that re-fetches every 5 minutes and populates `feed_state`.

- [ ] **Step 1: Replace lines 41–51 with `reactiveVal` + `feed_state` + timer**

Delete the current block:
```r
  live_stations_df <- tryCatch(
    get_all_cities_live_stations(unique(city_weather_bike_df$CITY_ASCII)),
    error = function(e) {
      warning(paste("GBFS startup fetch failed:", conditionMessage(e)))
      EMPTY_STATIONS_SCHEMA
    }
  )
```

Replace with:

```r
  # ── Feed state + live station data ─────────────────────────────────────────
  # feed_state tracks per-city failure counts and display status.
  # live_stations_df is a reactiveVal: the map re-renders automatically when
  # new station data arrives from the 5-minute timer.

  GBFS_CITIES <- c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC")  # all tracked cities

  feed_state <- reactiveValues(                                      # one entry per city; "loading" until first fetch
    Seoul          = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    London         = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    `New York`     = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    Paris          = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    Chicago        = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    `Washington DC`= list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL)
  )

  live_stations_df <- reactiveVal(EMPTY_STATIONS_SCHEMA)             # starts empty; replaced by first timer fire

  gbfs_timer <- reactiveTimer(300000)                                # invalidates every 5 minutes (300,000 ms)

  observe({                                                          # runs immediately on startup; re-runs every 5 min
    gbfs_timer()                                                     # declare dependency on timer
    new_data <- lapply(GBFS_CITIES, function(city) {                 # fetch each city independently
      result <- get_city_live_stations(city)                         # enriched return: data + status + metadata
      update_feed_state(feed_state, city, result)                    # update feed_state (side effect)
      result$data                                                    # return just the tibble for stacking
    })
    live_stations_df(bind_rows(new_data))                            # update reactiveVal — triggers map re-render
  })
```

- [ ] **Step 2: Update the 3 `live_stations_df` call sites (add parentheses)**

`live_stations_df` is now a `reactiveVal`, so all reads need `()`.

**Line ~157** (inside `renderLeaflet`, Live Map tab):
```r
# Before:
city_stations <- live_stations_df %>%
  filter(CITY_ASCII == input$city_dropdown, IS_RENTING == TRUE)

# After:
city_stations <- live_stations_df() %>%                              # () reads current reactiveVal
  filter(CITY_ASCII == input$city_dropdown, IS_RENTING == TRUE)
```

**Line ~514** (inside `operator_stations` reactive, Operator tab):
```r
# Before:
operator_stations <- reactive({
  live_stations_df %>%
    filter(CITY_ASCII == input$operator_city, IS_RENTING == TRUE)
})

# After:
operator_stations <- reactive({
  live_stations_df() %>%                                             # () inside reactive is fine — declares dependency
    filter(CITY_ASCII == input$operator_city, IS_RENTING == TRUE)
})
```

**Line ~771** (inside `rider_stations` reactive, Rider tab):
```r
# Before:
rider_stations <- reactive({
  live_stations_df %>%
    filter(CITY_ASCII == input$rider_city, IS_RENTING == TRUE)
})

# After:
rider_stations <- reactive({
  live_stations_df() %>%                                             # () inside reactive — re-evaluates on new data
    filter(CITY_ASCII == input$rider_city, IS_RENTING == TRUE)
})
```

- [ ] **Step 3: Verify the app still launches**

```r
Rscript -e "library(shiny); runApp('shiny_app', port=3839, launch.browser=FALSE)" &
```
Wait 15 seconds. Open `http://localhost:3839` in a browser. The map should show Paris
(default) with station markers loading within ~10 seconds of the timer first firing.
Kill the process after confirming (`Ctrl+C`).

- [ ] **Step 4: Commit**

```
git add shiny_app/server.R
git commit -m "feat(server): replace static station fetch with 5-min reactiveTimer + feed_state"
```

---

## Task 4: `server.R` — Add `renderUI` for the Feed Health panel

**Files:**
- Modify: `shiny_app/server.R` — insert after the `gbfs_timer` observe block from Task 3

- [ ] **Step 1: Insert `feed_health_df` reactive + `output$feed_health_panel` renderUI**

Directly after the `observe({ gbfs_timer(); ... })` block, insert:

```r
  # ── Feed Health panel reactive ──────────────────────────────────────────────
  # Collapses feed_state into a list of per-city status records consumed by renderUI.
  feed_health_df <- reactive({
    lapply(GBFS_CITIES, function(city) {                             # one record per city in display order
      s <- feed_state[[city]]                                        # read current city state from reactiveValues
      list(
        city       = city,
        status     = s$status,
        failures   = s$failures,
        row_count  = s$row_count,
        fetched_at = s$fetched_at,
        message    = s$message
      )
    })
  })


  # ── Feed Health panel UI ────────────────────────────────────────────────────
  # Renders a colour-coded row per city. Re-renders whenever feed_state changes
  # (i.e. after every timer fire). Fills uiOutput("feed_health_panel") in ui.R.

  output$feed_health_panel <- renderUI({

    rows <- feed_health_df()                                         # current list of per-city status records

    # Section header
    header <- tags$div(
      style = "padding:10px 12px 6px; border-bottom:1px solid #ddd;",
      tags$div(
        style = "font-size:11px; text-transform:uppercase; font-weight:700;
                 letter-spacing:0.05em; color:#555;",
        "Live Data Status"
      ),
      tags$div(style = "font-size:11px; color:#888; margin-top:2px;",
               "Refreshes every 5 minutes")
    )

    # One colour-coded row per city
    city_rows <- lapply(rows, function(r) {
      cfg <- switch(r$status,
        loading = list(bg="#f8f8f8", border="#cccccc", badge_bg="#aaaaaa", label="…"),
        green   = list(bg="#f0faf2", border="#27ae60", badge_bg="#27ae60", label="LIVE"),
        amber   = list(bg="#fffbf0", border="#f39c12", badge_bg="#f39c12", label="DELAYED"),
        red     = list(bg="#fff5f5", border="#e74c3c", badge_bg="#e74c3c", label="UNAVAILABLE"),
                  list(bg="#f8f8f8", border="#cccccc", badge_bg="#aaaaaa", label="?")  # fallback
      )
      body_text <- build_feed_status_text(r)                        # plain-English status sentence
      tags$div(
        style = sprintf(
          "background:%s; border-left:4px solid %s; padding:9px 12px; border-bottom:1px solid #dde;",
          cfg$bg, cfg$border
        ),
        tags$div(
          style = "display:flex; justify-content:space-between; align-items:center;",
          tags$span(style = "font-weight:600; color:#1a1a1a; font-size:13px;", r$city),
          tags$span(
            style = sprintf(
              "background:%s; color:white; font-size:10px; padding:2px 7px;
               border-radius:10px; font-weight:600;",
              cfg$badge_bg
            ),
            cfg$label
          )
        ),
        tags$div(style = "color:#555; font-size:11px; margin-top:3px;", body_text)
      )
    })

    # Footer note
    footer <- tags$div(
      style = "padding:8px 12px; background:#f8f8f8; font-size:10px; color:#999; border-top:1px solid #ddd;",
      "Station maps show live availability. Forecasts always run independently."
    )

    tagList(header, city_rows, footer)
  })
```

- [ ] **Step 2: Commit (UI not wired yet — safe to commit the server side first)**

```
git add shiny_app/server.R
git commit -m "feat(server): add feed_health_df reactive and feed_health_panel renderUI"
```

---

## Task 5: `server.R` — Shared chart reactives + modal title fix

**Files:**
- Modify: `shiny_app/server.R` lines ~389–498

Currently each chart has two independent `renderPlot` calls (sidebar + modal), so the
modal can lag behind the sidebar when the city changes. This task extracts one shared
`reactive()` per chart so sidebar and modal always consume the same computed object.
Modal titles are also made reactive so they update when city changes while modal is open.

- [ ] **Step 1: Replace the sidebar `renderPlot` block (lines ~389–402) with shared reactives**

Delete:
```r
  output$temp_line <- renderPlot({
    req(input$city_dropdown != "All")
    build_temp_chart(selected_city_data())
  })

  output$bike_line <- renderPlot({
    req(input$city_dropdown != "All")
    build_bike_chart(selected_city_data())
  })

  output$humidity_pred_chart <- renderPlot({
    req(input$city_dropdown != "All")
    build_humidity_chart(selected_city_data())
  })
```

Replace with:
```r
  # ── Shared chart reactives ─────────────────────────────────────────────────
  # One reactive per chart. Both sidebar and modal renderPlots consume the same
  # reactive object — they are guaranteed to always show identical data.

  temp_chart_obj <- reactive({                                       # temperature trend; invalidates on city change
    req(input$city_dropdown != "All")
    build_temp_chart(selected_city_data())
  })

  bike_chart_obj <- reactive({                                       # bike demand forecast
    req(input$city_dropdown != "All")
    build_bike_chart(selected_city_data())
  })

  humidity_chart_obj <- reactive({                                   # humidity vs demand scatter
    req(input$city_dropdown != "All")
    build_humidity_chart(selected_city_data())
  })

  # Sidebar outputs — consume shared reactives
  output$temp_line           <- renderPlot({ temp_chart_obj() })    # sidebar temperature chart
  output$bike_line           <- renderPlot({ bike_chart_obj() })    # sidebar bike demand chart
  output$humidity_pred_chart <- renderPlot({ humidity_chart_obj() }) # sidebar humidity chart

  # Modal outputs — same reactive; guaranteed in sync with sidebar
  output$temp_line_modal           <- renderPlot({ temp_chart_obj() })    # expanded temperature chart
  output$bike_line_modal           <- renderPlot({ bike_chart_obj() })    # expanded bike chart
  output$humidity_pred_chart_modal <- renderPlot({ humidity_chart_obj() }) # expanded humidity chart
```

- [ ] **Step 2: Add reactive modal title outputs (insert after the block above)**

```r
  # ── Reactive modal titles ──────────────────────────────────────────────────
  # Static paste() in showModal() evaluates once at click-time. Using renderUI
  # here means the title re-renders whenever input$city_dropdown changes,
  # even if the modal is already open.

  output$modal_title_temp <- renderUI({
    tags$span(
      tags$i(class="glyphicon glyphicon-signal", style="margin-right:8px; color:#008cba;"),
      paste("Temperature — Next 24h —", input$city_dropdown)  # reactive city name
    )
  })

  output$modal_title_bike <- renderUI({
    tags$span(
      tags$i(class="glyphicon glyphicon-stats", style="margin-right:8px; color:#43ac6a;"),
      paste("Bike Demand — Next 24h —", input$city_dropdown)
    )
  })

  output$modal_title_humidity <- renderUI({
    tags$span(
      tags$i(class="glyphicon glyphicon-tint", style="margin-right:8px; color:#004e7c;"),
      paste("Humidity vs Demand — 24h —", input$city_dropdown)
    )
  })
```

- [ ] **Step 3: Update the 3 `observeEvent` modal calls (lines ~449–498) to use `uiOutput` titles**

Replace each static `title = tags$span(...)` in `showModal(modalDialog(...))` with the
corresponding `uiOutput`. Change all three:

**expand_temp** (line ~449):
```r
  observeEvent(input$expand_temp, {
    showModal(modalDialog(
      title     = uiOutput("modal_title_temp"),                      # reactive title — updates on city change
      tags$div(class = "modal-chart-body",
               plotOutput("temp_line_modal", height = "430px")),
      footer    = modalButton("Close"),
      size      = "l",
      easyClose = TRUE
    ))
  })
```

**expand_bike** (line ~466):
```r
  observeEvent(input$expand_bike, {
    showModal(modalDialog(
      title     = uiOutput("modal_title_bike"),                      # reactive title
      tags$div(class = "modal-chart-body",
               plotOutput("bike_line_modal", height = "430px")),
      footer    = modalButton("Close"),
      size      = "l",
      easyClose = TRUE
    ))
  })
```

**expand_humidity** (line ~483):
```r
  observeEvent(input$expand_humidity, {
    showModal(modalDialog(
      title     = uiOutput("modal_title_humidity"),                  # reactive title
      tags$div(class = "modal-chart-body",
               plotOutput("humidity_pred_chart_modal", height = "430px")),
      footer    = modalButton("Close"),
      size      = "l",
      easyClose = TRUE
    ))
  })
```

- [ ] **Step 4: Delete the now-redundant separate `renderPlot` blocks for modal outputs**

The old `output$temp_line_modal`, `output$bike_line_modal`, and
`output$humidity_pred_chart_modal` `renderPlot` calls (lines ~461–498) are now replaced
by the shared reactive outputs in Step 1. Delete the old standalone versions:

```r
# DELETE these three — they are now in the shared reactive block:
output$temp_line_modal <- renderPlot({
  req(input$city_dropdown != "All")
  build_temp_chart(selected_city_data())
})

output$bike_line_modal <- renderPlot({
  req(input$city_dropdown != "All")
  build_bike_chart(selected_city_data())
})

output$humidity_pred_chart_modal <- renderPlot({
  req(input$city_dropdown != "All")
  build_humidity_chart(selected_city_data())
})
```

- [ ] **Step 5: Commit**

```
git add shiny_app/server.R
git commit -m "fix(server): shared chart reactives; modal titles now reactive to city dropdown"
```

---

## Task 6: `ui.R` — CSS fixes + Feed Health panel + modal title slots

**Files:**
- Modify: `shiny_app/ui.R`

Three independent changes: two CSS additions, one new `uiOutput` slot in the sidebar.
The modal titles already have their server-side `renderUI` from Task 5 — no `ui.R`
changes are needed for them because `uiOutput("modal_title_temp")` is passed directly
inside `showModal()` in `server.R`, not declared in `ui.R`.

- [ ] **Step 1: Add `max-height` + `overflow-y` to `.dash-left` CSS (around line 62)**

Find this block:
```css
        .dash-left {
          width: 250px;
          min-width: 250px;
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
```

Replace with:
```css
        .dash-left {
          width: 250px;
          min-width: 250px;
          display: flex;
          flex-direction: column;
          gap: 12px;
          max-height: calc(100vh - 80px);   /* match dash-right; prevents page overflow */
          overflow-y: auto;                  /* sidebar scrolls internally when Feed Health panel added */
        }
```

- [ ] **Step 2: Add ellipsis to `.chart-header span` CSS (around line 109)**

Find:
```css
        .chart-header span {
          font-family: 'Barlow Condensed', sans-serif;
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 1.2px;
          text-transform: uppercase;
          color: #008cba;
        }
```

Replace with:
```css
        .chart-header span {
          font-family: 'Barlow Condensed', sans-serif;
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 1.2px;
          text-transform: uppercase;
          color: #008cba;
          white-space: nowrap;              /* keep title on one line */
          overflow: hidden;                 /* clip overflow rather than wrap */
          text-overflow: ellipsis;          /* show … when title is too wide for 280px pane */
          max-width: 200px;                 /* leave room for expand button in same flex row */
        }
```

- [ ] **Step 3: Insert Feed Health panel in the left sidebar**

In the Live Map tab's left sidebar section, find the "Filter by Demand" `dash-card` block
(ends around line 314). Insert the Feed Health `uiOutput` card **immediately after it**,
before the "Coverage" card:

```r
                        # Feed Health panel — rendered server-side via output$feed_health_panel
                        # Colour-coded rows: green (LIVE) / amber (DELAYED) / red (UNAVAILABLE)
                        # Always expanded so the user can see feed status at a glance
                        tags$div(class = "dash-card", style = "padding:0; overflow:hidden;",
                                 uiOutput("feed_health_panel")
                        ),
```

- [ ] **Step 4: Run the app and verify visually**

Start the app:
```r
Rscript -e "library(shiny); runApp('shiny_app', port=3839, launch.browser=FALSE)"
```

Open `http://localhost:3839`. Check:

1. Feed Health panel appears in the left sidebar between "Filter by Demand" and "Coverage"
2. Cities initially show grey "…" (loading state) then flip to coloured rows within ~10 seconds
3. All 6 cities show a status row with badge and plain-English text
4. Sidebar does not overflow the page when all rows are visible — scrolls internally if needed
5. Chart title "Peak Demand by City — Next 24h" in right panel shows `…` ellipsis if clipped

- [ ] **Step 5: Test modal expand is now dynamic**

While app is running:

1. Select "London" from city dropdown — wait for charts to render
2. Click the fullscreen icon on "Temperature — Next 24 Hours"
3. Modal opens — title should read "Temperature — Next 24h — London"
4. **Without closing the modal**, change city dropdown to "Paris"
5. The chart inside the modal should update to Paris (same reactive)
6. The modal title should update to "Temperature — Next 24h — Paris"
7. Close modal, reopen — title and chart should match Paris

- [ ] **Step 6: Commit**

```
git add shiny_app/ui.R
git commit -m "fix(ui): dash-left overflow scroll; chart-header ellipsis; wire feed_health_panel"
```

---

## Task 7: Final verification + workflow update

- [ ] **Step 1: Run full app and cycle through all 6 cities**

```r
Rscript -e "library(shiny); runApp('shiny_app', port=3839, launch.browser=FALSE)"
```

Verify for each city (Seoul, London, New York, Paris, Chicago, Washington DC):
- Map markers appear within 10 seconds of startup
- Feed Health panel shows correct badge colour (all should be green with live APIs)
- Temperature, Bike Demand, Humidity charts render correctly in sidebar
- Expand icon on each chart opens a modal with the correct city name in the title

- [ ] **Step 2: Simulate a feed failure to test amber/red states**

In `gbfs_client.R`, temporarily force Paris to return `EMPTY_STATIONS_SCHEMA`:

```r
# Temporary test-only change in parse_gbfs_stations() — revert after test
if (cfg$type == "gbfs" && city_name == "Paris") return(EMPTY_STATIONS_SCHEMA)
```

Restart the app. After the first timer fire (~10 seconds):
- Paris row should show amber "DELAYED" badge (failure count = 1)
- After 3 timer cycles (~30 seconds in dev; use `reactiveTimer(5000)` temporarily to speed up):
  Paris row should turn red "UNAVAILABLE"
- All other cities remain green
- Paris map shows the cluster fallback marker (city-centre weather point), not an empty map

Revert the test change:
```r
# Remove the temporary test line from parse_gbfs_stations()
```

- [ ] **Step 3: Push to remote**

```
git push origin main
```

- [ ] **Step 4: Update workflow_status.md**

Update `C:\Users\deepa\.claude\projects\D--OneDrive-Developer-DataAnalytics-R-projects-bike-demand-prediction\memory\workflow_status.md`:
- Tick the Feed Health alerting phase as complete
- Record: 5-min refresh timer added, `live_stations_df` now a `reactiveVal`, modal chart bug fixed

---

## Self-Review Checklist

**Spec coverage:**
- [x] Enriched return from `gbfs_client.R` → Task 1
- [x] `feed_state` reactiveValues with failure-count thresholds → Task 3
- [x] `build_feed_status_text()` helper → Task 2
- [x] `update_feed_state()` helper → Task 2
- [x] 5-minute reactive timer (implicit in spec, required by implementation) → Task 3
- [x] `live_stations_df` as reactiveVal; 3 call-site updates → Task 3 Step 2
- [x] `feed_health_df` reactive + `renderUI` → Task 4
- [x] Shared chart reactives → Task 5 Step 1
- [x] Reactive modal titles → Task 5 Steps 2 + 3
- [x] Delete stale standalone modal `renderPlot` calls → Task 5 Step 4
- [x] `.dash-left` overflow CSS → Task 6 Step 1
- [x] `.chart-header span` ellipsis CSS → Task 6 Step 2
- [x] `uiOutput("feed_health_panel")` in sidebar → Task 6 Step 3
- [x] Seoul sample-key special-case text → covered in `build_feed_status_text()`
- [x] Loading state → covered in `feed_state` init + `build_feed_status_text()`

**Type consistency check:**
- `get_city_live_stations()` returns `list(data, status, row_count, fetched_at, message)`
- `update_feed_state(feed_state, city, result)` reads `result$status`, `result$row_count`, `result$fetched_at`, `result$message` — all match
- `feed_state[[city]]` stores `list(failures, status, row_count, fetched_at, message)` — matches `build_feed_status_text(r)` field access (`r$status`, `r$failures`, `r$row_count`, `r$fetched_at`, `r$city`)
- `feed_health_df()` returns list of lists with fields `city, status, failures, row_count, fetched_at, message` — all consumed correctly in `renderUI`
- `temp_chart_obj`, `bike_chart_obj`, `humidity_chart_obj` defined as `reactive({})` — consumed as `temp_chart_obj()` in `renderPlot` — consistent

**Placeholder scan:** None found. All steps contain complete code.
