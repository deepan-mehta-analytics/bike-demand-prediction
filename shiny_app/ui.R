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
                                   choices  = c("All", "Seoul", "Suzhou", "London", "New York", "Paris"),
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
                        
                        # Stats
                        tags$div(class = "dash-card",
                                 tags$h5("Coverage"),
                                 tags$div(class = "stat-row",
                                          tags$div(class = "stat-box stat-cities",
                                                   tags$div(class = "stat-num", "5"),
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
                                 "Powered by OpenWeather API", tags$br(),
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
    )    # end tabPanel
  )      # end navbarPage
)        # end shinyUI