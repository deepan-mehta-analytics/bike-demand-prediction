# =============================================================================
# gbfs_client.R
# -----------------------------------------------------------------------------
# Live bike-station data client for the Shiny dashboard.
#
# Fetches real-time station availability from each city's live feed and returns
# a single standardised data frame consumed by the Operator (UC1) and Rider
# (UC2) tabs, and by the city drill-down map view.
#
# Three feed types are handled:
#   "gbfs"  — standard GBFS v2 (NYC, Paris, Chicago)
#             Two requests: station_information.json + station_status.json
#             Joined on station_id to produce one row per station
#   "tfl"   — London TfL BikePoint API (proprietary format, single endpoint)
#             Properties NbBikes / NbEmptyDocks / NbDocks extracted from
#             the additionalProperties array in each feature object
#   "skip"  — Seoul (Seoul Open API requires free key registration at
#             data.seoul.go.kr; returns empty tibble gracefully until key added)
#
# All functions wrap HTTP calls in tryCatch — a GBFS failure must never
# crash the Shiny app. On error, an empty tibble with the correct schema
# is returned so the rest of the app degrades gracefully.
# =============================================================================


# ── Libraries ─────────────────────────────────────────────────────────────────
if (!require(httr))    install.packages("httr")    # HTTP GET requests to GBFS endpoints
if (!require(dplyr))   install.packages("dplyr")   # inner_join, bind_rows, filter, mutate
if (!require(tibble))  install.packages("tibble")  # tibble() for schema-safe empty frames
if (!require(purrr))   install.packages("purrr")   # map_chr / map_int for list extraction


# ── Null-coalescing operator ──────────────────────────────────────────────────
# %||% returns y if x is NULL, otherwise x.
# Defined here explicitly rather than importing from rlang to avoid namespace
# ambiguity — rlang is a transitive dependency but not directly loaded.
`%||%` <- function(x, y) if (is.null(x)) y else x   # safe null fallback for API field extraction


# ── City GBFS configuration ───────────────────────────────────────────────────
# Hardcoded here (not read from cities.yaml) to avoid adding a yaml package
# dependency to renv. cities.yaml remains the human-readable reference doc.
# Each entry: type + URL(s) for that city's feed.

CITY_GBFS_CONFIG <- list(                                           # named list keyed by CITY_ASCII

  "Seoul" = list(                                                   # Seoul Open API requires API key
    type = "skip"                                                   # skip until SEOUL_OPEN_API_KEY is set
  ),

  "London" = list(                                                  # TfL BikePoint — not GBFS spec
    type       = "tfl",                                             # custom parser required
    status_url = "https://api.tfl.gov.uk/bikepoint"                # single endpoint returns all stations
  ),

  "New York" = list(                                                # Citi Bike GBFS v2
    type       = "gbfs",                                            # standard GBFS parser
    info_url   = "https://gbfs.citibikenyc.com/gbfs/en/station_information.json",   # static: name/lat/lon/capacity
    status_url = "https://gbfs.citibikenyc.com/gbfs/en/station_status.json"         # live: available bikes/docks
  ),

  "Paris" = list(                                                   # Vélib' Métropole GBFS v2
    type       = "gbfs",                                            # standard GBFS parser
    info_url   = "https://velib-metropole-opendata.smovengo.fr/opendata/Velib_Metropole/station_information.json",
    status_url = "https://velib-metropole-opendata.smovengo.fr/opendata/Velib_Metropole/station_status.json"
  ),

  "Chicago" = list(                                                 # Divvy (Lyft) GBFS v2
    type       = "gbfs",                                            # standard GBFS parser
    info_url   = "https://gbfs.divvybikes.com/gbfs/en/station_information.json",
    status_url = "https://gbfs.divvybikes.com/gbfs/en/station_status.json"
  ),

  "Washington DC" = list(                                           # Capital Bikeshare GBFS v2 — fully public, no auth
    type       = "gbfs",                                            # standard GBFS parser (same as NYC, Paris, Chicago)
    info_url   = "https://gbfs.capitalbikeshare.com/gbfs/en/station_information.json",  # static: name/lat/lon/capacity
    status_url = "https://gbfs.capitalbikeshare.com/gbfs/en/station_status.json"        # live: available bikes/docks
  )
)


# ── Empty schema tibble ───────────────────────────────────────────────────────
# Returned whenever a city is skipped or a fetch fails.
# All callers must receive the same column names and types to allow bind_rows().

EMPTY_STATIONS_SCHEMA <- tibble(                                    # zero-row tibble with correct types
  CITY_ASCII      = character(0),                                   # city name matching CITY_ASCII convention
  STATION_ID      = character(0),                                   # unique station identifier
  STATION_NAME    = character(0),                                   # human-readable station name for popups
  LAT             = double(0),                                      # station latitude
  LNG             = double(0),                                      # station longitude
  AVAILABLE_BIKES = integer(0),                                     # current rentable bikes
  AVAILABLE_DOCKS = integer(0),                                     # current free docks
  CAPACITY        = integer(0),                                     # total dock slots
  IS_RENTING      = logical(0),                                     # TRUE = station accepting rentals
  LAST_UPDATED    = integer(0)                                      # Unix timestamp of last status report
)


# =============================================================================
# SECTION 1 — Low-level HTTP helper
# =============================================================================

# fetch_gbfs_json()
# ------------------
# Makes a GET request to a GBFS or TfL endpoint and returns the parsed JSON.
# On any error (network timeout, HTTP 4xx/5xx, malformed JSON) returns NULL
# so the calling function can decide how to handle the failure.
#
# Arguments:
#   url — full URL string to fetch
#
# Returns: parsed R list (from httr::content) or NULL on failure

fetch_gbfs_json <- function(url) {
  tryCatch({
    resp <- GET(url, timeout(10))                                   # 10-second timeout; GBFS feeds are fast
    if (http_error(resp)) {                                         # non-2xx status code from server
      warning(paste("GBFS fetch failed:", url, "— HTTP", status_code(resp)))
      return(NULL)                                                  # return NULL; caller handles gracefully
    }
    content(resp, as = "parsed", encoding = "UTF-8")               # parse JSON into R list
  }, error = function(e) {                                          # catches network errors (no connection etc.)
    warning(paste("GBFS network error:", url, "—", conditionMessage(e)))
    NULL                                                            # return NULL on any network failure
  })
}


# =============================================================================
# SECTION 2 — Standard GBFS v2 parser (NYC, Paris, Chicago)
# =============================================================================

# parse_standard_gbfs()
# ---------------------
# Fetches station_information.json and station_status.json for a GBFS v2 city.
# Joins them on station_id to produce one row per station with live counts.
#
# Arguments:
#   city_name  — CITY_ASCII string e.g. "New York"
#   info_url   — URL for station_information.json
#   status_url — URL for station_status.json
#
# Returns: tibble matching EMPTY_STATIONS_SCHEMA, or EMPTY_STATIONS_SCHEMA on failure

parse_standard_gbfs <- function(city_name, info_url, status_url) {

  # ── Fetch both feeds ───────────────────────────────────────────────────────
  info_json   <- fetch_gbfs_json(info_url)                         # static station data (name, coords, capacity)
  status_json <- fetch_gbfs_json(status_url)                       # live availability data

  if (is.null(info_json) || is.null(status_json)) {                # either fetch failed
    warning(paste("Skipping", city_name, "— GBFS fetch returned NULL"))
    return(EMPTY_STATIONS_SCHEMA)                                   # degrade gracefully
  }

  # ── Extract station lists from the GBFS v2 envelope ───────────────────────
  # GBFS v2 structure: { "data": { "stations": [ {...}, {...} ] }, "ttl": ..., "last_updated": ... }
  info_list   <- info_json$data$stations                           # list of station_information objects
  status_list <- status_json$data$stations                         # list of station_status objects

  if (is.null(info_list) || length(info_list) == 0 ||
      is.null(status_list) || length(status_list) == 0) {          # empty or missing stations array
    warning(paste("Empty station list for", city_name))
    return(EMPTY_STATIONS_SCHEMA)
  }

  # ── Build data frames from the list of station objects ────────────────────
  # map_chr / map_int iterate over the list and extract one field per element.
  # Use as.character / as.integer to coerce consistently (API may return mixed types).

  # ── Station information (static) ──
  info_df <- tibble(
    station_id = map_chr(info_list, ~ as.character(.x$station_id %||% NA_character_)),  # unique ID
    name       = map_chr(info_list, ~ as.character(.x$name       %||% "Unknown")),      # display name
    lat        = map_dbl(info_list, ~ as.double(.x$lat           %||% NA_real_)),       # latitude
    lon        = map_dbl(info_list, ~ as.double(.x$lon           %||% NA_real_)),       # longitude
    capacity   = map_int(info_list, ~ as.integer(.x$capacity     %||% 0L))             # total dock count
  )

  # ── Station status (live) ──
  status_df <- tibble(
    station_id      = map_chr(status_list, ~ as.character(.x$station_id         %||% NA_character_)),
    num_bikes       = map_int(status_list, ~ as.integer(.x$num_bikes_available  %||% 0L)),  # available bikes
    num_docks       = map_int(status_list, ~ as.integer(.x$num_docks_available  %||% 0L)),  # free docks
    is_renting      = map_lgl(status_list, ~ isTRUE(.x$is_renting == 1 || .x$is_renting == TRUE)),
    last_reported   = map_int(status_list, ~ as.integer(.x$last_reported        %||% 0L))  # unix timestamp
  )

  # ── Join on station_id and rename to standard schema ──────────────────────
  joined <- info_df %>%
    inner_join(status_df, by = "station_id") %>%                   # inner join: only stations with both info + status
    filter(!is.na(lat), !is.na(lon)) %>%                           # drop stations missing coordinates
    transmute(                                                      # rename + select to standard schema
      CITY_ASCII      = city_name,                                  # propagate city name to every row
      STATION_ID      = station_id,
      STATION_NAME    = name,
      LAT             = lat,
      LNG             = lon,
      AVAILABLE_BIKES = num_bikes,
      AVAILABLE_DOCKS = num_docks,
      CAPACITY        = capacity,
      IS_RENTING      = is_renting,
      LAST_UPDATED    = last_reported
    )

  joined
}


# =============================================================================
# SECTION 3 — TfL BikePoint parser (London)
# =============================================================================

# parse_tfl_bikepoint()
# ----------------------
# Fetches the TfL BikePoint endpoint and converts its proprietary format
# into the standard station schema.
#
# TfL response structure (array of features):
#   [{ "id": "BikePoints_1",
#      "commonName": "River Street , Clerkenwell",
#      "lat": 51.529163, "lon": -0.10997,
#      "additionalProperties": [
#        { "key": "NbBikes",      "value": "4"  },
#        { "key": "NbEmptyDocks", "value": "13" },
#        { "key": "NbDocks",      "value": "17" }
#      ]}, ...]
#
# Arguments:
#   status_url — TfL BikePoint URL (e.g. https://api.tfl.gov.uk/bikepoint)
#
# Returns: tibble matching EMPTY_STATIONS_SCHEMA, or EMPTY_STATIONS_SCHEMA on failure

parse_tfl_bikepoint <- function(status_url) {

  json_list <- fetch_gbfs_json(status_url)                         # fetch TfL BikePoint array

  if (is.null(json_list) || length(json_list) == 0) {              # fetch failed or empty response
    warning("TfL BikePoint fetch returned NULL or empty list")
    return(EMPTY_STATIONS_SCHEMA)
  }

  # ── Helper: extract a named property from additionalProperties ────────────
  # TfL stores availability in a flat key-value list rather than named fields.
  # get_tfl_prop() finds the element with matching key and returns its value as integer.
  get_tfl_prop <- function(props, key) {
    hit <- Filter(function(p) identical(p$key, key), props)         # find matching key
    if (length(hit) == 0) return(0L)                               # return 0 if key missing
    as.integer(hit[[1]]$value)                                     # parse string value to int
  }

  # ── Build one row per BikePoint feature ───────────────────────────────────
  rows <- lapply(json_list, function(bp) {                         # iterate each BikePoint object
    props <- bp$additionalProperties %||% list()                   # extract additionalProperties list

    tibble(
      CITY_ASCII      = "London",                                   # hardcoded — only London uses TfL
      STATION_ID      = as.character(bp$id        %||% NA_character_),
      STATION_NAME    = as.character(bp$commonName %||% "Unknown"),
      LAT             = as.double(bp$lat           %||% NA_real_),
      LNG             = as.double(bp$lon           %||% NA_real_),
      AVAILABLE_BIKES = get_tfl_prop(props, "NbBikes"),            # bikes available now
      AVAILABLE_DOCKS = get_tfl_prop(props, "NbEmptyDocks"),       # empty docks
      CAPACITY        = get_tfl_prop(props, "NbDocks"),            # total docks
      IS_RENTING      = TRUE,                                       # TfL does not expose is_renting; assume TRUE
      LAST_UPDATED    = as.integer(Sys.time())                     # use current time (TfL has no last_reported)
    )
  })

  result <- bind_rows(rows) %>%                                     # combine all rows into one tibble
    filter(!is.na(LAT), !is.na(LNG))                               # drop any stations missing coordinates

  result
}


# =============================================================================
# SECTION 4 — Per-city dispatcher
# =============================================================================

# parse_gbfs_stations()
# ----------------------
# Routes a city to the correct parser based on its type in CITY_GBFS_CONFIG.
# Always returns a tibble matching EMPTY_STATIONS_SCHEMA — never throws.
#
# Arguments:
#   city_name — CITY_ASCII string (must be a key in CITY_GBFS_CONFIG)
#
# Returns: tibble matching EMPTY_STATIONS_SCHEMA

parse_gbfs_stations <- function(city_name) {

  cfg <- CITY_GBFS_CONFIG[[city_name]]                             # look up city config

  if (is.null(cfg)) {                                              # city not in config
    warning(paste("No GBFS config for city:", city_name))
    return(EMPTY_STATIONS_SCHEMA)
  }

  if (cfg$type == "skip") {                                        # Seoul or any future key-gated city
    message(paste("Skipping GBFS for", city_name, "(no API key configured)"))
    return(EMPTY_STATIONS_SCHEMA)
  }

  if (cfg$type == "tfl") {                                         # London TfL BikePoint
    return(parse_tfl_bikepoint(cfg$status_url))
  }

  if (cfg$type == "gbfs") {                                        # standard GBFS v2
    return(parse_standard_gbfs(city_name, cfg$info_url, cfg$status_url))
  }

  warning(paste("Unknown GBFS type:", cfg$type, "for city:", city_name))
  EMPTY_STATIONS_SCHEMA                                            # fallback for unrecognised type
}


# =============================================================================
# SECTION 5 — Main entry point
# =============================================================================

# get_all_cities_live_stations()
# --------------------------------
# Fetches live station data for every city in the supplied vector and returns
# a single combined data frame. Called once at Shiny startup; result stored
# as live_stations_df in server.R.
#
# Arguments:
#   city_names — character vector of CITY_ASCII names e.g. c("Seoul", "London", ...)
#
# Returns: tibble with all cities' stations combined (or EMPTY_STATIONS_SCHEMA if all fail)

get_all_cities_live_stations <- function(city_names) {

  results <- lapply(city_names, function(cn) {                     # fetch each city independently
    tryCatch(
      parse_gbfs_stations(cn),                                     # parse using correct method for city type
      error = function(e) {                                        # catch any unexpected runtime errors
        warning(paste("Unexpected error for city:", cn, "—", conditionMessage(e)))
        EMPTY_STATIONS_SCHEMA                                      # return empty; do not propagate error
      }
    )
  })

  combined <- bind_rows(results)                                   # stack all city results into one data frame

  if (nrow(combined) == 0) {                                       # all cities failed or were skipped
    message("get_all_cities_live_stations: no station data returned for any city")
    return(EMPTY_STATIONS_SCHEMA)
  }

  combined                                                         # return combined data frame to server.R
}
