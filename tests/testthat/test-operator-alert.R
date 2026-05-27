library(testthat)                                                           # testthat testing framework
library(rprojroot)                                                          # project root detection
proj_root <- find_root(has_file("renv.lock"))                               # walk up until renv.lock is found
setwd(file.path(proj_root, "shiny_app"))                                    # change to shiny_app/ so source() paths resolve

source("server_helpers.R")                                                  # helper module from Task 1

# Thresholds the helper is parameterised on (mirrored from server.R constants):
RED_PCT   <- 0.25                                                           # red:   ≥25% stations have zero bikes
AMBER_PCT <- 0.10                                                           # amber: ≥10% stations have zero bikes
FILL_PCT  <- 0.20                                                           # amber: fleet fill rate <20%

test_that("returns 'red' when zero-bike fraction meets the 25% threshold", {
  out <- compute_operator_alert_level(
    n_stations         = 100L,
    n_empty_stations   = 25L,                                               # exactly 25%
    total_bikes        = 500L,
    total_capacity     = 1000L,                                             # 50% fill — not amber by itself
    red_pct = RED_PCT, amber_pct = AMBER_PCT, fill_pct = FILL_PCT
  )
  expect_equal(out, "red")
})

test_that("returns 'red' when zero-bike fraction exceeds 25%", {
  out <- compute_operator_alert_level(100L, 26L, 500L, 1000L,              # 26% empty → red
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "red")
})

test_that("returns 'amber' when zero-bike fraction meets 10% but not 25%", {
  out <- compute_operator_alert_level(100L, 10L, 500L, 1000L,              # 10% empty, 50% fill → amber
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "amber")
})

test_that("returns 'amber' when fill rate drops below 20% even with few empty stations", {
  out <- compute_operator_alert_level(100L, 5L, 150L, 1000L,               # 15% fill, 5% empty → amber
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "amber")
})

test_that("returns 'amber' at fill rate exactly 19% (just below threshold)", {
  out <- compute_operator_alert_level(100L, 0L, 190L, 1000L,               # 19% fill, 0% empty → amber
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "amber")
})

test_that("returns 'green' when fill rate at threshold (20%) and zero-bike under 10%", {
  out <- compute_operator_alert_level(100L, 5L, 200L, 1000L,               # 20% fill, 5% empty → green
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "green")
})

test_that("returns 'green' on healthy fleet", {
  out <- compute_operator_alert_level(100L, 3L, 600L, 1000L,               # 60% fill, 3% empty → green
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "green")
})

test_that("handles zero capacity edge case without divide-by-zero", {
  out <- compute_operator_alert_level(0L, 0L, 0L, 0L,                      # no fleet → critical by convention
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "red")                                                  # no fleet → critical by convention
})

test_that("returns 'red' when stations exist but total_capacity is zero (data-quality variant)", {
  out <- compute_operator_alert_level(10L, 0L, 50L, 0L,                     # stations report but capacity missing
                                       RED_PCT, AMBER_PCT, FILL_PCT)
  expect_equal(out, "red")                                                  # server.R red branch routes to data-quality body
})
