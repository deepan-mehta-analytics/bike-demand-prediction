# tests/testthat/test-bigquery-client.R
# Working directory: resolved to shiny_app/ via rprojroot before source() is called.
# Only tests pure lookup table constants — no GCP auth tested.
library(testthat)                                              # test framework
setwd(file.path(rprojroot::find_root(rprojroot::is_git_root), "shiny_app"))  # absolute path — works from any invocation dir
suppressMessages(source("bigquery_client.R"))                  # defines BQ_CITY_SLUG_TO_NAME + BQ_CITY_NAME_TO_SLUG


# ── BQ_CITY_SLUG_TO_NAME ──────────────────────────────────────────────────────

test_that("BQ_CITY_SLUG_TO_NAME: nyc maps to New York", {
  expect_equal(unname(BQ_CITY_SLUG_TO_NAME["nyc"]), "New York")   # unname() strips the key from comparison
})

test_that("BQ_CITY_SLUG_TO_NAME: dc maps to Washington DC", {
  expect_equal(unname(BQ_CITY_SLUG_TO_NAME["dc"]), "Washington DC")
})

test_that("BQ_CITY_SLUG_TO_NAME: london maps to London", {
  expect_equal(unname(BQ_CITY_SLUG_TO_NAME["london"]), "London")
})


# ── BQ_CITY_NAME_TO_SLUG ──────────────────────────────────────────────────────

test_that("BQ_CITY_NAME_TO_SLUG: New York maps to nyc (inverse mapping correct)", {
  expect_equal(unname(BQ_CITY_NAME_TO_SLUG["New York"]), "nyc")   # reverse of BQ_CITY_SLUG_TO_NAME
})
