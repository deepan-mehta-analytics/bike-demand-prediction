library(testthat)                                                           # testing framework
library(rprojroot)                                                          # project-root anchoring
proj_root <- find_root(is_git_root)                                         # canonical anchor per helper-workdir.R
setwd(file.path(proj_root, "shiny_app"))                                    # helpers expect shiny_app/ as cwd

source("server_helpers.R")                                                  # provides build_csv_filename + build_csv_header_block

test_that("build_csv_filename lowercases and dash-joins city + UTC stamp", {
  out <- build_csv_filename("New York", as.POSIXct("2026-05-27 14:30:00", tz = "UTC"))  # multi-word city, typical time
  expect_equal(out, "bike-demand-forecast-new-york-20260527-1430.csv")      # expected: slug + YYYYMMDD-HHMM
})

test_that("build_csv_filename handles multi-word city with mixed case", {
  out <- build_csv_filename("Washington DC", as.POSIXct("2026-05-27 09:05:00", tz = "UTC"))  # leading zero in minutes
  expect_equal(out, "bike-demand-forecast-washington-dc-20260527-0905.csv") # expected: two-word slug, zero-padded time
})

test_that("build_csv_filename handles single-word city", {
  out <- build_csv_filename("Seoul", as.POSIXct("2026-05-27 23:59:00", tz = "UTC"))  # single word, end-of-day time
  expect_equal(out, "bike-demand-forecast-seoul-20260527-2359.csv")         # expected: no dash-join needed
})

test_that("build_csv_header_block returns 4 commented lines with metadata", {
  out <- build_csv_header_block(                                             # all required fields
    city        = "Paris",
    source      = "openweather_live",
    fmt_start   = "27 May 2026 14:00",
    fmt_end     = "28 May 2026 11:00",
    exported_at = as.POSIXct("2026-05-27 14:30:00", tz = "UTC")
  )
  lines <- strsplit(out, "\n", fixed = TRUE)[[1]]                           # split on literal newline
  expect_equal(length(lines), 4L)                                           # exactly 4 header lines
  expect_match(lines[1], "^# Bike Demand 24h Forecast — exported 2026-05-27 14:30 UTC$")  # line 1: export stamp
  expect_match(lines[2], "^# City: Paris$")                                 # line 2: city name
  expect_match(lines[3], "^# Source: openweather_live$")                    # line 3: data source label
  expect_match(lines[4], "^# Forecast horizon: 27 May 2026 14:00 -> 28 May 2026 11:00$")  # line 4: horizon arrow
})

test_that("build_csv_header_block reports demo_fallback source verbatim", {
  out <- build_csv_header_block("Seoul", "demo_fallback", "now", "later",  # fallback source label
                                 as.POSIXct("2026-05-27 00:00:00", tz = "UTC"))
  expect_match(out, "# Source: demo_fallback")                              # exact source label preserved in output
})
