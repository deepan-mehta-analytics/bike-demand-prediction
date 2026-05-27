# tests/testthat/test-data-source-footer.R
# Tests for build_data_source_footer() and build_data_source_subtitle_line() helpers (B3).
# Helpers take plain inputs and return plain character strings — no Shiny session needed.

library(testthat)                                                          # testthat framework
library(rprojroot)                                                         # repo-root resolution for source()
proj_root <- find_root(has_file("renv.lock"))                              # locate repo root from any wd
setwd(file.path(proj_root, "shiny_app"))                                   # match runtime working dir of Shiny app

source("server_helpers.R")                                                 # the helper module created in Task 1

# ── build_data_source_footer() ────────────────────────────────────────────────

test_that("build_data_source_footer returns OpenWeather-only message when all cities live", {
  df <- data.frame(
    CITY_ASCII  = c("Seoul", "London", "New York"),                        # 3 cities
    data_source = rep("openweather_live", 3L)                              # all live
  )
  out <- build_data_source_footer(df)                                      # call helper
  expect_match(out, "Powered by OpenWeather API")                          # base claim present
  expect_false(grepl("demo fallback", out, ignore.case = TRUE))            # no mixed-state suffix
  expect_false(grepl("not set", out, ignore.case = TRUE))                  # no all-demo suffix
})

test_that("build_data_source_footer reports mixed-state count when some cities on demo", {
  df <- data.frame(
    CITY_ASCII  = c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC"),
    data_source = c("openweather_live", "openweather_live", "demo_fallback",
                    "openweather_live", "openweather_live", "openweather_live")
  )
  out <- build_data_source_footer(df)
  expect_match(out, "Powered by OpenWeather API")                          # live claim retained
  expect_match(out, "1 of 6 cities on demo fallback")                      # explicit mixed-state count
})

test_that("build_data_source_footer reports all-demo message when no cities live", {
  df <- data.frame(
    CITY_ASCII  = c("Seoul", "London"),
    data_source = c("demo_fallback", "demo_fallback")
  )
  out <- build_data_source_footer(df)
  expect_match(out, "Demo data")                                           # all-demo claim
  expect_match(out, "OPENWEATHER_KEY not set")                             # actionable user hint
})

test_that("build_data_source_footer returns safe default for empty input df (startup race)", {
  df <- data.frame(CITY_ASCII = character(0), data_source = character(0))  # empty schema
  out <- build_data_source_footer(df)                                       # reactive fires pre-load
  expect_equal(out, "Powered by OpenWeather API")                           # safe default; no crash
})

test_that("build_data_source_footer warns and degrades when data_source column missing", {
  df <- data.frame(CITY_ASCII = c("Seoul", "London"))                       # contract violation: no data_source col
  expect_warning(out <- build_data_source_footer(df),                       # warning fires for debugging
                 "data_source.*column missing")
  expect_equal(out, "Powered by OpenWeather API")                           # safe UI default despite warning
})

# ── build_data_source_subtitle_line() ────────────────────────────────────────

test_that("build_data_source_subtitle_line returns timestamped OpenWeather line for live source", {
  out <- build_data_source_subtitle_line("openweather_live", as.POSIXct("2026-05-27 14:30:00", tz = "UTC"))
  expect_match(out, "Source: OpenWeather")                                 # source name
  expect_match(out, "14:30 UTC")                                           # passed-in time formatted
})

test_that("build_data_source_subtitle_line returns demo hint for fallback source", {
  out <- build_data_source_subtitle_line("demo_fallback", Sys.time())      # time arg ignored for demo
  expect_match(out, "Demo fallback")                                       # source label
  expect_match(out, "OPENWEATHER_KEY")                                     # env var name in actionable hint
})

test_that("build_data_source_subtitle_line degrades gracefully for NA src", {
  out <- build_data_source_subtitle_line(NA_character_, Sys.time())        # NA in: should not crash
  expect_match(out, "Demo fallback")                                       # graceful: same as demo path
})

test_that("build_data_source_subtitle_line degrades gracefully for NULL src", {
  out <- build_data_source_subtitle_line(NULL, Sys.time())                 # NULL in: should not crash
  expect_match(out, "Demo fallback")                                       # graceful: same as demo path
})
