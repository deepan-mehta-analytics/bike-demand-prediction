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
