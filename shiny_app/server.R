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

source("model_prediction.R")

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
      
      selected_city        <- city_weather_bike_df %>% filter(CITY_ASCII == input$city_dropdown)
      selected_city_coords <- cities_max_bike      %>% filter(CITY_ASCII == input$city_dropdown)
      
      leaflet(data = selected_city) %>%
        addTiles() %>%
        setView(lng  = selected_city_coords$LNG[1],
                lat  = selected_city_coords$LAT[1],
                zoom = 10) %>%
        addMarkers(lng = ~LNG, lat = ~LAT,
                   popup          = ~DETAILED_LABEL,
                   clusterOptions = markerClusterOptions())
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
  
})  # end shinyServer