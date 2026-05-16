# =============================================================================
# bigquery_client.R
# Phase 7F — GCP Streaming Dashboard
# Authenticates with BigQuery and queries bike_demand.station_snapshots,
# the table written by the Dataflow GBFS streaming pipeline.
#
# BQ table: bike-demand-ml-system.bike_demand.station_snapshots
# Schema  : city | station_id | station_name | window_start | window_end |
#           avg_bikes_available | min_bikes_available | max_bikes_available |
#           total_snapshots
# City slugs: nyc, dc, london, chicago  (from gcp_config.yaml in the Python repo)
# =============================================================================

# ── City Lookup Tables ────────────────────────────────────────────────────────

BQ_CITY_SLUG_TO_NAME <- c(                    # Python pipeline slug → Shiny display name
  nyc     = "New York",                       # Citi Bike NYC
  dc      = "Washington DC",                  # Capital Bikeshare
  london  = "London",                         # TfL Santander Cycles
  chicago = "Chicago"                         # Divvy Bikes
)

BQ_CITY_NAME_TO_SLUG <- setNames(             # reverse: display name → BQ slug for WHERE clauses
  names(BQ_CITY_SLUG_TO_NAME),                # slugs become the values
  BQ_CITY_SLUG_TO_NAME                        # display names become the keys
)

BQ_PROJECT_ID <- "bike-demand-ml-system"      # GCP project ID (from Python repo config/gcp_config.yaml)

BQ_TABLE <- paste0(                           # fully qualified BQ table reference with backtick quoting
  "`", BQ_PROJECT_ID, ".bike_demand.station_snapshots`"
)


# ── Authentication ────────────────────────────────────────────────────────────
# Requires GOOGLE_APPLICATION_CREDENTIALS to point to a service account JSON file.
# Explicit service-account-only auth: avoids triggering interactive OAuth in Shiny.
# Returns TRUE on success, FALSE on any failure (never crashes the app).
bq_auth_safe <- function() {
  if (!requireNamespace("bigrquery", quietly = TRUE)) {  # package not installed yet
    message("[BigQuery] bigrquery not installed — run renv::install('bigrquery') then renv::snapshot().")
    return(FALSE)                                         # caller shows setup instructions in the tab
  }
  key_path <- Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS", unset = "")  # path to service account JSON
  if (nchar(key_path) == 0) {                            # env var not configured
    message("[BigQuery] GOOGLE_APPLICATION_CREDENTIALS not set — GCP Stream tab disabled.")
    return(FALSE)
  }
  if (!file.exists(key_path)) {                          # env var set but the file doesn't exist
    warning("[BigQuery] Credentials file not found: ", key_path)
    return(FALSE)
  }
  tryCatch({
    bigrquery::bq_auth(path = key_path)                  # authenticate with service account JSON
    message("[BigQuery] Authenticated via service account key.")
    TRUE
  }, error = function(e) {
    warning("[BigQuery] Auth failed: ", conditionMessage(e))
    FALSE
  })
}


# ── City Trend Query ──────────────────────────────────────────────────────────
# Queries the last `hours_back` hours of station_snapshots for one city.
# Groups by window_start → one row per 5-minute window with per-station avg/min/max.
# Returns a data frame or NULL on failure / empty result.
query_city_trend <- function(city_name, hours_back = 2) {
  city_slug <- BQ_CITY_NAME_TO_SLUG[city_name]           # resolve display name → pipeline slug
  if (is.na(city_slug)) {                                 # city not in the pipeline config
    warning("[BigQuery] Unknown city for BQ query: ", city_name)
    return(NULL)
  }
  sql <- paste0(                                          # build parameterised SQL
    "SELECT ",
    "  city, ",
    "  window_start, ",
    "  ROUND(AVG(avg_bikes_available), 1) AS avg_bikes, ",  # mean bikes per station in window
    "  MIN(min_bikes_available)           AS min_bikes, ",  # emptiest station seen in window
    "  MAX(max_bikes_available)           AS max_bikes, ",  # fullest station seen in window
    "  COUNT(*)                           AS n_stations ",  # stations reporting in this window
    "FROM ", BQ_TABLE, " ",
    "WHERE window_start >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ", hours_back, " HOUR) ",
    "  AND city = '", city_slug, "' ",                    # single-city filter
    "GROUP BY city, window_start ",                        # one aggregate row per 5-min window
    "ORDER BY window_start ASC"                            # ascending so chart reads left-to-right
  )
  tryCatch({
    result <- bigrquery::bq_project_query(BQ_PROJECT_ID, sql)  # execute query; returns BQ temp table ref
    df     <- bigrquery::bq_table_download(result, quiet = TRUE)  # download rows into an R data frame
    if (nrow(df) == 0) return(NULL)                        # empty window — pipeline not running
    df$window_start <- as.POSIXct(df$window_start, tz = "UTC")  # BQ TIMESTAMP → POSIXct UTC
    df$city_name    <- city_name                           # add display-name column for plot labels
    df                                                     # return cleaned trend data frame
  }, error = function(e) {
    warning("[BigQuery] Trend query failed: ", conditionMessage(e))
    NULL                                                   # graceful failure; caller shows empty-state panel
  })
}


# ── Latest Snapshot Per City ──────────────────────────────────────────────────
# Returns one row per city: the most recent 5-minute window's aggregate stats.
# Only cities with data in the last 24 hours appear in the result.
# Columns: city, city_name, latest_window, avg_bikes, min_bikes, max_bikes, n_stations
query_latest_snapshot <- function() {
  sql <- paste0(                                          # ROW_NUMBER() picks the newest window per city
    "SELECT city, window_start AS latest_window, avg_bikes, min_bikes, max_bikes, n_stations ",
    "FROM ( ",
    "  SELECT ",
    "    city, ",
    "    window_start, ",
    "    ROUND(AVG(avg_bikes_available), 1)  AS avg_bikes, ",
    "    MIN(min_bikes_available)            AS min_bikes, ",
    "    MAX(max_bikes_available)            AS max_bikes, ",
    "    COUNT(*)                            AS n_stations, ",
    "    ROW_NUMBER() OVER (PARTITION BY city ORDER BY window_start DESC) AS rn ",
    "  FROM ", BQ_TABLE, " ",
    "  WHERE window_start >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) ",
    "  GROUP BY city, window_start ",
    ") WHERE rn = 1 ",                                    # keep only the latest window per city
    "ORDER BY city"
  )
  tryCatch({
    result <- bigrquery::bq_project_query(BQ_PROJECT_ID, sql)
    df     <- bigrquery::bq_table_download(result, quiet = TRUE)
    if (nrow(df) == 0) return(NULL)
    df$latest_window <- as.POSIXct(df$latest_window, tz = "UTC")
    df$city_name     <- BQ_CITY_SLUG_TO_NAME[df$city]    # add display names for UI labels
    df
  }, error = function(e) {
    warning("[BigQuery] Latest snapshot query failed: ", conditionMessage(e))
    NULL
  })
}
