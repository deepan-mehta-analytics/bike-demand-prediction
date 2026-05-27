library(testthat)                                                              # unit-testing framework
library(rprojroot)                                                             # project-root resolution
proj_root <- find_root(is_git_root)                                            # canonical anchor per helper-workdir.R
setwd(file.path(proj_root, "shiny_app"))                                       # set wd so source() finds server_helpers.R

source("server_helpers.R")                                                     # provides count_unique_cities() + FORECAST_HOURS_CONSTANT

test_that("count_unique_cities returns 6 for a 6-city frame", {
  df <- data.frame(CITY_ASCII = c("Seoul", "London", "New York", "Paris", "Chicago", "Washington DC"))   # 6 distinct cities
  expect_equal(count_unique_cities(df), 6L)                                    # must return integer 6
})

test_that("count_unique_cities deduplicates within a city (8-slot forecast)", {
  df <- data.frame(CITY_ASCII = rep(c("Seoul", "London"), each = 8L))         # 16 rows, 2 cities (8 slots each)
  expect_equal(count_unique_cities(df), 2L)                                    # unique() must collapse to 2
})

test_that("count_unique_cities returns 0 for empty input", {
  df <- data.frame(CITY_ASCII = character(0))                                  # zero-row data frame
  expect_equal(count_unique_cities(df), 0L)                                    # empty frame → 0 cities
})

test_that("FORECAST_HOURS_CONSTANT equals 24", {
  expect_equal(FORECAST_HOURS_CONSTANT, "24")                                  # documented constant, not data-derived
})
