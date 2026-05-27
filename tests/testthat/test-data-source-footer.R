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
