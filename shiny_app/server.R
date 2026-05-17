# =============================================================================
# server.R
# — 24-hour bike demand forecast across 5 cities
# — Dynamic map header showing actual forecast date range
# — All chart titles, axes and legends reflect the 24-hour window
# =============================================================================

if (!require(shiny))     install.packages("shiny")
if (!require(shinyjs))   install.packages("shinyjs")
if (!require(ggplot2))   install.packages("ggplot2")
if (!require(leaflet))   install.packages("leaflet")
if (!require(tidyverse)) install.packages("tidyverse")
if (!require(httr))      install.packages("httr")
if (!require(scales))    install.packages("scales")

source("model_prediction.R")    # weather API + linear regression model
source("gbfs_client.R")         # live GBFS station availability client (Phase 7B)
source("bigquery_client.R")     # BigQuery auth + trend/snapshot queries (Phase 7F)

# ── Phase 7F: authenticate once on server start ───────────────────────────────
# BQ_AVAILABLE is TRUE if GOOGLE_APPLICATION_CREDENTIALS is set and valid.
# All GCP Stream tab outputs gate on this flag before querying BigQuery.
BQ_AVAILABLE <- bq_auth_safe()  # FALSE if not configured — GCP Stream tab shows setup instructions

test_weather_data_generation <- function() {
  tryCatch({                                                           # catch weather API errors (e.g. missing key)
    df <- generate_city_weather_bike_data()                           # live OpenWeather 5-day forecast path
    stopifnot(length(df) > 0)                                        # guard: abort if response is empty
    print(head(df))                                                   # log first rows for debugging
    df                                                                # return live data
  }, error = function(e) {
    warning(paste(                                                     # log the reason but don't crash server
      "[Bikecast demo mode] Weather API unavailable — serving synthetic",
      "24-hour forecast. Error:", conditionMessage(e)
    ))
    generate_demo_weather_data()                                      # static fallback — model.csv predictions
  })
}


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
  stopifnot(is.list(r), !is.null(r$status))                         # guard: caller must supply a valid status record
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
  if (result$status == "ok") {                                       # successful fetch -> green
    feed_state[[city]] <- list(
      failures   = 0L,                                               # reset failure counter
      status     = "green",
      row_count  = result$row_count,
      fetched_at = result$fetched_at,
      message    = NULL
    )
  } else {                                                           # failed fetch -> amber or red
    prev          <- isolate(feed_state[[city]]$failures) %||% 0L   # isolate: read without declaring reactive dep
    new_failures  <- prev + 1L                                       # increment consecutive failure count
    prev_fetched  <- isolate(feed_state[[city]]$fetched_at)          # isolate: read without declaring reactive dep
    feed_state[[city]] <- list(
      failures   = new_failures,
      status     = if (new_failures >= 3L) "red" else "amber",       # 1-2 fails = amber; 3+ = red
      row_count  = 0L,
      fetched_at = prev_fetched,                                     # last time data was successfully received
      message    = result$message
    )
  }
}


shinyServer(function(input, output, session) {
  
  # ---------------------------------------------------------------------------
  # Forecast data fetched once on startup; station data refreshes via reactiveTimer every 5 min
  # Each city now has 8 rows (8 x 3-hour slots = next 24 hours)
  # ---------------------------------------------------------------------------
  city_weather_bike_df <- test_weather_data_generation()

  # ── Feed state + live station data ──────────────────────────────────────────
  # feed_state tracks per-city failure counts and display status.
  # live_stations_df is a reactiveVal: the map re-renders automatically when
  # new station data arrives from the 5-minute timer.

  GBFS_CITIES <- names(CITY_GBFS_CONFIG)                            # derived from config — single source of truth

  feed_state <- reactiveValues(                                      # one entry per city; "loading" until first fetch
    Seoul           = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    London          = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    `New York`      = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    Paris           = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    Chicago         = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL),
    `Washington DC` = list(failures=0L, status="loading", row_count=0L, fetched_at=NULL, message=NULL)
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

  # ── Feed Health panel UI ──────────────────────────────────────────────────
  # Renders a colour-coded row per city. Re-renders whenever feed_state changes
  # (i.e. after every timer fire). Fills uiOutput("feed_health_panel") in ui.R.

  output$feed_health_panel <- renderUI({

    rows <- lapply(GBFS_CITIES, function(city) {                     # one record per city in display order
      s <- feed_state[[city]]                                        # read current city state from reactiveValues
      list(
        city       = city,                                           # CITY_ASCII string for display
        status     = s$status,                                       # "loading" | "green" | "amber" | "red"
        failures   = s$failures,                                     # consecutive failure count
        row_count  = s$row_count,                                    # number of stations returned
        fetched_at = s$fetched_at,                                   # POSIXct of last fetch (or NULL)
        message    = s$message                                       # NULL or plain-English failure reason
      )
    })                                                               # inline feed state collapsing (removed unnecessary reactive)

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
        loading = list(bg="#f8f8f8", border="#cccccc", badge_bg="#aaaaaa", label="..."),
        green   = list(bg="#f0faf2", border="#27ae60", badge_bg="#27ae60", label="LIVE"),
        amber   = list(bg="#fffbf0", border="#f39c12", badge_bg="#f39c12", label="DELAYED"),
        red     = list(bg="#fff5f5", border="#e74c3c", badge_bg="#e74c3c", label="UNAVAILABLE"),
                  list(bg="#f8f8f8", border="#cccccc", badge_bg="#aaaaaa", label="?")  # fallback
      )
      body_text <- build_feed_status_text(r)                        # plain-English status sentence
      tags$div(
        style = sprintf(
          "background:%s; border-left:4px solid %s; padding:9px 12px; border-bottom:1px solid #ddd;",
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
  
  
  # ---------------------------------------------------------------------------
  # Dynamic map header title — shows actual forecast date range from the data
  # ---------------------------------------------------------------------------
  # renderUI() lets us build HTML dynamically so the dates are live values,
  # not hardcoded strings. output$map_date_title fills the uiOutput() in ui.R.
  output$map_date_title <- renderUI({
    tags$div(
      class = "map-title",
      tags$i(class = "glyphicon glyphicon-globe", style = "margin-right:7px;"),
      paste0("24-Hour Bike Demand Forecast  \u2022  ", fmt_start, "  \u2192  ", fmt_end)
    )
  })
  
  
  # ---------------------------------------------------------------------------
  # Demand filter button toggle logic
  # ---------------------------------------------------------------------------
  filter_state <- reactiveValues(low = TRUE, medium = TRUE, high = TRUE)
  
  observeEvent(input$filter_low, {
    filter_state$low <- !filter_state$low
    toggleClass(id = "filter_low", class = "btn-faded", condition = !filter_state$low)
  })
  observeEvent(input$filter_medium, {
    filter_state$medium <- !filter_state$medium
    toggleClass(id = "filter_medium", class = "btn-faded", condition = !filter_state$medium)
  })
  observeEvent(input$filter_high, {
    filter_state$high <- !filter_state$high
    toggleClass(id = "filter_high", class = "btn-faded", condition = !filter_state$high)
  })
  
  active_levels <- reactive({
    lvls <- c()
    if (filter_state$low)    lvls <- c(lvls, "small")
    if (filter_state$medium) lvls <- c(lvls, "medium")
    if (filter_state$high)   lvls <- c(lvls, "large")
    lvls
  })
  
  
  # ===========================================================================
  # PART A — Leaflet map
  # ===========================================================================
  output$city_bike_map <- renderLeaflet({
    
    if (input$city_dropdown == "All") {
      
      filtered <- cities_max_bike %>%
        filter(BIKE_PREDICTION_LEVEL %in% active_levels())
      
      if (length(active_levels()) == 0 || nrow(filtered) == 0) {
        return(leaflet() %>% addTiles() %>% setView(lng = 20, lat = 30, zoom = 2))
      }
      
      leaflet(data = filtered) %>%
        addTiles() %>%
        addCircleMarkers(
          lng = ~LNG, lat = ~LAT,
          radius = ~case_when(
            BIKE_PREDICTION_LEVEL == "small"  ~ 6,
            BIKE_PREDICTION_LEVEL == "medium" ~ 10,
            BIKE_PREDICTION_LEVEL == "large"  ~ 12
          ),
          color = ~case_when(
            BIKE_PREDICTION_LEVEL == "small"  ~ "green",
            BIKE_PREDICTION_LEVEL == "medium" ~ "yellow",
            BIKE_PREDICTION_LEVEL == "large"  ~ "red"
          ),
          popup = ~LABEL
        )
      
    } else {

      selected_city_coords <- cities_max_bike %>% filter(CITY_ASCII == input$city_dropdown)  # city centre for setView

      # Filter live GBFS stations for the selected city; only show stations that are renting
      city_stations <- live_stations_df() %>%                              # () reads current reactiveVal
        filter(CITY_ASCII == input$city_dropdown, IS_RENTING == TRUE)   # exclude closed / out-of-service stations

      if (nrow(city_stations) == 0) {
        # ── Fallback: GBFS unavailable for this city — show city-centre weather marker ──
        # This preserves the pre-Phase-7B behaviour for Seoul (no GBFS) and any failed fetch.
        selected_city <- city_weather_bike_df %>% filter(CITY_ASCII == input$city_dropdown)
        leaflet(data = selected_city) %>%
          addTiles() %>%
          setView(lng  = selected_city_coords$LNG[1],
                  lat  = selected_city_coords$LAT[1],
                  zoom = 12) %>%
          addMarkers(lng = ~LNG, lat = ~LAT,
                     popup          = ~DETAILED_LABEL,
                     clusterOptions = markerClusterOptions())          # cluster weather slots at city centre

      } else {
        # ── Live station layer: one circle marker per GBFS station ──────────────
        # Colour reflects current availability (matches Yeti green/yellow/red palette):
        #   >= 5 bikes → #43ac6a (green  — good supply)
        #    1–4 bikes → #e99002 (yellow — low)
        #      0 bikes → #f04124 (red    — empty)
        leaflet(data = city_stations) %>%
          addTiles() %>%
          setView(lng  = selected_city_coords$LNG[1],
                  lat  = selected_city_coords$LAT[1],
                  zoom = 14) %>%                                        # zoom 14 shows individual station dots
          addCircleMarkers(
            lng    = ~LNG,
            lat    = ~LAT,
            radius = 7,                                                 # fixed radius — size shows location, not demand
            color  = ~ifelse(AVAILABLE_BIKES >= 5, "#43ac6a",          # green: well stocked
                      ifelse(AVAILABLE_BIKES >= 1, "#e99002",          # yellow: low stock
                                                   "#f04124")),        # red: empty
            fillColor = ~ifelse(AVAILABLE_BIKES >= 5, "#43ac6a",
                         ifelse(AVAILABLE_BIKES >= 1, "#e99002",
                                                      "#f04124")),
            fillOpacity = 0.85,                                        # slightly transparent fill
            weight      = 1,                                           # thin border
            popup = ~paste0(                                           # HTML popup — Yeti colour scheme
              "<b style='font-size:13px;'>", STATION_NAME, "</b><br>",
              "<b style='color:", ifelse(AVAILABLE_BIKES >= 5, "#43ac6a",
                                  ifelse(AVAILABLE_BIKES >= 1, "#e99002", "#f04124")), ";'>",
              AVAILABLE_BIKES, " bikes available</b><br>",
              "<span style='color:#666;'>", AVAILABLE_DOCKS, " docks free &nbsp;|&nbsp; Capacity: ", CAPACITY, "</span>"
            )
          )
      }
    }
  })
  
  
  # ===========================================================================
  # RIGHT PANEL — "All" view: city comparison bar chart + summary table
  # ===========================================================================
  
  # Build a horizontal bar chart comparing peak demand across all cities.
  # Colour-coded green/yellow/red to match the map markers.
  # Title and subtitle now reference the 24-hour window with actual dates.
  build_compare_chart <- function(data) {
    level_colours <- c("small" = "#43ac6a", "medium" = "#e99002", "large" = "#f04124")
    
    ggplot(data, aes(x    = reorder(CITY_ASCII, BIKE_PREDICTION),
                     y    = BIKE_PREDICTION,
                     fill = BIKE_PREDICTION_LEVEL)) +
      geom_col(width = 0.6, show.legend = FALSE) +
      geom_text(aes(label = scales::comma(BIKE_PREDICTION)),
                hjust = -0.15, size = 3.2, color = "#333") +
      scale_fill_manual(values = level_colours) +
      scale_y_continuous(expand   = expansion(mult = c(0, 0.25)),
                         labels   = scales::comma) +
      coord_flip() +
      labs(
        title    = "Peak Predicted Demand — Next 24 Hours",
        subtitle = paste0(fmt_start, "  \u2192  ", fmt_end),
        x        = NULL,
        y        = "Predicted Bikes (peak slot)"
      ) +
      theme_minimal() +
      theme(
        plot.title    = element_text(face = "bold", size = 12, color = "#004e7c"),
        plot.subtitle = element_text(size = 9, color = "#666"),
        axis.text.y   = element_text(size = 11, color = "#333"),
        axis.title.x  = element_text(size = 9),
        panel.grid.major.y = element_blank(),
        panel.grid.minor   = element_blank()
      )
  }
  
  output$city_compare_chart <- renderPlot({ build_compare_chart(cities_max_bike) })
  
  observeEvent(input$expand_compare, {
    showModal(modalDialog(
      title = tags$span(
        tags$i(class = "glyphicon glyphicon-stats", style = "margin-right:8px; color:#008cba;"),
        paste0("Peak Demand — All Cities — Next 24 Hours")
      ),
      tags$div(class = "modal-chart-body",
               plotOutput("city_compare_chart_modal", height = "430px")),
      footer    = modalButton("Close"),
      size      = "l",
      easyClose = TRUE
    ))
  })
  output$city_compare_chart_modal <- renderPlot({ build_compare_chart(cities_max_bike) })
  
  
  # City summary table — sorted highest demand first, with coloured level badges
  output$city_summary_table <- renderUI({
    tbl <- cities_max_bike %>%
      arrange(desc(BIKE_PREDICTION)) %>%
      select(CITY_ASCII, BIKE_PREDICTION, BIKE_PREDICTION_LEVEL)
    
    rows <- apply(tbl, 1, function(row) {
      level       <- row["BIKE_PREDICTION_LEVEL"]
      badge_class <- paste0("badge-", level)
      label       <- switch(level, small = "Low", medium = "Medium", large = "High")
      tags$tr(
        tags$td(row["CITY_ASCII"]),
        tags$td(scales::comma(as.numeric(row["BIKE_PREDICTION"]))),
        tags$td(tags$span(class = badge_class, label))
      )
    })
    
    tags$table(
      class = "summary-table",
      tags$thead(tags$tr(
        tags$th("City"),
        tags$th("Peak (24h)"),   # Updated column header
        tags$th("Demand")
      )),
      tags$tbody(rows)
    )
  })
  
  
  # ===========================================================================
  # RIGHT PANEL — City detail charts
  # ===========================================================================
  
  # Prepare selected city data — already limited to 8 slots from the API.
  # FORECASTDATETIME_DT was parsed globally above; TIME_INDEX labels each slot.
  selected_city_data <- reactive({
    city_weather_bike_df %>%
      filter(CITY_ASCII == input$city_dropdown) %>%
      mutate(
        TIME_INDEX  = row_number(),
        # Format x-axis labels as HH:MM (time of day) since we're within 24h
        TIME_LABEL  = format(FORECASTDATETIME_DT, "%H:%M")
      )
  })
  
  
  # ── Chart builder functions ───────────────────────────────────────────────
  # Each function returns a ggplot object reused for both sidebar and modal.
  # All titles and axis labels now reference "24 Hours" and show time (HH:MM).
  
  build_temp_chart <- function(df) {
    city <- unique(df$CITY_ASCII)[1]
    ggplot(df, aes(x = FORECASTDATETIME_DT, y = TEMPERATURE)) +
      geom_line(color = "#008cba", linewidth = 0.9) +
      geom_point(color = "#004e7c", size = 2.5) +
      geom_text(aes(label = paste0(round(TEMPERATURE, 1), "\u00b0C")),
                vjust = -0.9, size = 3, color = "#333") +
      labs(
        title    = paste("Temperature Trend \u2014", city),
        subtitle = paste0("Next 24 Hours  \u2022  ", fmt_start, " \u2192 ", fmt_end),
        x        = "Time of Day (UTC)",
        y        = "Temperature (\u00b0C)"
      ) +
      # Format x-axis as HH:MM — appropriate for a 24-hour window
      scale_x_datetime(date_labels = "%H:%M", date_breaks = "3 hours") +
      theme_minimal() +
      theme(
        plot.title    = element_text(face = "bold", size = 12, color = "#004e7c"),
        plot.subtitle = element_text(size = 9, color = "#666"),
        axis.title    = element_text(size = 9),
        axis.text.x   = element_text(angle = 30, hjust = 1, size = 8),
        panel.grid.minor = element_blank()
      )
  }
  
  build_bike_chart <- function(df) {
    city <- unique(df$CITY_ASCII)[1]
    ggplot(df, aes(x = FORECASTDATETIME_DT, y = BIKE_PREDICTION)) +
      geom_line(color = "#43ac6a", linewidth = 0.9) +
      geom_point(color = "#2d7a4a", size = 2.5) +
      geom_text(aes(label = scales::comma(round(BIKE_PREDICTION))),
                vjust = -0.9, size = 3, color = "#333") +
      labs(
        title    = paste("Bike Demand Forecast \u2014", city),
        subtitle = paste0("Next 24 Hours  \u2022  ", fmt_start, " \u2192 ", fmt_end),
        x        = "Time of Day (UTC)",
        y        = "Predicted Bikes"
      ) +
      scale_x_datetime(date_labels = "%H:%M", date_breaks = "3 hours") +
      theme_minimal() +
      theme(
        plot.title    = element_text(face = "bold", size = 12, color = "#2d7a4a"),
        plot.subtitle = element_text(size = 9, color = "#666"),
        axis.title    = element_text(size = 9),
        axis.text.x   = element_text(angle = 30, hjust = 1, size = 8),
        panel.grid.minor = element_blank()
      )
  }
  
  build_humidity_chart <- function(df) {
    city <- unique(df$CITY_ASCII)[1]
    ggplot(df, aes(x = HUMIDITY, y = BIKE_PREDICTION)) +
      geom_point(color = "#004e7c", alpha = 0.8, size = 3.5) +
      geom_smooth(method  = "lm",
                  formula = y ~ poly(x, 4),
                  color   = "red",
                  fill    = "lightpink",
                  alpha   = 0.3) +
      labs(
        title    = paste("Humidity vs Demand \u2014", city),
        subtitle = "24-Hour forecast window",
        x        = "Humidity (%)",
        y        = "Predicted Bikes"
      ) +
      theme_minimal() +
      theme(
        plot.title    = element_text(face = "bold", size = 12, color = "#004e7c"),
        plot.subtitle = element_text(size = 9, color = "#666"),
        axis.title    = element_text(size = 9),
        panel.grid.minor = element_blank()
      )
  }
  
  
  # ── Shared chart reactives ────────────────────────────────────────────────
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
  output$bike_line_modal           <- renderPlot({ bike_chart_obj() })    # expanded bike demand chart
  output$humidity_pred_chart_modal <- renderPlot({ humidity_chart_obj() }) # expanded humidity chart

  # ── Reactive modal titles ─────────────────────────────────────────────────
  # Static paste() in showModal() evaluates once at click-time. Using renderUI
  # here means the title re-renders whenever input$city_dropdown changes,
  # even if the modal is already open.

  output$modal_title_temp <- renderUI({
    tags$span(
      tags$i(class="glyphicon glyphicon-signal", style="margin-right:8px; color:#008cba;"),
      paste("Temperature — Next 24h —", input$city_dropdown)      # reactive city name in title
    )
  })

  output$modal_title_bike <- renderUI({
    tags$span(
      tags$i(class="glyphicon glyphicon-stats", style="margin-right:8px; color:#43ac6a;"),
      paste("Bike Demand — Next 24h —", input$city_dropdown)      # reactive city name in title
    )
  })

  output$modal_title_humidity <- renderUI({
    tags$span(
      tags$i(class="glyphicon glyphicon-tint", style="margin-right:8px; color:#004e7c;"),
      paste("Humidity vs Demand — 24h —", input$city_dropdown)    # reactive city name in title
    )
  })
  
  # ---------------------------------------------------------------------------
  # Click-to-inspect handlers — one per chart
  # ---------------------------------------------------------------------------
  # Each renderText() reads its own input$*_click, which Shiny populates
  # whenever the user clicks the corresponding plotOutput().
  # $x and $y give the data-space coordinates of the click.
  
  # ── Temperature chart click ──
  # $x = UNIX timestamp (POSIXct axis), $y = temperature in °C
  output$temp_click_output <- renderText({
    click <- input$temp_click
    if (is.null(click)) return("Click a point on the chart above.")
    clicked_time <- as.POSIXct(click$x, origin = "1970-01-01", tz = "UTC")
    paste0(
      "Time=", format(clicked_time, "%H:%M UTC"),
      "\nTemperature=", round(click$y, 1), " °C"
    )
  })
  
  # ── Bike demand chart click ──
  # $x = UNIX timestamp, $y = predicted bike count
  output$bike_click_output <- renderText({
    click <- input$bike_click
    if (is.null(click)) return("Click a point on the chart above.")
    clicked_time <- as.POSIXct(click$x, origin = "1970-01-01", tz = "UTC")
    paste0(
      "Time=", format(clicked_time, "%H:%M UTC"),
      "\nPredicted Bikes=", scales::comma(round(click$y))
    )
  })
  
  # ── Humidity scatter chart click ──
  # $x = humidity %, $y = predicted bike count
  # (no datetime on this chart — x axis is humidity, not time)
  output$humidity_click_output <- renderText({
    click <- input$humidity_click
    if (is.null(click)) return("Click a point on the chart above.")
    paste0(
      "Humidity=", round(click$x, 1), " %",
      "\nPredicted Bikes=", scales::comma(round(click$y))
    )
  })
  
  
  # ── Expand modals ─────────────────────────────────────────────────────────
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
  

  # ===========================================================================
  # OPERATOR TAB (Phase 7D — UC1)
  # Fleet rebalancing view: demand-vs-supply alerts, station heatmap, CSV export
  # ===========================================================================

  # ── Reactives ────────────────────────────────────────────────────────────

  operator_city_data <- reactive({                                          # 8 forecast rows for selected operator city
    city_weather_bike_df %>%                                                # full 5-city 24h forecast frame
      filter(CITY_ASCII == input$operator_city)                             # keep only the operator's chosen city
  })

  operator_stations <- reactive({                                           # live GBFS stations for selected city
    live_stations_df() %>%                                                  # () inside reactive — declares dependency
      filter(CITY_ASCII == input$operator_city, IS_RENTING == TRUE)         # open stations only; skip closed/maintenance
  })

  operator_peak_demand <- reactive({                                        # peak predicted demand in the 24h window
    max(operator_city_data()$BIKE_PREDICTION, na.rm = TRUE)                # single numeric: highest slot for this city
  })

  operator_fleet_summary <- reactive({                                      # aggregate fleet stats for the selected city
    s <- operator_stations()                                                # live station frame
    list(                                                                   # named list for clean downstream access
      total_bikes    = sum(s$AVAILABLE_BIKES, na.rm = TRUE),               # bikes available right now across all stations
      total_docks    = sum(s$AVAILABLE_DOCKS, na.rm = TRUE),               # free dock spaces right now
      total_capacity = sum(s$CAPACITY,        na.rm = TRUE),               # total theoretical capacity (bikes + docks)
      empty_stations = sum(s$AVAILABLE_BIKES == 0, na.rm = TRUE),          # count of stations with zero bikes
      n_stations     = nrow(s)                                             # total operational (IS_RENTING) stations
    )
  })


  # ── Map title ─────────────────────────────────────────────────────────────

  output$operator_map_title <- renderUI({                                   # dynamic header for the operator map
    tags$div(                                                               # title block inside the map-header div
      class = "map-title",
      tags$i(class = "glyphicon glyphicon-wrench", style = "margin-right:7px;"),  # wrench icon — operations context
      paste0("Fleet Rebalancing View — ", input$operator_city)        # city name injected at render time
    )
  })


  # ── Demand-vs-supply alert panels ─────────────────────────────────────────

  output$operator_alerts <- renderUI({                                      # Yeti panel-danger/warning/success alert
    peak  <- operator_peak_demand()                                         # peak predicted bikes for the 24h window
    fleet <- operator_fleet_summary()                                       # fleet totals
    total <- fleet$total_bikes                                              # bikes available across all stations now
    empty <- fleet$empty_stations                                           # zero-bike stations count
    n     <- fleet$n_stations                                               # total operational stations

    if (n == 0) {                                                           # no GBFS data (Seoul or any fetch failure)
      return(tags$div(
        class = "panel panel-info",                                         # Yeti info panel — neutral, not a critical alert
        style = "margin-bottom:0;",
        tags$div(class = "panel-heading",
          tags$h3(class = "panel-title",
            tags$i(class = "glyphicon glyphicon-info-sign", style = "margin-right:6px;"),
            "No Live Station Data"
          )
        ),
        tags$div(class = "panel-body",
          "Live GBFS data is unavailable for this city. ",
          "Demand forecast is shown on the map."
        )
      ))
    }

    ratio <- if (total > 0) peak / total else Inf                          # demand-to-supply ratio (Inf when fleet empty)

    # Choose alert level by ratio
    if (is.infinite(ratio) || ratio >= 1.0) {                              # peak demand meets or exceeds all available bikes
      panel_class <- "panel-danger"                                        # red: critical
      icon_glyph  <- "glyphicon-warning-sign"
      alert_title <- "Critical Supply Shortage"
      alert_body  <- paste0(
        "Peak demand (", scales::comma(peak), " bikes) equals or exceeds ",
        "current availability (", scales::comma(total), " bikes). ",
        "Immediate rebalancing required."
      )
    } else if (ratio >= 0.75) {                                            # demand is 75–99% of availability
      panel_class <- "panel-warning"                                       # amber: low supply warning
      icon_glyph  <- "glyphicon-exclamation-sign"
      alert_title <- "Low Supply Warning"
      alert_body  <- paste0(
        "Peak demand is ", round(ratio * 100), "% of current availability. ",
        "Proactive rebalancing advised before peak hours."
      )
    } else {                                                               # demand is under 75% of availability
      panel_class <- "panel-success"                                       # green: supply adequate
      icon_glyph  <- "glyphicon-ok-sign"
      alert_title <- "Supply Adequate"
      alert_body  <- paste0(
        "Fleet is well-positioned. Peak demand (", scales::comma(peak), " bikes) ",
        "is ", round(ratio * 100), "% of available supply."
      )
    }

    main_panel <- tags$div(                                                 # primary demand-vs-supply alert
      class = paste("panel", panel_class),
      style = "margin-bottom:0;",
      tags$div(class = "panel-heading",
        tags$h3(class = "panel-title",
          tags$i(class = paste("glyphicon", icon_glyph), style = "margin-right:6px;"),
          alert_title
        )
      ),
      tags$div(class = "panel-body", alert_body)
    )

    if (empty > 0) {                                                       # secondary panel: empty station count
      empty_panel <- tags$div(
        class = "panel panel-warning",
        style = "margin-top:12px; margin-bottom:0;",                       # top margin handled inline (inside uiOutput wrapper)
        tags$div(class = "panel-heading",
          tags$h3(class = "panel-title",
            tags$i(class = "glyphicon glyphicon-ban-circle", style = "margin-right:6px;"),
            paste0(empty, " Empty Station", if (empty != 1) "s" else "")  # pluralise correctly
          )
        ),
        tags$div(class = "panel-body",
          paste0(empty, " of ", n, " stations have zero bikes. ",
                 "Priority restock targets shown in red on the map.")
        )
      )
      return(tagList(main_panel, empty_panel))                             # return both panels
    }

    main_panel                                                             # no empty stations — return single panel
  })


  # ── Fleet fill-rate summary with Yeti progress bar ────────────────────────

  output$operator_station_stats <- renderUI({                              # dash-card: fleet fill rate + progress bar
    fleet <- operator_fleet_summary()
    if (fleet$n_stations == 0) return(NULL)                               # hide card if no GBFS data

    fill_pct <- if (fleet$total_capacity > 0)                             # fleet-wide fill rate as integer %
      as.integer(fleet$total_bikes / fleet$total_capacity * 100) else 0L

    bar_class <- if (fill_pct < 20)  "progress-bar-danger"               # red: critically low
                 else if (fill_pct < 60) "progress-bar-warning"          # amber: moderate
                 else "progress-bar-success"                              # green: healthy

    tags$div(class = "dash-card",
      tags$h5("Fleet Status"),
      tags$p(style = "font-size:12px; color:#555; margin-bottom:6px;",
        tags$strong(scales::comma(fleet$total_bikes)), " bikes available across ",
        tags$strong(fleet$n_stations), " stations"
      ),
      tags$div(class = "progress", style = "margin-bottom:4px; height:20px;",  # Bootstrap 3 progress container
        tags$div(
          class = paste("progress-bar", bar_class),                       # Yeti contextual colour applied here
          role  = "progressbar",
          style = paste0("width:", fill_pct, "%; line-height:20px; font-size:12px;"),
          paste0(fill_pct, "% fleet capacity")                            # readable label inside the bar
        )
      ),
      tags$p(style = "font-size:11px; color:#888; margin:0;",
        scales::comma(fleet$total_docks), " dock spaces free"
      )
    )
  })


  # ── Fleet rebalancing Leaflet map ─────────────────────────────────────────

  output$operator_map <- renderLeaflet({                                   # station heatmap: size = capacity, colour = fill rate
    stations    <- operator_stations()                                     # live stations for selected city
    city_coords <- cities_max_bike %>%                                     # city centre row for setView
      filter(CITY_ASCII == input$operator_city)

    centre_lng <- if (nrow(city_coords) > 0) city_coords$LNG[1] else 0   # fallback to 0,0 if city not in data
    centre_lat <- if (nrow(city_coords) > 0) city_coords$LAT[1] else 20

    base_map <- leaflet() %>%                                              # bare Leaflet map
      addTiles() %>%                                                       # OpenStreetMap tile layer
      setView(lng = centre_lng, lat = centre_lat, zoom = 13)              # centre on selected city, street-level zoom

    if (nrow(stations) == 0) {                                            # no GBFS data for this city (Seoul or failure)
      cd <- operator_city_data()                                          # fall back to forecast markers at city centre
      return(base_map %>%
        addMarkers(
          data           = cd,
          lng            = ~LNG, lat = ~LAT,
          popup          = ~paste0("<b>", CITY_ASCII, "</b><br>",
                                   "Forecast: ", scales::comma(BIKE_PREDICTION),
                                   " bikes at ", FORECASTDATETIME),
          clusterOptions = markerClusterOptions()                         # cluster 8 overlapping forecast slots
        )
      )
    }

    # Compute fill rate and rebalancing recommendation per station
    stations <- stations %>%
      mutate(
        fill_rate    = AVAILABLE_BIKES / pmax(CAPACITY, 1L),              # proportion full; pmax avoids division by zero
        fill_pct     = as.integer(round(fill_rate * 100)),                # integer % for popup display
        marker_color = case_when(                                         # urgency colour
          fill_rate < 0.20 ~ "#f04124",                                   # red: < 20% — needs restocking
          fill_rate < 0.60 ~ "#e99002",                                   # amber: 20–60% — monitor
          TRUE             ~ "#43ac6a"                                    # green: 60%+ — adequate or source
        ),
        marker_radius = as.integer(pmax(6L, pmin(20L, CAPACITY %/% 8L))),# scale 6–20px by station capacity
        action = case_when(                                               # operator-facing recommendation text
          fill_rate < 0.20 ~ "RESTOCK — send bikes here",
          fill_rate > 0.80 ~ "SOURCE — bikes can be collected",
          TRUE             ~ "BALANCED — no action needed"
        )
      )

    base_map %>%
      addCircleMarkers(                                                    # one circle per station
        data        = stations,
        lng         = ~LNG, lat = ~LAT,
        radius      = ~marker_radius,                                     # bigger = higher capacity station
        color       = ~marker_color,                                      # border matches fill-rate urgency
        fillColor   = ~marker_color,
        fillOpacity = 0.75,
        weight      = 1.5,
        popup = ~paste0(                                                   # HTML popup with rebalancing context
          "<b style='font-size:13px;'>", STATION_NAME, "</b><br>",
          "<b style='color:", marker_color, ";'>", action, "</b><br>",
          "Fill rate: <b>", fill_pct, "%</b>",
          " (", AVAILABLE_BIKES, " / ", CAPACITY, " bikes)<br>",
          "<span style='color:#666;'>", AVAILABLE_DOCKS, " dock spaces free</span>"
        )
      )
  })


  # ── 24-hour forecast CSV download ─────────────────────────────────────────

  output$download_forecast <- downloadHandler(                             # triggers on "Download 24h CSV" button click
    filename = function() {                                                # dynamic filename: city + date
      paste0(
        "bikecast_",
        tolower(gsub(" ", "_", input$operator_city)),                     # e.g. "new_york"
        "_forecast_",
        format(Sys.Date(), "%Y%m%d"),                                     # e.g. "20260507"
        ".csv"
      )
    },
    content = function(file) {                                            # write operationally relevant columns to CSV
      operator_city_data() %>%                                            # 8 forecast slots for selected city
        select(CITY_ASCII, FORECASTDATETIME, TEMPERATURE, HUMIDITY,       # weather context
               WIND_SPEED, BIKE_PREDICTION, BIKE_PREDICTION_LEVEL) %>%   # demand forecast columns
        write.csv(file, row.names = FALSE)                                # standard CSV; no row index column
    }
  )


  # ===========================================================================
  # RIDER TAB (Phase 7E — UC2)
  # Demand score badges, best-time recommendation, natural-language summary,
  # top-station table, live availability map
  # ===========================================================================

  # ── Reactives ────────────────────────────────────────────────────────────

  rider_city_data <- reactive({                                            # forecast rows for selected rider city
    city_weather_bike_df %>%                                               # full 5-city 24h frame
      filter(CITY_ASCII == input$rider_city) %>%                          # filter to chosen city
      arrange(FORECASTDATETIME_DT)                                        # ensure chronological order
  })

  rider_stations <- reactive({                                             # live GBFS stations for selected rider city
    live_stations_df() %>%                                                 # () inside reactive — re-evaluates on new data
      filter(CITY_ASCII == input$rider_city, IS_RENTING == TRUE)          # open stations only
  })


  # ── Map title ─────────────────────────────────────────────────────────────

  output$rider_map_title <- renderUI({                                     # dynamic Rider map header
    tags$div(
      class = "map-title",
      tags$i(class = "glyphicon glyphicon-map-marker", style = "margin-right:7px;"),
      paste0("Live Station Availability — ", input$rider_city)
    )
  })


  # ── Demand score cards — next 3 forecast slots ────────────────────────────

  output$rider_demand_scores <- renderUI({                                 # 3-up grid of Yeti label demand badges
    df <- rider_city_data() %>% head(3L)                                  # first 3 time slots = next 9 hours
    if (nrow(df) == 0) return(tags$p("No forecast data available."))

    cards <- lapply(seq_len(nrow(df)), function(i) {                      # one card per forecast slot
      row       <- df[i, ]                                                 # single-row data frame
      time_lbl  <- format(row$FORECASTDATETIME_DT, "%H:%M")               # e.g. "09:00"
      level     <- row$BIKE_PREDICTION_LEVEL                               # "small" / "medium" / "large"

      badge_cls <- switch(level,                                           # map level to Yeti label class
        small  = "label label-success",                                    # green  — low demand
        medium = "label label-warning",                                    # amber  — moderate demand
        large  = "label label-danger",                                     # red    — high demand
        "label label-default"                                              # fallback
      )
      demand_text <- switch(level,
        small  = "Low", medium = "Med", large = "High", "?"               # short text fits inside badge
      )

      tags$div(class = "col-xs-4", style = "padding:4px;",               # Bootstrap 3: 3 equal columns
        tags$div(class = "well well-sm demand-card",                      # Yeti well as card background
          tags$p(class = "demand-time", time_lbl),                        # time slot label
          tags$span(class = paste(badge_cls, "demand-badge"), demand_text),# coloured demand badge
          tags$p(class = "demand-bikes",                                  # predicted count below badge
            scales::comma(row$BIKE_PREDICTION)
          )
        )
      )
    })

    tags$div(class = "row", style = "margin:0;", cards)                   # Bootstrap grid row containing 3 cards
  })


  # ── Best time to ride recommendation ──────────────────────────────────────

  output$rider_best_time <- renderUI({                                     # lowest-demand slot in 24h window
    df <- rider_city_data()
    if (nrow(df) == 0) return(NULL)

    best_row   <- df %>% slice_min(BIKE_PREDICTION, n = 1L, with_ties = FALSE)  # slot with fewest predicted bikes
    best_time  <- format(best_row$FORECASTDATETIME_DT, "%H:%M")          # e.g. "14:00"
    best_pred  <- scales::comma(best_row$BIKE_PREDICTION)                 # formatted integer
    first_time <- format(df$FORECASTDATETIME_DT[1], "%H:%M")             # next (soonest) slot time

    is_now     <- best_time == first_time                                 # TRUE if best time is now
    time_desc  <- if (is_now) "Now (next 3 hours)" else paste0("Around ", best_time)

    level     <- best_row$BIKE_PREDICTION_LEVEL
    badge_cls <- switch(level,                                            # Yeti label for the best-slot demand level
      small  = "label label-success",
      medium = "label label-warning",
      large  = "label label-danger",
      "label label-default"
    )
    level_text <- switch(level,
      small = "Low", medium = "Moderate", large = "High", "Unknown"
    )

    tags$div(class = "dash-card",
      tags$h5("Best Time to Ride Today"),
      tags$div(class = "well", style = "padding:12px; margin-bottom:0; background:#f9fbfc;",
        tags$p(style = "margin:0 0 5px;",                                # time with clock icon
          tags$i(class = "glyphicon glyphicon-time",
                 style = "color:#43ac6a; margin-right:6px;"),
          tags$strong(time_desc)
        ),
        tags$p(style = "font-size:12px; color:#555; margin:0;",          # demand level + count
          "Demand: ", tags$span(class = badge_cls, level_text),
          " — ", best_pred, " bikes predicted"
        )
      )
    )
  })


  # ── Natural-language availability summary ─────────────────────────────────

  output$rider_summary <- renderUI({                                       # plain-language 3-sentence summary
    df       <- rider_city_data()
    stations <- rider_stations()
    if (nrow(df) == 0) return(NULL)

    first_row  <- df %>% slice(1L)                                        # soonest forecast slot
    city       <- first_row$CITY_ASCII                                    # city name for prose
    level      <- first_row$BIKE_PREDICTION_LEVEL
    now_pred   <- scales::comma(first_row$BIKE_PREDICTION)                # formatted bikes count

    level_class <- switch(level,                                          # Yeti label for inline badge
      small  = "label label-success",
      medium = "label label-warning",
      large  = "label label-danger",
      "label label-default"
    )
    level_word <- switch(level,
      small = "LOW", medium = "MODERATE", large = "HIGH", "UNKNOWN"      # uppercase for badge text
    )

    has_gbfs    <- nrow(stations) > 0                                     # whether live data is available
    total_bikes <- if (has_gbfs) scales::comma(sum(stations$AVAILABLE_BIKES, na.rm = TRUE)) else NULL
    n_stations  <- nrow(stations)

    best_row    <- df %>% slice_min(BIKE_PREDICTION, n = 1L, with_ties = FALSE)
    best_time   <- format(best_row$FORECASTDATETIME_DT, "%H:%M")
    first_time  <- format(first_row$FORECASTDATETIME_DT, "%H:%M")

    tags$div(class = "dash-card",
      tags$h5("Availability Summary"),
      tags$div(class = "well",
               style = "padding:12px; margin-bottom:0; font-size:12.5px; line-height:1.65; color:#444;",

        # Line 1: current demand level
        tags$p(style = "margin:0 0 7px;",
          "Demand in ", tags$strong(city), " right now: ",
          tags$span(class = level_class, level_word),
          " (", now_pred, " bikes predicted)."
        ),

        # Line 2: live fleet availability (or absence of data)
        if (has_gbfs)
          tags$p(style = "margin:0 0 7px;",
            tags$strong(total_bikes), " bikes available across ",
            tags$strong(n_stations), " open stations."
          )
        else
          tags$p(style = "margin:0 0 7px; color:#888; font-style:italic;",
            "Live station data is unavailable for this city."
          ),

        # Line 3: best-time hint
        if (best_time != first_time)
          tags$p(style = "margin:0;",
            tags$i(class = "glyphicon glyphicon-thumbs-up",
                   style = "color:#43ac6a; margin-right:4px;"),
            "Quietest window today: ", tags$strong(best_time),
            " — a good time to plan your ride."
          )
        else
          tags$p(style = "margin:0;",
            tags$i(class = "glyphicon glyphicon-thumbs-up",
                   style = "color:#43ac6a; margin-right:4px;"),
            "Now is already the quietest window in today's forecast."
          )
      )
    )
  })


  # ── Top-5 stations by available bikes ─────────────────────────────────────

  output$rider_station_table <- renderUI({                                 # Yeti table-striped + label badges
    stations <- rider_stations()

    if (nrow(stations) == 0) {                                            # no GBFS for this city
      return(tags$div(class = "dash-card",
        tags$h5("Live Station Availability"),
        tags$p(style = "font-size:12px; color:#888; margin:0;",
          "No live data available for this city."
        )
      ))
    }

    top <- stations %>%
      arrange(desc(AVAILABLE_BIKES)) %>%                                  # highest-stocked first
      head(5L)                                                             # top 5 — fits sidebar without scrolling

    rows <- lapply(seq_len(nrow(top)), function(i) {                      # one table row per station
      s     <- top[i, ]
      avail <- s$AVAILABLE_BIKES

      status_cls  <- if (avail >= 5) "label label-success"               # green: good supply
                     else if (avail >= 1) "label label-warning"          # amber: low supply
                     else "label label-danger"                           # red: empty
      status_text <- if (avail >= 5) "Good" else if (avail >= 1) "Low" else "Empty"

      name <- s$STATION_NAME                                              # truncate long names for narrow column
      if (nchar(name) > 22) name <- paste0(substr(name, 1L, 20L), "…")

      tags$tr(
        tags$td(name, style = "font-size:11px;"),
        tags$td(avail, style = "font-size:11px; text-align:center;"),
        tags$td(style = "text-align:center;",
          tags$span(class = status_cls, status_text)                     # Yeti label badge
        )
      )
    })

    tags$div(class = "dash-card",
      tags$h5("Top Stations — Live Availability"),
      tags$table(
        class = "table table-striped table-condensed table-hover",        # Yeti Bootstrap 3 table classes
        style = "margin-bottom:0; font-size:12px;",
        tags$thead(
          tags$tr(
            tags$th("Station"),
            tags$th(style = "text-align:center;", "Bikes"),
            tags$th(style = "text-align:center;", "Status")
          )
        ),
        tags$tbody(rows)
      )
    )
  })


  # ── Rider live station availability map ───────────────────────────────────

  output$rider_map <- renderLeaflet({                                     # same colour logic as Live Map (Phase 7B)
    stations    <- rider_stations()
    city_coords <- cities_max_bike %>% filter(CITY_ASCII == input$rider_city)

    centre_lng <- if (nrow(city_coords) > 0) city_coords$LNG[1] else 0
    centre_lat <- if (nrow(city_coords) > 0) city_coords$LAT[1] else 20

    base_map <- leaflet() %>%
      addTiles() %>%
      setView(lng = centre_lng, lat = centre_lat, zoom = 14)              # street-level zoom for finding stations

    if (nrow(stations) == 0) {                                            # Seoul / GBFS failure fallback
      cd <- rider_city_data()
      return(base_map %>%
        addMarkers(
          data           = cd,
          lng            = ~LNG, lat = ~LAT,
          popup          = ~paste0("<b>", CITY_ASCII, "</b><br>",
                                   "Forecast: ", scales::comma(BIKE_PREDICTION),
                                   " bikes at ", FORECASTDATETIME),
          clusterOptions = markerClusterOptions()
        )
      )
    }

    # Colour by available bikes: green (>=5), amber (1-4), red (0)
    # Consistent with Live Map palette so riders recognise the scheme
    base_map %>%
      addCircleMarkers(
        data        = stations,
        lng         = ~LNG, lat = ~LAT,
        radius      = 7,                                                  # fixed radius — size = location, not demand
        color       = ~ifelse(AVAILABLE_BIKES >= 5, "#43ac6a",
                       ifelse(AVAILABLE_BIKES >= 1, "#e99002", "#f04124")),
        fillColor   = ~ifelse(AVAILABLE_BIKES >= 5, "#43ac6a",
                       ifelse(AVAILABLE_BIKES >= 1, "#e99002", "#f04124")),
        fillOpacity = 0.85,
        weight      = 1,
        popup = ~paste0(
          "<b style='font-size:13px;'>", STATION_NAME, "</b><br>",
          "<b style='color:",
          ifelse(AVAILABLE_BIKES >= 5, "#43ac6a",
          ifelse(AVAILABLE_BIKES >= 1, "#e99002", "#f04124")),
          ";'>", AVAILABLE_BIKES, " bikes available</b><br>",
          "<span style='color:#666;'>",
          AVAILABLE_DOCKS, " docks free | Capacity: ", CAPACITY, "</span>"
        )
      )
  })


  # ===========================================================================
  # GCP STREAM TAB (Phase 7F)
  # Live station availability from BigQuery (written by Dataflow pipeline).
  # Queries bike-demand-ml-system.bike_demand.station_snapshots every 5 minutes.
  # ===========================================================================

  # ── 5-minute auto-refresh timer ──────────────────────────────────────────────
  bq_timer <- reactiveTimer(300000)                        # fire every 300 000 ms (5 minutes)

  # ── Manual refresh trigger ────────────────────────────────────────────────────
  bq_refresh_counter <- reactiveVal(0L)                    # incremented by the Refresh Now button
  observeEvent(input$bq_refresh, {
    bq_refresh_counter(bq_refresh_counter() + 1L)         # bumping the counter invalidates bq_trend/bq_latest
  })

  # ── Last successful refresh timestamp ────────────────────────────────────────
  bq_last_refresh <- reactiveVal(NULL)                     # set to Sys.time() each time a query returns rows

  # ── BQ trend data reactive ────────────────────────────────────────────────────
  # Re-executes on: 5-min timer, manual refresh, or city dropdown change.
  bq_trend <- reactive({
    bq_timer()                                             # auto-refresh dependency
    bq_refresh_counter()                                   # manual refresh dependency
    if (!BQ_AVAILABLE) return(NULL)                        # skip query when not authenticated
    df <- query_city_trend(input$bq_city, hours_back = 2) # last 2 hours for the selected city
    if (!is.null(df)) bq_last_refresh(Sys.time())         # record refresh time when data arrives
    df
  })

  # ── BQ latest snapshot reactive ───────────────────────────────────────────────
  # Returns one row per city: most recent window in the last 24 hours.
  bq_latest <- reactive({
    bq_timer()                                             # auto-refresh dependency
    bq_refresh_counter()                                   # manual refresh dependency
    if (!BQ_AVAILABLE) return(NULL)
    query_latest_snapshot()
  })

  # ── Connection status panel ────────────────────────────────────────────────────
  output$bq_status_panel <- renderUI({
    if (!BQ_AVAILABLE) {                                   # auth failed or bigrquery not installed
      return(tags$div(
        class = "panel panel-warning", style = "margin-bottom:0;",
        tags$div(class = "panel-heading",
          tags$h3(class = "panel-title",
            tags$i(class = "glyphicon glyphicon-warning-sign", style = "margin-right:6px;"),
            "GCP Not Configured"
          )
        ),
        tags$div(class = "panel-body",
          tags$p(style = "margin:0 0 8px; font-size:12px;",
            "To enable live BigQuery data:"
          ),
          tags$ol(style = "font-size:12px; padding-left:18px; margin:0;",
            tags$li(tags$code("renv::install('bigrquery')"), " then ",
                    tags$code("renv::snapshot()")),       # Step 1: install the package
            tags$li("Export a service account key for GCP project ",
                    tags$code("bike-demand-ml-system")),  # Step 2: create credentials
            tags$li("Set env var ",
                    tags$code("GOOGLE_APPLICATION_CREDENTIALS"),
                    " to the JSON file path")             # Step 3: configure the env var
          )
        )
      ))
    }
    latest      <- bq_latest()                            # current latest-snapshot data
    n_cities    <- if (is.null(latest)) 0L else nrow(latest)  # count cities with recent data
    last_ref    <- bq_last_refresh()                      # time of most recent successful query

    tags$div(
      class = "panel panel-success", style = "margin-bottom:0;",
      tags$div(class = "panel-heading",
        tags$h3(class = "panel-title",
          tags$i(class = "glyphicon glyphicon-ok-circle", style = "margin-right:6px;"),
          "BigQuery Connected"
        )
      ),
      tags$div(class = "panel-body",
        tags$p(style = "margin:0; font-size:12px;",
          tags$strong(n_cities), " cities with recent data  •  5-min windows"
        ),
        if (!is.null(last_ref))                           # show refresh time once a query has run
          tags$p(style = "font-size:11px; color:#888; margin:4px 0 0;",
            "Last refresh: ", format(last_ref, "%H:%M:%S UTC")
          )
      )
    )
  })

  # ── Latest snapshot stat cards ─────────────────────────────────────────────────
  output$bq_city_stats <- renderUI({
    latest <- bq_latest()

    if (is.null(latest)) {                                 # no data in last 24 hours
      if (!BQ_AVAILABLE) return(NULL)                      # hide — the status panel already explains why
      return(tags$div(class = "dash-card",
        tags$h5("Pipeline Status"),
        tags$p(style = "font-size:12px; color:#888; margin:0;",
          tags$i(class = "glyphicon glyphicon-time",
                 style = "margin-right:5px; color:#e99002;"),
          "No data in last 24 hours. Is the pipeline running?"
        )
      ))
    }

    rows <- lapply(seq_len(nrow(latest)), function(i) {   # one display row per city with data
      r       <- latest[i, ]
      age_min <- as.numeric(difftime(Sys.time(), r$latest_window, units = "mins"))  # minutes old
      age_txt <- if (age_min < 60)                         # format age as "Xm ago" or "X.Xh ago"
        paste0(round(age_min), "m ago")
      else
        paste0(round(age_min / 60, 1), "h ago")

      tags$div(
        style = paste0(
          "display:flex; justify-content:space-between; align-items:center;",
          "padding:6px 0; border-bottom:1px solid #f0f4f8; font-size:12px;"
        ),
        tags$span(style = "font-weight:600; color:#004e7c;", r$city_name),  # city name (left)
        tags$span(                                          # avg bikes + age (right)
          tags$strong(scales::comma(r$avg_bikes)), " avg  ",
          tags$span(style = "color:#888;", age_txt)
        )
      )
    })

    tags$div(class = "dash-card",
      tags$h5("Latest Snapshot — All Cities"),
      rows
    )
  })

  # ── BQ trend time-series chart builder ────────────────────────────────────────
  # One ggplot per call: avg line + min/max ribbon + per-window point labels.
  build_bq_trend_chart <- function(df, city_name) {
    ggplot(df, aes(x = window_start)) +
      geom_ribbon(                                         # shaded band = min/max bike range across stations
        aes(ymin = min_bikes, ymax = max_bikes),
        fill  = "#e8f4fb",
        alpha = 0.55
      ) +
      geom_line(                                           # solid line = avg bikes per station per window
        aes(y = avg_bikes),
        color     = "#008cba",
        linewidth = 1.1
      ) +
      geom_point(                                          # dot per window for visual inspection
        aes(y = avg_bikes),
        color = "#004e7c",
        size  = 2.5
      ) +
      geom_text(                                           # numeric labels above each point
        aes(y = avg_bikes, label = round(avg_bikes, 0)),
        vjust = -0.8,
        size  = 3,
        color = "#333"
      ) +
      labs(
        title    = paste("Live Station Feed —", city_name),
        subtitle = paste0(
          "5-minute windows  •  avg bikes / station (ribbon = min/max)  •  ",
          nrow(df), " windows"
        ),
        x = "Window Start (UTC)",
        y = "Bikes Available (avg per station)"
      ) +
      scale_x_datetime(date_labels = "%H:%M", date_breaks = "15 min") +
      theme_minimal() +
      theme(
        plot.title       = element_text(face = "bold", size = 12, color = "#004e7c"),
        plot.subtitle    = element_text(size = 9, color = "#666"),
        axis.title       = element_text(size = 9),
        axis.text.x      = element_text(angle = 30, hjust = 1, size = 8),
        panel.grid.minor = element_blank()
      )
  }

  # ── GCP Stream chart output ────────────────────────────────────────────────────
  output$bq_stream_chart <- renderPlot({
    df <- bq_trend()                                       # current BQ trend data for selected city

    if (!BQ_AVAILABLE) return(NULL)                        # empty plot when not configured

    if (is.null(df) || nrow(df) == 0) {                   # no data for city in last 2 hours
      ggplot() +
        annotate(                                          # centre-aligned message on blank canvas
          "text",
          x     = 0.5, y = 0.5,
          label = paste0(
            input$bq_city, " has no data in the last 2 hours.\n",
            "The GBFS poller may not currently be publishing this city."
          ),
          size  = 4.5, color = "#888",
          hjust = 0.5,  vjust = 0.5
        ) +
        xlim(0, 1) + ylim(0, 1) +
        theme_void() +
        labs(
          title    = paste("Live Station Feed —", input$bq_city),
          subtitle = "No data in last 2 hours"
        ) +
        theme(
          plot.title    = element_text(face = "bold", size = 12, color = "#004e7c"),
          plot.subtitle = element_text(size = 9, color = "#888")
        )
    } else {
      build_bq_trend_chart(df, input$bq_city)             # full trend chart when data is present
    }
  })

  # ── Last refresh text (shown below Refresh Now button) ────────────────────────
  output$bq_refresh_text <- renderUI({
    if (!BQ_AVAILABLE) return(NULL)
    tags$p(
      style = "font-size:10px; color:#999; margin:4px 0 0; font-style:italic;",
      "Auto-refreshes every 5 minutes."
    )
  })

})  # end shinyServer