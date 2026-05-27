# ============================================================================
# server_helpers.R — Pure helper functions consumed by server.R
# Extracted so testthat can unit-test them without spinning up a Shiny session.
# Each function takes plain inputs and returns plain strings.
# ============================================================================

# ── B3: Footer message based on live/demo split across cities ─────────────────
# Input:  df with CITY_ASCII and data_source columns
# Output: character string suitable for renderUI (HTML-safe plain text)
build_data_source_footer <- function(df) {
  if (nrow(df) == 0L) return("Powered by OpenWeather API")                   # transient: reactive fired pre-load
  if (!"data_source" %in% colnames(df)) {                                    # contract violation, not transient
    warning("build_data_source_footer: 'data_source' column missing from input df")   # surface in R console
    return("Powered by OpenWeather API")                                    # degrade to safe string for UI
  }
  # precondition: data_source is uniform within each city (set at generator level)
  per_city <- unique(df[, c("CITY_ASCII", "data_source")])                  # one row per city
  total    <- nrow(per_city)                                                # total cities in current frame
  demo_n   <- sum(per_city$data_source == "demo_fallback")                  # cities currently on fallback
  if (demo_n == 0L) return("Powered by OpenWeather API")                    # all live → simple claim
  if (demo_n == total) {                                                    # all demo → actionable hint
    return("Demo data — OPENWEATHER_KEY not set; live forecasts disabled")
  }
  sprintf("Powered by OpenWeather API — %d of %d cities on demo fallback",
          demo_n, total)                                                    # mixed-state count
}

# ── B3: Per-chart subtitle line indicating data source for the displayed city ─
# Input:  src       — "openweather_live" or "demo_fallback" (NULL / NA degrade to demo string)
#         build_time — POSIXct timestamp (chart build moment, UTC-format applied)
# Output: character string for ggplot subtitle (single line)
build_data_source_subtitle_line <- function(src, build_time) {
  if (identical(src, "openweather_live")) {                                 # exact-match: NULL/NA fall through
    return(sprintf("Source: OpenWeather, refreshed %s UTC",
                   format(build_time, "%H:%M", tz = "UTC")))                # formatted HH:MM UTC
  }
  "Source: Demo fallback — set OPENWEATHER_KEY in .Renviron and restart"   # actionable user hint
}

# ── C5: Operator alert level based on snapshot state (no forecast comparison) ─
# Inputs (all integers/numerics):
#   n_stations       — total stations in the city
#   n_empty_stations — stations with zero bikes available
#   total_bikes      — sum of bikes available across all stations
#   total_capacity   — sum of dock capacity across all stations
#   red_pct, amber_pct — zero-bike fraction thresholds
#   fill_pct         — fleet fill-rate threshold below which amber fires
# Output: one of "red", "amber", "green"
compute_operator_alert_level <- function(n_stations, n_empty_stations,
                                          total_bikes, total_capacity,
                                          red_pct, amber_pct, fill_pct) {
  if (n_stations == 0L || total_capacity == 0L) return("red")               # degenerate: no fleet → critical
  zero_frac <- n_empty_stations / n_stations                                # fraction of stations with 0 bikes
  fill_frac <- total_bikes / total_capacity                                 # fleet-wide fill rate
  if (zero_frac >= red_pct)                          return("red")          # critical: many empty stations
  if (zero_frac >= amber_pct || fill_frac < fill_pct) return("amber")       # warning: either condition
  "green"                                                                   # healthy
}

# ── C1: Engine indicator line for bike-demand chart subtitle ─────────────────
# Reads USE_FASTAPI at call time (chart-render time). The env var is set at
# container/process start so the value is stable across renders. No RMSE in UI.
# Tests must use withr::with_envvar() to override the value per-test.
build_engine_subtitle_line <- function() {
  if (identical(Sys.getenv("USE_FASTAPI", unset = "false"), "true")) {     # exact-match "true" only; anything else → local
    return("Engine: FastAPI Random Forest")                                 # FastAPI path: model served via Cloud Run
  }
  "Engine: Local linear regression"                                         # default: model.csv IBM linear regression
}

# ── C3: Stat-card helpers — derived city count + documented forecast horizon ──
count_unique_cities <- function(df) {                                        # used by renderText for stat_cities
  if (nrow(df) == 0L) return(0L)                                             # empty df → 0 cities
  length(unique(df$CITY_ASCII))                                              # unique city count
}

# Forecast horizon is genuinely fixed: OpenWeather 5-day/3-hour API yields
# 8 slots × 3 hours = 24 hours. Documented as a string for direct render.
FORECAST_HOURS_CONSTANT <- "24"
