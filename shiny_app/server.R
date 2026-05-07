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

test_weather_data_generation <- function() {
  city_weather_bike_df <- generate_city_weather_bike_data()
  stopifnot(length(city_weather_bike_df) > 0)
  print(head(city_weather_bike_df))
  return(city_weather_bike_df)
}


shinyServer(function(input, output, session) {
  
  # ---------------------------------------------------------------------------
  # Fetch data once on startup
  # Each city now has 8 rows (8 x 3-hour slots = next 24 hours)
  # ---------------------------------------------------------------------------
  city_weather_bike_df <- test_weather_data_generation()

  # Fetch live station availability from GBFS / TfL for all cities at startup.
  # Wrapped in tryCatch so a network failure never prevents the app from loading.
  # live_stations_df has columns: CITY_ASCII, STATION_ID, STATION_NAME, LAT, LNG,
  #   AVAILABLE_BIKES, AVAILABLE_DOCKS, CAPACITY, IS_RENTING, LAST_UPDATED
  live_stations_df <- tryCatch(
    get_all_cities_live_stations(unique(city_weather_bike_df$CITY_ASCII)),  # one call covers all cities
    error = function(e) {                                                    # GBFS outage must not crash app
      warning(paste("GBFS startup fetch failed:", conditionMessage(e)))
      EMPTY_STATIONS_SCHEMA                                                  # fall back to empty schema
    }
  )

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
      city_stations <- live_stations_df %>%
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
  
  
  # ── Sidebar renders ───────────────────────────────────────────────────────
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
      title = tags$span(
        tags$i(class = "glyphicon glyphicon-signal",
               style = "margin-right:8px; color:#008cba;"),
        paste("Temperature — Next 24h —", input$city_dropdown)
      ),
      tags$div(class = "modal-chart-body",
               plotOutput("temp_line_modal", height = "430px")),
      footer = modalButton("Close"), size = "l", easyClose = TRUE
    ))
  })
  output$temp_line_modal <- renderPlot({
    req(input$city_dropdown != "All")
    build_temp_chart(selected_city_data())
  })
  
  observeEvent(input$expand_bike, {
    showModal(modalDialog(
      title = tags$span(
        tags$i(class = "glyphicon glyphicon-stats",
               style = "margin-right:8px; color:#43ac6a;"),
        paste("Bike Demand — Next 24h —", input$city_dropdown)
      ),
      tags$div(class = "modal-chart-body",
               plotOutput("bike_line_modal", height = "430px")),
      footer = modalButton("Close"), size = "l", easyClose = TRUE
    ))
  })
  output$bike_line_modal <- renderPlot({
    req(input$city_dropdown != "All")
    build_bike_chart(selected_city_data())
  })
  
  observeEvent(input$expand_humidity, {
    showModal(modalDialog(
      title = tags$span(
        tags$i(class = "glyphicon glyphicon-tint",
               style = "margin-right:8px; color:#004e7c;"),
        paste("Humidity vs Demand — 24h —", input$city_dropdown)
      ),
      tags$div(class = "modal-chart-body",
               plotOutput("humidity_pred_chart_modal", height = "430px")),
      footer = modalButton("Close"), size = "l", easyClose = TRUE
    ))
  })
  output$humidity_pred_chart_modal <- renderPlot({
    req(input$city_dropdown != "All")
    build_humidity_chart(selected_city_data())
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
    live_stations_df %>%                                                    # all cities' station availability (Phase 7B)
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

})  # end shinyServer