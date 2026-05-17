# Feed Health Alerting — Design Spec
**Date:** 2026-05-17  
**Status:** Approved  
**Scope:** Live Map tab — sidebar status panel + modal expand bug fix  

---

## Problem

When a city's live station feed fails, the Bikecast app silently shows an empty map.
The 24-hour forecast still renders (it runs independently via OpenWeather + ML model),
but the user has no way to distinguish "no bikes available" from "the feed is down."

This spec defines a Feed Health panel in the left sidebar that surfaces feed status
at a glance, using colour-coded rows and plain-English text — never technical jargon.

---

## Design Principles Applied

- **One-scan clarity**: status is readable at a glance — colour → label → detail text, in that order.
- **Progressive disclosure**: summary state always visible; plain-English reason available without scrolling.
- **Non-intrusive**: always-on panel, never a pop-up or toast; forecast context always stated so users know what still works.
- **YAGNI**: no retry button, no status history log, no per-city refresh rate control.

---

## Status States

| State | Trigger | Badge label | Row background | Left border |
|---|---|---|---|---|
| `loading` | App just started; first fetch not yet complete | *(spinner dot)* | `#f8f8f8` | `#cccccc` |
| `green` | Last fetch returned ≥ 1 row (`status = "ok"`) | `LIVE` | `#f0faf2` | `#27ae60` |
| `amber` | 1–2 consecutive failed fetches | `DELAYED` | `#fffbf0` | `#f39c12` |
| `red` | 3+ consecutive failed fetches | `UNAVAILABLE` | `#fff5f5` | `#e74c3c` |

On any successful fetch, failure count resets to 0 regardless of prior state.

---

## Human-Readable Status Text

| State | Text shown |
|---|---|
| `loading` | *Connecting to station data…* |
| `green` | All {N} stations reporting normally. |
| `green` (Seoul sample key) | Showing 5 demo stations (sample key). Full data requires a Seoul API key. |
| `amber` (1st fail) | Station data is being refreshed — last update {N} minutes ago. Forecast is unaffected. |
| `amber` (2nd fail) | Waiting for station data — retrying shortly. Forecast is unaffected. |
| `red` | Station map is temporarily unavailable. Your 24-hour forecast is still running. |

Station count `{N}` is taken from `row_count` in the enriched return — never hardcoded.

---

## Architecture

```
5-min reactive timer
        │
        ▼
get_live_stations(city)          ← gbfs_client.R
        │
        ▼
list(data, status, row_count,    ← enriched return (new)
     fetched_at, message)
        │
        ▼
update feed_state[[city]]        ← reactiveValues in server.R
        │  failure count → derives green / amber / red
        ▼
feed_health_df reactive          ← collapses all city states
        │
        ▼
renderUI("feed_health_panel")    ← left sidebar, re-renders on each city fetch
```

---

## Component A — `gbfs_client.R`: Enriched Return

### What changes

`get_live_stations(city)` currently returns a bare tibble (or `EMPTY_STATIONS_SCHEMA`
on failure). It changes to return a named list.

### Return structure

```r
list(
  data       = tibble,          # station rows, or EMPTY_STATIONS_SCHEMA on failure
  status     = "ok" | "error",  # set inside client at point of knowledge
  row_count  = integer,         # nrow(data); 0 on failure
  fetched_at = POSIXct,         # Sys.time() at moment of return
  message    = character | NULL # NULL on success; plain-English reason on error
)
```

### Scope of change

- **Dispatcher only** (Section 5 of `gbfs_client.R`): wraps each parser's output in the list above.
- **Parser internals unchanged**: `parse_gbfs_v2`, `parse_tfl_bikepoint`, `parse_seoul_openapi` return tibbles exactly as today.
- **Every call site in `server.R`** updates from `result` → `result$data` (mechanical find-and-replace).

### On success (inside dispatcher)

```r
list(
  data       = parsed_tibble,
  status     = "ok",
  row_count  = nrow(parsed_tibble),
  fetched_at = Sys.time(),
  message    = NULL
)
```

### On failure (wraps the existing `EMPTY_STATIONS_SCHEMA` return)

```r
list(
  data       = EMPTY_STATIONS_SCHEMA,
  status     = "error",
  row_count  = 0L,
  fetched_at = Sys.time(),
  message    = "Reason in plain English"  # e.g. "API timeout after 10s"
)
```

> **VS Code aside — explore without risk:**  
> Open `shiny_app/gbfs_client.R` in VS Code. Press `Ctrl+Shift+O` (Go to Symbol) and
> type `get_live_stations` to jump straight to the function definition. The R extension
> (ms-vscode.vscode-r) gives you syntax highlighting and a symbol outline for free.
> No changes needed — just orient yourself to where the dispatcher lives (Section 5).

---

## Component B — `server.R`: Feed State Tracking

### Reactive state store

```r
# ── Feed Health State ──────────────────────────────────────────────────────
# One entry per city; initialised to "loading" so the panel shows immediately.
feed_state <- reactiveValues(
  Seoul         = list(failures = 0L, status = "loading", row_count = 0L, fetched_at = NULL, message = NULL),
  London        = list(failures = 0L, status = "loading", row_count = 0L, fetched_at = NULL, message = NULL),
  `New York`    = list(failures = 0L, status = "loading", row_count = 0L, fetched_at = NULL, message = NULL),
  Paris         = list(failures = 0L, status = "loading", row_count = 0L, fetched_at = NULL, message = NULL),
  Chicago       = list(failures = 0L, status = "loading", row_count = 0L, fetched_at = NULL, message = NULL),
  `Washington DC` = list(failures = 0L, status = "loading", row_count = 0L, fetched_at = NULL, message = NULL)
)
```

### Update logic (runs after each city fetch, inside the reactive timer)

```r
update_feed_state <- function(city, result) {
  if (result$status == "ok") {
    feed_state[[city]] <- list(
      failures   = 0L,
      status     = "green",
      row_count  = result$row_count,
      fetched_at = result$fetched_at,
      message    = NULL
    )
  } else {
    prev_failures <- feed_state[[city]]$failures
    new_failures  <- prev_failures + 1L
    feed_state[[city]] <- list(
      failures   = new_failures,
      status     = if (new_failures >= 3L) "red" else "amber",
      row_count  = 0L,
      fetched_at = result$fetched_at,
      message    = result$message
    )
  }
}
```

### Derived reactive for the panel

```r
feed_health_df <- reactive({
  cities <- c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC")
  lapply(cities, function(city) {
    s <- feed_state[[city]]
    list(city = city, status = s$status, failures = s$failures,
         row_count = s$row_count, fetched_at = s$fetched_at, message = s$message)
  })
})
```

> **VS Code aside — explore without risk:**  
> Open `shiny_app/server.R`. Press `Ctrl+F` and search for `reactiveValues` to see
> all existing reactive state stores. Compare their pattern to the `feed_state` design
> above — notice how the initialisation list will mirror them. No edits needed;
> just read to build the mental model.

---

## Component C — `server.R`: Shared Chart Reactives (Modal Bug Fix)

### Root cause

The three modal plots (`temp_line_modal`, `bike_line_modal`, `humidity_pred_chart_modal`)
each run an independent `renderPlot` call that re-invokes `build_*_chart(selected_city_data())`.
There is no shared cache — the sidebar and modal compute the same chart from scratch,
independently. Modal titles are static strings evaluated at click-time, so they go stale
if the city changes while the modal is open.

### Fix: shared reactive chart expressions

```r
# ── Shared chart reactives — sidebar and modal consume the same computed object ──
temp_chart_obj     <- reactive({
  req(input$city_dropdown != "All")
  build_temp_chart(selected_city_data())
})
bike_chart_obj     <- reactive({
  req(input$city_dropdown != "All")
  build_bike_chart(selected_city_data())
})
humidity_chart_obj <- reactive({
  req(input$city_dropdown != "All")
  build_humidity_chart(selected_city_data())
})

# Sidebar outputs consume the shared reactive
output$temp_line            <- renderPlot({ temp_chart_obj() })
output$bike_line            <- renderPlot({ bike_chart_obj() })
output$humidity_pred_chart  <- renderPlot({ humidity_chart_obj() })

# Modal outputs consume the same shared reactive — always in sync
output$temp_line_modal          <- renderPlot({ temp_chart_obj() })
output$bike_line_modal          <- renderPlot({ bike_chart_obj() })
output$humidity_pred_chart_modal <- renderPlot({ humidity_chart_obj() })
```

### Modal title fix

Replace static `paste("Temperature — Next 24h —", input$city_dropdown)` in each
`showModal()` with a `uiOutput` slot that is rendered server-side:

```r
output$modal_title_temp     <- renderUI({ tags$span("Temperature — Next 24h — ", input$city_dropdown) })
output$modal_title_bike     <- renderUI({ tags$span("Bike Demand — Next 24h — ", input$city_dropdown) })
output$modal_title_humidity <- renderUI({ tags$span("Humidity vs Demand — 24h — ", input$city_dropdown) })
```

In each `showModal(modalDialog(title = uiOutput("modal_title_temp"), ...))` — the title
slot now re-renders whenever the city changes, even while the modal is open.

> **VS Code aside — explore without risk:**  
> In `server.R`, use `Ctrl+Shift+F` (global search across all files) and search for
> `renderPlot`. You'll see all current render calls listed in the search panel on the
> left. This gives you a bird's-eye view of every chart output in the app — useful for
> confirming the before/after scope of the shared-reactive refactor without opening
> each file individually.

---

## Component D — `ui.R`: Layout Fixes + Feed Health Panel

### Fix 1 — Left sidebar overflow

Add to `.dash-left` CSS:

```css
.dash-left {
  /* existing */
  width: 250px;
  min-width: 250px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  /* new */
  max-height: calc(100vh - 80px);
  overflow-y: auto;
}
```

Mirrors the existing treatment on `.dash-right`. The sidebar now scrolls internally
rather than pushing the page when Feed Health rows are added.

### Fix 2 — Right sidebar chart title truncation

Add to `.chart-header span` CSS:

```css
.chart-header span {
  /* existing */
  font-family: 'Barlow Condensed', sans-serif;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 1.2px;
  text-transform: uppercase;
  color: #008cba;
  /* new */
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 200px;
}
```

Prevents hard clip on titles like "Peak Demand by City — Next 24h".

### Feed Health Panel insertion point

Inserted in the left sidebar between "Filter by Demand" and "Coverage":

```r
# Feed Health panel — rendered server-side; fully reactive
tags$div(class = "dash-card", style = "padding: 0; overflow: hidden;",
  uiOutput("feed_health_panel")
)
```

### Feed Health panel render (server.R `renderUI`)

```r
output$feed_health_panel <- renderUI({
  rows <- feed_health_df()
  # header
  header <- tags$div(
    style = "padding:10px 12px 6px; border-bottom:1px solid #ddd;",
    tags$div(style = "font-size:11px; text-transform:uppercase; font-weight:700;
                      letter-spacing:0.05em; color:#555;", "Live Data Status"),
    tags$div(style = "font-size:11px; color:#888; margin-top:2px;",
             "Refreshes every 5 minutes")
  )
  # one row per city
  city_rows <- lapply(rows, function(r) {
    cfg <- switch(r$status,
      loading     = list(bg="#f8f8f8", border="#ccc",    badge_bg="#aaa",     label="…"),
      green       = list(bg="#f0faf2", border="#27ae60", badge_bg="#27ae60",  label="LIVE"),
      amber       = list(bg="#fffbf0", border="#f39c12", badge_bg="#f39c12",  label="DELAYED"),
      red         = list(bg="#fff5f5", border="#e74c3c", badge_bg="#e74c3c",  label="UNAVAILABLE"),
                    list(bg="#f8f8f8", border="#ccc",    badge_bg="#aaa",     label="?")
    )
    body_text <- build_feed_status_text(r)   # helper — see below
    tags$div(
      style = sprintf("background:%s; border-left:4px solid %s;
                       padding:9px 12px; border-bottom:1px solid #dde;",
                      cfg$bg, cfg$border),
      tags$div(style = "display:flex; justify-content:space-between; align-items:center;",
        tags$span(style = "font-weight:600; color:#1a1a1a; font-size:13px;", r$city),
        tags$span(style = sprintf("background:%s; color:white; font-size:10px;
                                   padding:2px 7px; border-radius:10px; font-weight:600;",
                                  cfg$badge_bg), cfg$label)
      ),
      tags$div(style = "color:#555; font-size:11px; margin-top:3px;", body_text)
    )
  })
  # footer note
  footer <- tags$div(
    style = "padding:8px 12px; background:#f8f8f8; font-size:10px;
             color:#999; border-top:1px solid #ddd;",
    "Station maps show live availability. Forecasts always run independently."
  )
  tagList(header, city_rows, footer)
})
```

### `build_feed_status_text()` helper — plain R function, defined in `server.R` near the feed state block, not a reactive

```r
build_feed_status_text <- function(r) {
  # r: list(city, status, failures, row_count, fetched_at, message)
  if (r$status == "loading") return("Connecting to station data…")
  if (r$status == "green") {
    if (r$city == "Seoul" && r$row_count <= 5L)
      return("Showing 5 demo stations (sample key). Full data requires a Seoul API key.")
    return(paste0("All ", format(r$row_count, big.mark = ","), " stations reporting normally."))
  }
  mins_ago <- if (!is.null(r$fetched_at))
    as.integer(difftime(Sys.time(), r$fetched_at, units = "mins")) else NA_integer_
  if (r$status == "amber") {
    if (!is.na(mins_ago) && mins_ago > 0L)
      return(paste0("Station data is being refreshed — last update ",
                    mins_ago, " minute", if (mins_ago != 1L) "s" else "", " ago. Forecast is unaffected."))
    return("Waiting for station data — retrying shortly. Forecast is unaffected.")
  }
  # red
  return("Station map is temporarily unavailable. Your 24-hour forecast is still running.")
}
```

> **VS Code aside — explore without risk:**  
> In VS Code, open `shiny_app/ui.R`. Click anywhere inside the `.dash-left` CSS block
> (around line 62). Press `Alt+Z` to toggle word-wrap — you'll see the long CSS strings
> wrap to fit the editor width, which is useful for reading dense style blocks.
> Then press `Ctrl+K Ctrl+0` to fold all code regions and get a collapsed outline of
> the entire UI structure. `Ctrl+K Ctrl+J` unfolds everything again. No changes made.

---

## Files Changed (Summary)

| File | Section | Nature of change |
|---|---|---|
| `shiny_app/gbfs_client.R` | Section 5 (dispatcher) | Return type: bare tibble → named list |
| `shiny_app/server.R` | Feed state block (new) | Add `feed_state`, `update_feed_state`, `feed_health_df`, `renderUI` |
| `shiny_app/server.R` | Chart reactives (refactor) | Extract 3 shared `reactive()` chart objects; update 6 `renderPlot` calls |
| `shiny_app/server.R` | Modal observers | Replace static title strings with `uiOutput` slots + 3 new `renderUI` outputs |
| `shiny_app/ui.R` | CSS block | 2 targeted additions: `.dash-left` overflow, `.chart-header span` ellipsis |
| `shiny_app/ui.R` | Left sidebar | Insert `uiOutput("feed_health_panel")` between Filter and Coverage cards |

No new files. No changes to parser internals, model prediction, or other tabs.

---

## Out of Scope

- Manual retry button per city
- Status history / feed log
- Push notifications or email alerts
- Per-city configurable refresh rate
- GCP Stream tab feed health (separate system — BigQuery connectivity, not GBFS)
- Operator and Rider tab alerting (they use the same live station data; their alert design is deferred)

---

## Acceptance Criteria

1. Feed Health panel is always visible in the left sidebar on the Live Map tab.
2. All 6 city rows render with correct colour (green/amber/red/loading) on app start.
3. A city that fails 3 consecutive fetches shows `UNAVAILABLE` in red; recovery resets to green.
4. Status text is plain English — no API codes, HTTP status numbers, or R error messages visible to users.
5. Expanding any chart modal shows the correct city name in the title even if the city dropdown changes while the modal is open.
6. Sidebar and modal charts always show identical data (shared reactive).
7. Left sidebar scrolls internally when content exceeds viewport height — no page-level overflow.
8. Right sidebar chart titles do not hard-clip — they ellipsis gracefully.
