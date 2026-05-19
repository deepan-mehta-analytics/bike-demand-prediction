# tests/testthat/test-gbfs-client.R
# Working directory: resolved to shiny_app/ via rprojroot before source() is called.
library(testthat)                                              # test framework
library(mockery)                                               # stub() for HTTP call patching
library(tibble)                                                # tibble() for fixture construction
library(dplyr)                                                 # bind_rows(), filter()
setwd(file.path(rprojroot::find_root(rprojroot::is_git_root), "shiny_app"))  # absolute path — works from any invocation dir
suppressMessages(source("gbfs_client.R"))                      # load module; defines all functions + constants


# ── Shared fixtures ───────────────────────────────────────────────────────────
# Minimal GBFS v2 + TfL JSON structures. Station "2" has NULL coordinates in
# both fixtures — used to verify NA-coord filtering in parsers.

fake_gbfs_info <- function() {                                 # mimics station_information.json structure
  list(data = list(stations = list(
    list(station_id = "1", name = "Test St",
         lat = 40.7, lon = -74.0, capacity = 20L),
    list(station_id = "2", name = "NA Coords",                 # NULL coords — should be dropped
         lat = NULL,  lon = NULL,  capacity = 10L)
  )))
}

fake_gbfs_status <- function() {                               # mimics station_status.json structure
  list(data = list(stations = list(
    list(station_id = "1", num_bikes_available = 5L,
         num_docks_available = 15L, is_renting = 1L, last_reported = 1700000000L),
    list(station_id = "2", num_bikes_available = 3L,
         num_docks_available = 7L,  is_renting = 1L, last_reported = 1700000001L)
  )))
}

fake_tfl <- function() {                                       # mimics TfL BikePoint response array
  list(
    list(                                                      # station with full data
      id = "BikePoints_1", commonName = "River St",
      lat = 51.53, lon = -0.11,
      additionalProperties = list(
        list(key = "NbBikes",      value = "4"),               # bikes available
        list(key = "NbEmptyDocks", value = "13"),              # empty docks
        list(key = "NbDocks",      value = "17")               # total docks
      )
    ),
    list(                                                      # station with NULL coords — should be dropped
      id = "BikePoints_2", commonName = "NA Coords",
      lat = NULL, lon = NULL,
      additionalProperties = list()
    )
  )
}

make_station_tibble <- function(n = 2L) {                      # helper: build n-row station tibble
  tibble(
    CITY_ASCII      = rep("New York", n),
    STATION_ID      = as.character(seq_len(n)),
    STATION_NAME    = paste("Station", seq_len(n)),
    LAT             = rep(40.7, n),
    LNG             = rep(-74.0, n),
    AVAILABLE_BIKES = rep(5L, n),
    AVAILABLE_DOCKS = rep(15L, n),
    CAPACITY        = rep(20L, n),
    IS_RENTING      = rep(TRUE, n),
    LAST_UPDATED    = rep(1700000000L, n)
  )
}


# ── %||% ─────────────────────────────────────────────────────────────────────

test_that("%||%: NULL returns fallback", {
  expect_equal(NULL %||% "fallback", "fallback")               # NULL left-hand side → use right
})

test_that("%||%: non-NULL value returned unchanged", {
  expect_equal("value" %||% "fallback", "value")               # non-NULL left-hand side → ignore right
})


# ── EMPTY_STATIONS_SCHEMA ─────────────────────────────────────────────────────

test_that("EMPTY_STATIONS_SCHEMA has the correct 10 column names", {
  expected <- c(
    "CITY_ASCII", "STATION_ID", "STATION_NAME",
    "LAT", "LNG",
    "AVAILABLE_BIKES", "AVAILABLE_DOCKS", "CAPACITY",
    "IS_RENTING", "LAST_UPDATED"
  )
  expect_equal(names(EMPTY_STATIONS_SCHEMA), expected)         # exact names; order matters for bind_rows()
})

test_that("EMPTY_STATIONS_SCHEMA has 0 rows and correct column types", {
  expect_equal(nrow(EMPTY_STATIONS_SCHEMA), 0L)                # zero rows — it is a schema, not data
  expect_type(EMPTY_STATIONS_SCHEMA$CITY_ASCII,      "character")
  expect_type(EMPTY_STATIONS_SCHEMA$STATION_ID,      "character")
  expect_type(EMPTY_STATIONS_SCHEMA$STATION_NAME,    "character")
  expect_type(EMPTY_STATIONS_SCHEMA$LAT,             "double")
  expect_type(EMPTY_STATIONS_SCHEMA$LNG,             "double")
  expect_type(EMPTY_STATIONS_SCHEMA$AVAILABLE_BIKES, "integer")
  expect_type(EMPTY_STATIONS_SCHEMA$AVAILABLE_DOCKS, "integer")
  expect_type(EMPTY_STATIONS_SCHEMA$CAPACITY,        "integer")
  expect_type(EMPTY_STATIONS_SCHEMA$IS_RENTING,      "logical")
  expect_type(EMPTY_STATIONS_SCHEMA$LAST_UPDATED,    "integer")
})


# ── parse_standard_gbfs() ─────────────────────────────────────────────────────

test_that("parse_standard_gbfs: output column names match EMPTY_STATIONS_SCHEMA", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(url, ...) {   # patch HTTP call
    if (grepl("information", url)) fake_gbfs_info() else fake_gbfs_status()
  })
  result <- parse_standard_gbfs("New York",
                                 "http://x/information.json",
                                 "http://x/status.json")
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))    # schema must match exactly
})

test_that("parse_standard_gbfs: CITY_ASCII propagated to every output row", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(url, ...) {
    if (grepl("information", url)) fake_gbfs_info() else fake_gbfs_status()
  })
  result <- parse_standard_gbfs("New York",
                                 "http://x/information.json",
                                 "http://x/status.json")
  expect_true(all(result$CITY_ASCII == "New York"))            # city name must appear on every row
})

test_that("parse_standard_gbfs: drops stations with NULL/NA coordinates", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(url, ...) {
    if (grepl("information", url)) fake_gbfs_info() else fake_gbfs_status()
  })
  result <- parse_standard_gbfs("New York",
                                 "http://x/information.json",
                                 "http://x/status.json")
  expect_equal(nrow(result), 1L)                               # station "2" (NULL coords) must be dropped
  expect_equal(result$STATION_ID, "1")                         # only station "1" survives
})

test_that("parse_standard_gbfs: returns EMPTY_STATIONS_SCHEMA when fetch returns NULL", {
  stub(parse_standard_gbfs, "fetch_gbfs_json", function(...) NULL)  # simulate network failure
  result <- suppressWarnings(
    parse_standard_gbfs("New York",
                         "http://x/information.json",
                         "http://x/status.json")
  )
  expect_equal(nrow(result), 0L)                               # degrade gracefully — no rows
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))    # schema intact even on failure
})


# ── parse_tfl_bikepoint() ─────────────────────────────────────────────────────

test_that("parse_tfl_bikepoint: output column names match EMPTY_STATIONS_SCHEMA", {
  stub(parse_tfl_bikepoint, "fetch_gbfs_json", function(...) fake_tfl())
  result <- parse_tfl_bikepoint("https://api.tfl.gov.uk/bikepoint")
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))    # schema must match exactly
})

test_that("parse_tfl_bikepoint: extracts NbBikes, NbEmptyDocks, NbDocks correctly", {
  stub(parse_tfl_bikepoint, "fetch_gbfs_json", function(...) fake_tfl())
  result <- parse_tfl_bikepoint("https://api.tfl.gov.uk/bikepoint")
  row1   <- result[result$STATION_ID == "BikePoints_1", ]      # isolate known station
  expect_equal(row1$AVAILABLE_BIKES, 4L)                       # NbBikes = "4" → 4L
  expect_equal(row1$AVAILABLE_DOCKS, 13L)                      # NbEmptyDocks = "13" → 13L
  expect_equal(row1$CAPACITY,        17L)                      # NbDocks = "17" → 17L
})

test_that("parse_tfl_bikepoint: returns EMPTY_STATIONS_SCHEMA when fetch returns NULL", {
  stub(parse_tfl_bikepoint, "fetch_gbfs_json", function(...) NULL)  # simulate network failure
  result <- suppressWarnings(
    parse_tfl_bikepoint("https://api.tfl.gov.uk/bikepoint")
  )
  expect_equal(nrow(result), 0L)                               # degrade gracefully
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))
})


# ── parse_gbfs_stations() ─────────────────────────────────────────────────────

test_that("parse_gbfs_stations: unknown city returns EMPTY_STATIONS_SCHEMA with warning", {
  expect_warning(
    result <- parse_gbfs_stations("Atlantis"),                 # not in CITY_GBFS_CONFIG
    regexp = "No GBFS config"                                  # warning message must mention config
  )
  expect_equal(nrow(result), 0L)
  expect_equal(names(result), names(EMPTY_STATIONS_SCHEMA))
})

test_that("parse_gbfs_stations: London routes to parse_tfl_bikepoint (not standard GBFS)", {
  mock_tfl <- mock(EMPTY_STATIONS_SCHEMA)                      # mock records calls and returns value
  stub(parse_gbfs_stations, "parse_tfl_bikepoint", mock_tfl)
  parse_gbfs_stations("London")
  expect_called(mock_tfl, 1L)                                  # must be called exactly once
})


# ── get_city_live_stations() ──────────────────────────────────────────────────

test_that("get_city_live_stations: success path returns enriched list with status=ok", {
  stub(get_city_live_stations, "parse_gbfs_stations",
       function(...) make_station_tibble(2L))                  # stub returns 2-row tibble
  result <- get_city_live_stations("New York")
  expect_true(all(c("data", "status", "row_count", "fetched_at", "message") %in% names(result)))
  expect_equal(result$status,    "ok")                         # non-empty result → ok
  expect_equal(result$row_count, 2L)                           # matches nrow of stub return
  expect_null(result$message)                                  # message is NULL on success
})

test_that("get_city_live_stations: failure path returns status=error with non-empty message", {
  stub(get_city_live_stations, "parse_gbfs_stations",
       function(...) EMPTY_STATIONS_SCHEMA)                    # stub returns 0-row tibble → failure
  result <- get_city_live_stations("New York")
  expect_equal(result$status,    "error")                      # 0 rows → error
  expect_equal(result$row_count, 0L)
  expect_true(nchar(result$message) > 0L)                      # must include a human-readable reason
})

test_that("get_city_live_stations: fetched_at is POSIXct", {
  stub(get_city_live_stations, "parse_gbfs_stations",
       function(...) EMPTY_STATIONS_SCHEMA)
  result <- get_city_live_stations("New York")
  expect_s3_class(result$fetched_at, "POSIXct")               # timestamp class required by server.R
})
