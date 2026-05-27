# =============================================================================
# ui.R
# -----------------------------------------------------------------------------
# Three-column dashboard:
#   LEFT   — city selector, demand filter buttons, legend, tips
#   CENTRE — Leaflet map
#   RIGHT  — when "All": city comparison bar chart + summary table
#             when a city is selected: temperature trend, bike demand trend,
#             humidity correlation (all with expand-to-modal buttons)
#
# App defaults to Paris on launch so charts are visible immediately.
# =============================================================================

if (!require(leaflet))     install.packages("leaflet")
if (!require(shinythemes)) install.packages("shinythemes")
if (!require(shinyjs))     install.packages("shinyjs")

shinyUI(
  navbarPage(
    
    title = tags$span(
      tags$i(class = "glyphicon glyphicon-road", style = "margin-right:8px;"),
      "Bikecast"
    ),
    
    theme       = shinythemes::shinytheme("yeti"),
    collapsible = TRUE,
    
    header = tagList(
      useShinyjs(),
      tags$head(tags$style(HTML("

        @import url('https://fonts.googleapis.com/css2?family=Barlow:wght@400;600;700&family=Barlow+Condensed:wght@700&display=swap');

        body { font-family: 'Barlow', sans-serif; background-color: #f0f4f8; }

        /* ── Navbar ── */
        .navbar-default {
          background: linear-gradient(135deg, #004e7c 0%, #008cba 100%) !important;
          border: none;
          box-shadow: 0 2px 8px rgba(0,0,0,0.25);
        }
        .navbar-default .navbar-brand,
        .navbar-default .navbar-nav > li > a {
          color: #ffffff !important;
          font-family: 'Barlow Condensed', sans-serif;
          font-size: 18px;
          letter-spacing: 0.5px;
        }
        .navbar-default .navbar-brand { font-size: 22px; font-weight: 700; }

        /* ── Three-column flex layout ── */
        .dashboard-wrapper {
          display: flex;
          gap: 14px;
          padding: 14px;
          min-height: calc(100vh - 60px);
          align-items: stretch;
        }

        /* ── Left sidebar ── */
        .dash-left {
          width: 250px;
          min-width: 250px;
          display: flex;
          flex-direction: column;
          gap: 12px;
          max-height: calc(100vh - 80px);
          overflow-y: auto;
        }

        /* ── Right sidebar ── */
        .dash-right {
          width: 280px;
          min-width: 280px;
          display: flex;
          flex-direction: column;
          gap: 12px;
          max-height: calc(100vh - 80px);
          overflow-y: auto;
        }

        /* ── Cards ── */
        .dash-card, .chart-card {
          background: #ffffff;
          border-radius: 10px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.08);
          padding: 16px 18px;
        }
        .dash-card h5, .chart-card h5 {
          font-family: 'Barlow Condensed', sans-serif;
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 1.2px;
          text-transform: uppercase;
          color: #008cba;
          margin: 0 0 10px 0;
          padding-bottom: 7px;
          border-bottom: 2px solid #e8f4fb;
        }

        /* ── Chart card header row: title left, expand button right ── */
        .chart-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 10px;
          padding-bottom: 7px;
          border-bottom: 2px solid #e8f4fb;
        }
        .chart-header span {
          font-family: 'Barlow Condensed', sans-serif;
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 1.2px;
          text-transform: uppercase;
          color: #008cba;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 200px;
        }
        /* Expand button — tiny icon button that sits in the card header */
        .btn-expand {
          background: none;
          border: 1px solid #d0e8f5;
          border-radius: 5px;
          padding: 2px 7px;
          font-size: 11px;
          color: #008cba;
          cursor: pointer;
          line-height: 1.4;
          transition: background 0.15s;
        }
        .btn-expand:hover { background: #e8f4fb; }

        /* ── Dropdown ── */
        .selectize-input {
          border-radius: 6px !important;
          border-color: #008cba !important;
          font-family: 'Barlow', sans-serif;
          font-size: 13px;
          box-shadow: none !important;
        }
        .selectize-dropdown { border-color: #008cba !important; border-radius: 6px !important; }
        .selectize-dropdown-content .option.selected,
        .selectize-dropdown-content .option:hover { background: #e8f4fb !important; color: #004e7c; }

        /* ── Demand filter buttons (real Yeti Bootstrap buttons) ── */
        .filter-btn-row { display: flex; gap: 6px; }
        .filter-btn-row .btn {
          flex: 1;
          font-size: 12px;
          font-weight: 600;
          border-radius: 20px;
          padding: 5px 4px;
          transition: opacity 0.2s ease;
        }
        /* Faded state when a level is toggled OFF via shinyjs::toggleClass() */
        .filter-btn-row .btn.btn-faded { opacity: 0.28; }
        .filter-hint { font-size: 11px; color: #999; margin-top: 8px; font-style: italic; }

        /* ── Stat boxes ── */
        .stat-row { display: flex; gap: 8px; }
        .stat-box { flex:1; border-radius:8px; padding:10px 8px; text-align:center; color:#fff; }
        .stat-box .stat-num { font-family:'Barlow Condensed',sans-serif; font-size:22px; font-weight:700; line-height:1; }
        .stat-box .stat-lbl { font-size:10px; letter-spacing:.8px; text-transform:uppercase; margin-top:3px; opacity:.9; }
        .stat-cities { background: linear-gradient(135deg, #008cba, #00b4d8); }
        .stat-days   { background: linear-gradient(135deg, #43ac6a, #52c87f); }

        /* ── Legend ── */
        .legend-row { display:flex; align-items:center; gap:9px; margin-bottom:8px; font-size:12.5px; color:#333; }
        .legend-dot { width:12px; height:12px; border-radius:50%; flex-shrink:0; box-shadow:0 1px 3px rgba(0,0,0,.2); }
        .dot-green  { background:#43ac6a; }
        .dot-yellow { background:#e99002; }
        .dot-red    { background:#f04124; }

        /* ── Tips ── */
        .tip-row  { display:flex; align-items:flex-start; gap:9px; margin-bottom:9px; font-size:12px; color:#555; line-height:1.4; }
        .tip-icon { width:22px; height:22px; border-radius:50%; background:#e8f4fb; color:#008cba; display:flex; align-items:center; justify-content:center; font-weight:700; font-size:11px; flex-shrink:0; }

        /* ── Map panel ── */
        .dash-map {
          flex: 1;
          background: #ffffff;
          border-radius: 10px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.08);
          overflow: hidden;
          display: flex;
          flex-direction: column;
        }
        .map-header {
          background: linear-gradient(135deg, #004e7c 0%, #008cba 100%);
          color: #fff;
          padding: 12px 18px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-shrink: 0;
        }
        .map-header .map-title { font-family:'Barlow Condensed',sans-serif; font-size:15px; font-weight:700; }
        .map-badge { background:rgba(255,255,255,.2); border-radius:20px; padding:3px 11px; font-size:10px; letter-spacing:.8px; text-transform:uppercase; }

        /* ── Click output text box ── */
        .click-output pre {
          background: #f8fafc;
          border: 1px solid #d0e8f5;
          border-radius: 6px;
          padding: 8px 10px;
          font-size: 11px;
          color: #333;
          margin: 0;
          white-space: pre;
        }

        /* ── Summary table in right pane (All view) ── */
        .summary-table { width: 100%; border-collapse: collapse; font-size: 12px; }
        .summary-table th {
          background: #e8f4fb;
          color: #004e7c;
          font-family: 'Barlow Condensed', sans-serif;
          letter-spacing: 0.8px;
          text-transform: uppercase;
          padding: 6px 8px;
          text-align: left;
          font-size: 11px;
        }
        .summary-table td { padding: 6px 8px; border-bottom: 1px solid #f0f4f8; color: #333; }
        .summary-table tr:last-child td { border-bottom: none; }
        .badge-small  { background:#43ac6a; color:#fff; border-radius:10px; padding:2px 8px; font-size:10px; }
        .badge-medium { background:#e99002; color:#fff; border-radius:10px; padding:2px 8px; font-size:10px; }
        .badge-large  { background:#f04124; color:#fff; border-radius:10px; padding:2px 8px; font-size:10px; }

        /* ── Modal chart: fill the dialog nicely ── */
        .modal-chart-body { padding: 10px 20px 20px; }
        .modal-dialog.modal-lg { width: 85vw; max-width: 1100px; }

        /* ── Footer ── */
        .dash-footer { text-align:center; padding:8px; font-size:11px; color:#aaa; margin-top:auto; }

        /* ── Operator tab: Yeti Bootstrap panels in left sidebar ── */
        /* Round corners to match dash-card; typography consistent with Barlow */
        .dash-left .panel { border-radius: 8px !important; overflow: hidden; }
        .dash-left .panel-heading { padding: 10px 14px; }
        .dash-left .panel-body { padding: 10px 14px; font-size: 12.5px; line-height: 1.5; }
        .dash-left .panel-title { font-family: 'Barlow Condensed', sans-serif; font-size: 13px; font-weight: 700; letter-spacing: 0.3px; }

        /* ── Rider tab: demand score cards (3-up Bootstrap grid inside dash-card) ── */
        /* well-sm provides the card background; demand-* classes handle inner layout */
        .demand-card { text-align: center; min-height: 82px; }
        .demand-card .demand-time { font-size: 11px; color: #888; margin: 0 0 6px; }
        .demand-card .demand-badge { font-size: 13px !important; padding: 5px 9px !important; display: inline-block; border-radius: 3px; }
        .demand-card .demand-bikes { font-size: 11px; color: #666; margin: 7px 0 0; }

        /* ── GCP Stream tab: chart panel container ── */
        /* Mirrors dash-map but holds a plotOutput instead of a leafletOutput */
        .dash-chart-panel {
          flex: 1;
          background: #ffffff;
          border-radius: 10px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.08);
          display: flex;
          flex-direction: column;
          overflow: hidden;
        }
        .chart-panel-header {
          background: linear-gradient(135deg, #004e7c 0%, #008cba 100%);
          color: #fff;
          padding: 12px 18px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-shrink: 0;
        }
        .chart-panel-body {
          flex: 1;
          padding: 16px;
        }

      ")))
    ),
    
    tabPanel(
      title = tags$span(
        tags$i(class="glyphicon glyphicon-map-marker", style="margin-right:5px;"),
        "Live Map"
      ),
      
      tags$div(class = "dashboard-wrapper",
               
               # ════════════════════════════════════════════════════════════════════
               # LEFT SIDEBAR
               # ════════════════════════════════════════════════════════════════════
               tags$div(class = "dash-left",
                        
                        # City selector — defaults to Paris so charts show on launch
                        tags$div(class = "dash-card",
                                 tags$h5("Select City"),
                                 selectInput(
                                   inputId  = "city_dropdown",
                                   label    = NULL,
                                   choices  = c("All", "Seoul", "London", "New York", "Paris", "Chicago", "Washington DC"),
                                   selected = "Paris"   # ← Default to Paris so charts appear immediately
                                 ),
                                 tags$p(style = "font-size:11px; color:#888; margin:4px 0 0;",
                                        tags$i(class="glyphicon glyphicon-info-sign", style="margin-right:3px; color:#008cba;"),
                                        "Select 'All' for a global overview or a city for detail charts."
                                 )
                        ),
                        
                        # Demand filter — real Yeti Bootstrap buttons
                        tags$div(class = "dash-card",
                                 tags$h5("Filter by Demand"),
                                 tags$div(class = "filter-btn-row",
                                          actionButton("filter_low",    "Low",    class = "btn btn-success"),
                                          actionButton("filter_medium", "Medium", class = "btn btn-warning"),
                                          actionButton("filter_high",   "High",   class = "btn btn-danger")
                                 ),
                                 tags$p(class = "filter-hint", "Click to show / hide cities by demand level.")
                        ),

                        # Feed Health panel — rendered server-side via output$feed_health_panel
                        # Colour-coded rows: green (LIVE) / amber (DELAYED) / red (UNAVAILABLE)
                        # Note: overflow:hidden is on an INNER div, not the flex-item dash-card.
                        # A flex item with overflow:hidden collapses to height:0 in column-flex
                        # containers — moving it inward lets the flex item size to its content.
                        tags$div(class = "dash-card", style = "padding:0;",
                                 tags$div(style = "overflow:hidden; border-radius:10px;",
                                          uiOutput("feed_health_panel"))
                        ),

                        # Stats
                        tags$div(class = "dash-card",
                                 tags$h5("Coverage"),
                                 tags$div(class = "stat-row",
                                          tags$div(class = "stat-box stat-cities",
                                                   tags$div(class = "stat-num", "6"),
                                                   tags$div(class = "stat-lbl", "Cities")
                                          ),
                                          tags$div(class = "stat-box stat-days",
                                                   tags$div(class = "stat-num", "24"),
                                                   tags$div(class = "stat-lbl", "Hr Forecast")
                                          )
                                 )
                        ),
                        
                        # Legend
                        tags$div(class = "dash-card",
                                 tags$h5("Demand Level"),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-green"),
                                          tags$div(tags$strong("Low"), " — peak < 1,000 bikes / 3h slot")
                                 ),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-yellow"),
                                          tags$div(tags$strong("Medium"), " — peak 1,000 – 3,000 bikes")
                                 ),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-red"),
                                          tags$div(tags$strong("High"), " — peak > 3,000 bikes / 3h slot")
                                 )
                        ),
                        
                        # Tips
                        tags$div(class = "dash-card",
                                 tags$h5("How to Use"),
                                 tags$div(class = "tip-row",
                                          tags$div(class = "tip-icon", "1"),
                                          tags$span("Toggle the coloured demand buttons to filter cities on the map.")
                                 ),
                                 tags$div(class = "tip-row",
                                          tags$div(class = "tip-icon", "2"),
                                          tags$span("Choose 'All' for a global overview comparing all cities over 24 hours.")
                                 ),
                                 tags$div(class = "tip-row",
                                          tags$div(class = "tip-icon", "3"),
                                          tags$span("Select a city to drill down into its 24-hour forecast charts.")
                                 ),
                                 tags$div(class = "tip-row",
                                          tags$div(class = "tip-icon", "4"),
                                          tags$span(
                                            tags$i(class="glyphicon glyphicon-fullscreen", style="margin-right:3px; color:#008cba;"),
                                            "Click the expand icon on any chart to view it full-screen."
                                          )
                                 )
                        ),
                        
                        tags$div(class = "dash-footer",
                                 uiOutput("data_source_footer", inline = TRUE), tags$br(),  # B3: reactive source claim
                                 "IBM Data Analytics Capstone"
                        )
                        
               ),  # end dash-left
               
               
               # ════════════════════════════════════════════════════════════════════
               # CENTRE — Leaflet map
               # ════════════════════════════════════════════════════════════════════
               tags$div(class = "dash-map",
                        tags$div(class = "map-header",
                                 # uiOutput() fills this from output$map_date_title in server.R
                                 # which builds the title dynamically with actual forecast dates
                                 uiOutput("map_date_title"),
                                 tags$div(class = "map-badge", "Live • 24h")
                        ),
                        leafletOutput("city_bike_map", height = "calc(100vh - 130px)")
               ),
               
               
               # ════════════════════════════════════════════════════════════════════
               # RIGHT SIDEBAR — two modes depending on dropdown selection
               # ════════════════════════════════════════════════════════════════════
               tags$div(class = "dash-right",
                        
                        # ── MODE A: "All" selected — city comparison placeholders ──────────
                        # conditionalPanel shows this block ONLY when "All" is selected
                        conditionalPanel(
                          condition = "input.city_dropdown == 'All'",
                          
                          # City comparison bar chart
                          tags$div(class = "chart-card",
                                   tags$div(class = "chart-header",
                                            tags$span("Peak Demand by City — Next 24h"),
                                            actionButton("expand_compare", "", class = "btn-expand",
                                                         icon("fullscreen", lib = "glyphicon"),
                                                         title = "Expand chart"
                                            )
                                   ),
                                   # Filled by output$city_compare_chart in server.R
                                   plotOutput("city_compare_chart", height = "220px")
                          ),
                          
                          # Summary stats table
                          tags$div(class = "chart-card",
                                   tags$div(class = "chart-header",
                                            tags$span("City Summary")
                                   ),
                                   # Filled by output$city_summary_table — rendered as HTML table
                                   uiOutput("city_summary_table")
                          )
                        ),
                        
                        # ── MODE B: Specific city — three detail charts with expand buttons ─
                        conditionalPanel(
                          condition = "input.city_dropdown != 'All'",
                          
                          # Task 1: Temperature trend
                          # Temperature chart — click any point to inspect temp value at that time
                          tags$div(class = "chart-card",
                                   tags$div(class = "chart-header",
                                            tags$span("Temperature — Next 24 Hours"),
                                            actionButton("expand_temp", "", class = "btn-expand",
                                                         icon("fullscreen", lib = "glyphicon"),
                                                         title = "Expand chart"
                                            )
                                   ),
                                   # click = "temp_click" captures the click coordinates into input$temp_click
                                   plotOutput("temp_line", height = "190px", click = "temp_click"),
                                   tags$div(style = "margin-top:7px;",
                                            tags$p(style = "font-size:10px; color:#999; margin-bottom:3px;",
                                                   tags$i(class="glyphicon glyphicon-hand-up", style="margin-right:3px;"),
                                                   "Click a point to inspect:"
                                            ),
                                            tags$div(class = "click-output",
                                                     verbatimTextOutput("temp_click_output")
                                            )
                                   )
                          ),
                          
                          # Bike demand chart — click any point to inspect predicted bike count
                          tags$div(class = "chart-card",
                                   tags$div(class = "chart-header",
                                            tags$span("Bike Demand — Next 24 Hours"),
                                            actionButton("expand_bike", "", class = "btn-expand",
                                                         icon("fullscreen", lib = "glyphicon"),
                                                         title = "Expand chart"
                                            )
                                   ),
                                   # click = "bike_click" captures click coordinates into input$bike_click
                                   plotOutput("bike_line", height = "190px", click = "bike_click"),
                                   tags$div(style = "margin-top:7px;",
                                            tags$p(style = "font-size:10px; color:#999; margin-bottom:3px;",
                                                   tags$i(class="glyphicon glyphicon-hand-up", style="margin-right:3px;"),
                                                   "Click a point to inspect:"
                                            ),
                                            tags$div(class = "click-output",
                                                     verbatimTextOutput("bike_click_output")
                                            )
                                   )
                          ),
                          
                          # Humidity chart — click any point to inspect humidity & predicted bikes
                          tags$div(class = "chart-card",
                                   tags$div(class = "chart-header",
                                            tags$span("Humidity vs Demand — 24h"),
                                            actionButton("expand_humidity", "", class = "btn-expand",
                                                         icon("fullscreen", lib = "glyphicon"),
                                                         title = "Expand chart"
                                            )
                                   ),
                                   # click = "humidity_click" captures click coordinates into input$humidity_click
                                   plotOutput("humidity_pred_chart", height = "190px", click = "humidity_click"),
                                   tags$div(style = "margin-top:7px;",
                                            tags$p(style = "font-size:10px; color:#999; margin-bottom:3px;",
                                                   tags$i(class="glyphicon glyphicon-hand-up", style="margin-right:3px;"),
                                                   "Click a point to inspect:"
                                            ),
                                            tags$div(class = "click-output",
                                                     verbatimTextOutput("humidity_click_output")
                                            )
                                   )
                          )
                        )
                        
               )  # end dash-right
               
      )  # end dashboard-wrapper
    ),   # end Live Map tabPanel


    # ══════════════════════════════════════════════════════════════════════════
    # OPERATOR TAB (Phase 7D — UC1)
    # Fleet rebalancing view for city operators:
    #   — Demand-vs-supply alert panels (Yeti panel-danger / warning / success)
    #   — Fill-rate progress bar across all stations
    #   — Leaflet map: stations coloured/sized by rebalancing urgency
    #   — 24-hr forecast CSV export
    # ══════════════════════════════════════════════════════════════════════════
    tabPanel(
      title = tags$span(
        tags$i(class = "glyphicon glyphicon-dashboard", style = "margin-right:5px;"),
        "Operator"
      ),

      tags$div(class = "dashboard-wrapper",

               # ════════════════════════════════════════════════════════════════
               # LEFT SIDEBAR — controls, alerts, fleet stats, export
               # ════════════════════════════════════════════════════════════════
               tags$div(class = "dash-left", style = "width:310px; min-width:310px;",

                        # City selector for Operator view (no "All" option — always city-specific)
                        tags$div(class = "dash-card",
                                 tags$h5("Select City"),
                                 selectInput(
                                   inputId  = "operator_city",
                                   label    = NULL,
                                   choices  = c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC"),
                                   selected = "London"        # ← London has live GBFS and good station density
                                 )
                        ),

                        # Demand-vs-supply alert — Yeti panel-danger / panel-warning / panel-success
                        # Rendered server-side so it reflects live GBFS + forecast data
                        uiOutput("operator_alerts"),

                        # Fleet fill-rate summary with Yeti progress bar
                        uiOutput("operator_station_stats"),

                        # 24-hour demand forecast CSV download
                        tags$div(class = "dash-card",
                                 tags$h5("Export Forecast"),
                                 downloadButton(
                                   "download_forecast",
                                   label = tags$span(
                                     tags$i(class = "glyphicon glyphicon-download-alt", style = "margin-right:6px;"),
                                     "Download 24h CSV"
                                   ),
                                   class = "btn btn-primary btn-block"   # Yeti primary button — full width
                                 ),
                                 tags$p(
                                   style = "font-size:11px; color:#888; margin-top:8px; margin-bottom:0;",
                                   "24-hour demand forecast for the selected city."
                                 )
                        ),

                        # Rebalancing colour legend
                        tags$div(class = "dash-card",
                                 tags$h5("Rebalancing Key"),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-red"),
                                          tags$div(tags$strong("Restock"), " — fill rate < 20%")
                                 ),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-yellow"),
                                          tags$div(tags$strong("Monitor"), " — fill rate 20–60%")
                                 ),
                                 tags$div(class = "legend-row",
                                          tags$div(class = "legend-dot dot-green"),
                                          tags$div(tags$strong("Source"), " — fill rate > 60%")
                                 ),
                                 tags$p(
                                   style = "font-size:11px; color:#888; margin:8px 0 0; font-style:italic;",
                                   "Circle size reflects station capacity."
                                 )
                        )

               ),  # end dash-left (Operator)


               # ════════════════════════════════════════════════════════════════
               # CENTRE — Operator fleet rebalancing map
               # ════════════════════════════════════════════════════════════════
               tags$div(class = "dash-map",
                        tags$div(class = "map-header",
                                 uiOutput("operator_map_title"),           # dynamic title with city name
                                 tags$div(class = "map-badge", "Rebalancing View")
                        ),
                        leafletOutput("operator_map", height = "calc(100vh - 130px)")
               )

      )  # end dashboard-wrapper (Operator)
    ),   # end Operator tabPanel


    # ══════════════════════════════════════════════════════════════════════════
    # RIDER TAB (Phase 7E — UC2)
    # End-user view for cyclists:
    #   — Demand score badges (Yeti label-success/warning/danger) for next 3 slots
    #   — Best-time-to-ride recommendation (lowest demand hour today)
    #   — Natural-language availability summary
    #   — Top-5 stations by live bike count (Yeti table-striped + label badges)
    #   — Live station availability map
    # ══════════════════════════════════════════════════════════════════════════
    tabPanel(
      title = tags$span(
        tags$i(class = "glyphicon glyphicon-road", style = "margin-right:5px;"),
        "Rider"
      ),

      tags$div(class = "dashboard-wrapper",

               # ════════════════════════════════════════════════════════════════
               # LEFT SIDEBAR — city, demand cards, best time, summary, stations
               # ════════════════════════════════════════════════════════════════
               tags$div(class = "dash-left", style = "width:340px; min-width:340px;",

                        # City selector
                        tags$div(class = "dash-card",
                                 tags$h5("Select City"),
                                 selectInput(
                                   inputId  = "rider_city",
                                   label    = NULL,
                                   choices  = c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC"),
                                   selected = "London"
                                 )
                        ),

                        # Demand score cards — Yeti label-success/warning/danger for next 3 forecast slots
                        # Each card: time slot label + coloured demand badge + predicted bike count
                        tags$div(class = "dash-card",
                                 tags$h5("Demand Score — Next 9 Hours"),
                                 uiOutput("rider_demand_scores")
                        ),

                        # Best time recommendation — lowest-demand slot in the 24h window
                        uiOutput("rider_best_time"),

                        # Natural-language summary — demand level + live bikes + best-time hint
                        uiOutput("rider_summary"),

                        # Top-5 stations by current bike availability (Yeti table + label badges)
                        uiOutput("rider_station_table")

               ),  # end dash-left (Rider)


               # ════════════════════════════════════════════════════════════════
               # CENTRE — Live station availability map
               # Same colour scheme as Live Map: green ≥5, amber 1–4, red 0 bikes
               # ════════════════════════════════════════════════════════════════
               tags$div(class = "dash-map",
                        tags$div(class = "map-header",
                                 uiOutput("rider_map_title"),
                                 tags$div(class = "map-badge", "Live Availability")
                        ),
                        leafletOutput("rider_map", height = "calc(100vh - 130px)")
               )

      )  # end dashboard-wrapper (Rider)
    ),   # end Rider tabPanel


    # ══════════════════════════════════════════════════════════════════════════
    # GCP STREAM TAB (Phase 7F)
    # Live station availability from BigQuery (written by Cloud Run GBFS poller):
    #   — Queries bike-demand-ml-system.bike_demand.station_snapshots
    #   — Time-series chart: avg bikes / station per 5-min window (last 2 hrs)
    #   — Shaded ribbon: min-to-max range across stations in each window
    #   — Auto-refreshes every 5 minutes; manual Refresh Now button
    #   — Shows setup instructions when GOOGLE_APPLICATION_CREDENTIALS not set
    # ══════════════════════════════════════════════════════════════════════════
    tabPanel(
      title = tags$span(
        tags$i(class = "glyphicon glyphicon-signal", style = "margin-right:5px;"),
        "GCP Stream"
      ),

      tags$div(class = "dashboard-wrapper",

               # ════════════════════════════════════════════════════════════════
               # LEFT SIDEBAR — city selector, status, refresh, stats
               # ════════════════════════════════════════════════════════════════
               tags$div(class = "dash-left", style = "width:310px; min-width:310px;",

                        # City selector — only cities the Cloud Run GBFS poller publishes
                        tags$div(class = "dash-card",
                                 tags$h5("Select City"),
                                 selectInput(
                                   inputId  = "bq_city",
                                   label    = NULL,
                                   choices  = c("New York", "Washington DC", "London", "Chicago"),
                                   selected = "New York"   # NYC has live data from 2026-05-15
                                 ),
                                 tags$p(
                                   style = "font-size:11px; color:#888; margin:4px 0 0;",
                                   tags$i(class="glyphicon glyphicon-info-sign",
                                          style="margin-right:3px; color:#008cba;"),
                                   "Only cities polled by the Cloud Run GBFS poller are available here.",
                                   " Seoul and Paris are not in the GCP pipeline."
                                 )
                        ),

                        # Connection status — green (connected) or amber (setup needed)
                        # Rendered server-side so it reflects BQ_AVAILABLE at runtime
                        uiOutput("bq_status_panel"),

                        # Refresh Now button + auto-refresh hint
                        tags$div(class = "dash-card",
                                 tags$h5("Refresh Data"),
                                 actionButton(
                                   inputId = "bq_refresh",
                                   label   = tags$span(
                                     tags$i(class = "glyphicon glyphicon-refresh",
                                            style = "margin-right:6px;"),
                                     "Refresh Now"
                                   ),
                                   class = "btn btn-primary btn-block"
                                 ),
                                 uiOutput("bq_refresh_text")  # "Auto-refreshes every 5 minutes."
                        ),

                        # Per-city latest snapshot stats (one row per city with recent data)
                        uiOutput("bq_city_stats"),

                        # How-this-works explanation card
                        tags$div(class = "dash-card",
                                 tags$h5("About This Tab"),
                                 tags$div(class = "tip-row",
                                          tags$div(class = "tip-icon", "1"),
                                          tags$span(
                                            "Data flows: GBFS → Pub/Sub → Dataflow → BigQuery",
                                            " every 5 minutes."
                                          )
                                 ),
                                 tags$div(class = "tip-row",
                                          tags$div(class = "tip-icon", "2"),
                                          tags$span(
                                            "Each chart point = average bikes available per station",
                                            " within a 5-minute aggregation window."
                                          )
                                 ),
                                 tags$div(class = "tip-row",
                                          tags$div(class = "tip-icon", "3"),
                                          tags$span(
                                            "The blue ribbon shows the min-to-max bike range across",
                                            " all stations in each window."
                                          )
                                 )
                        )

               ),  # end dash-left (GCP Stream)


               # ════════════════════════════════════════════════════════════════
               # CENTRE — time-series chart from BigQuery
               # Avg bikes per station per 5-min window, last 2 hours
               # ════════════════════════════════════════════════════════════════
               tags$div(class = "dash-chart-panel",
                        tags$div(class = "chart-panel-header",
                                 tags$div(class = "map-title",
                                          tags$i(class = "glyphicon glyphicon-signal",
                                                 style = "margin-right:7px;"),
                                          "GCP Streaming Dashboard — Last 2 Hours"
                                 ),
                                 tags$div(class = "map-badge", "BigQuery • Live")
                        ),
                        tags$div(class = "chart-panel-body",
                                 plotOutput("bq_stream_chart",
                                            height = "calc(100vh - 200px)")
                        )
               )

      )  # end dashboard-wrapper (GCP Stream)
    )    # end GCP Stream tabPanel

  )      # end navbarPage
)        # end shinyUI