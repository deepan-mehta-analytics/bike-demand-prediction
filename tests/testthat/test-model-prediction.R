# tests/testthat/test-model-prediction.R
# Working directory: resolved to shiny_app/ via rprojroot before source() is called.
library(testthat)                                              # test framework
setwd(file.path(rprojroot::find_root(rprojroot::is_git_root), "shiny_app"))  # absolute path — works from any invocation dir
suppressMessages(source("model_prediction.R"))                 # load module under test; suppress package load msgs


# ── safe_val() ───────────────────────────────────────────────────────────────

test_that("safe_val: NULL returns NA_real_ by default", {
  expect_identical(safe_val(NULL), NA_real_)                  # default = NA_real_ when input is NULL
})

test_that("safe_val: NULL with custom default returns that default", {
  expect_identical(safe_val(NULL, default = 0.0), 0.0)        # custom default honoured for NULL
})

test_that("safe_val: non-NULL value passes through unchanged", {
  expect_identical(safe_val(15.5), 15.5)                      # non-NULL bypasses default entirely
})


# ── calculate_bike_prediction_level() ────────────────────────────────────────

test_that("calculate_bike_prediction_level: 0 is small", {
  expect_equal(calculate_bike_prediction_level(0), "small")     # single-value: q33==q67==0; 0<=q33 → small
})

test_that("calculate_bike_prediction_level: 1000 is small (single-value degenerate)", {
  expect_equal(calculate_bike_prediction_level(1000), "small")  # single-value: q33==q67==1000; 1000<=q33 → small
})

test_that("calculate_bike_prediction_level: value in lower tertile of spread is small", {
  result <- calculate_bike_prediction_level(c(0, 500, 1001, 2000, 5000))  # q33≈660, so 500 <= q33
  expect_equal(result[2], "small")                               # 500 is in the bottom tertile
})

test_that("calculate_bike_prediction_level: value in middle tertile of spread is medium", {
  result <- calculate_bike_prediction_level(c(0, 500, 1001, 2000, 5000))  # q33≈660, q67≈1680
  expect_equal(result[3], "medium")                              # 1001 falls between q33 and q67
})

test_that("calculate_bike_prediction_level: value in top tertile of spread is large", {
  result <- calculate_bike_prediction_level(c(0, 500, 1001, 2000, 5000))  # q67≈1680, so 5000 > q67
  expect_equal(result[5], "large")                               # 5000 is in the top tertile
})

test_that("calculate_bike_prediction_level: vectorised input returns exact tertile labels", {
  result <- calculate_bike_prediction_level(c(0, 500, 1001, 2000, 5000))  # q33≈680, q67≈1602 over this set
  expect_length(result, 5L)                                      # one output per input element
  expect_equal(result,                                            # exact per-position contract: catches mis-bucketing
               c("small", "small", "medium", "large", "large"))  # 0,500 ≤ q33; 1001 ≤ q67; 2000,5000 > q67
})


# ── load_saved_model() ────────────────────────────────────────────────────────

test_that("load_saved_model: returns a named numeric vector", {
  model <- load_saved_model("model.csv")                       # reads shiny_app/model.csv
  expect_true(is.numeric(model))                               # coefficients are numeric
  expect_false(is.null(names(model)))                          # names must be present for lookup
})

test_that("load_saved_model: names include all keys used by predict_bike_demand", {
  model <- load_saved_model("model.csv")                       # reads shiny_app/model.csv
  required_keys <- c(
    "Intercept",                                               # baseline term
    as.character(0:23),                                        # 24 hour-of-day keys
    "SPRING", "SUMMER", "AUTUMN", "WINTER"                    # 4 season keys
  )
  missing <- setdiff(required_keys, names(model))              # keys present in spec but absent from CSV
  expect_equal(
    length(missing), 0L,
    label = paste("Missing model keys:", paste(missing, collapse = ", "))
  )
})


# ── predict_bike_demand() ─────────────────────────────────────────────────────

test_that("predict_bike_demand: returns integer vector same length as input", {
  result <- predict_bike_demand(
    TEMPERATURE = c(15.0, 20.0),                               # two rows of input
    HUMIDITY    = c(60L,  55L),
    WIND_SPEED  = c(3.0,  4.0),
    VISIBILITY  = c(10000L, 9000L),
    SEASONS     = c("SPRING", "SUMMER"),
    HOURS       = c(8L, 12L)
  )
  expect_true(is.integer(result))                              # pmax(as.integer(...)) guarantees integer
  expect_length(result, 2L)                                    # one prediction per input row
})

test_that("predict_bike_demand: all values are non-negative", {
  result <- predict_bike_demand(
    TEMPERATURE = -10.0,                                       # cold conditions may produce low raw prediction
    HUMIDITY    = 90L,
    WIND_SPEED  = 10.0,
    VISIBILITY  = 500L,
    SEASONS     = "WINTER",
    HOURS       = 3L                                           # 3 AM - very low demand
  )
  expect_true(all(result >= 0L, na.rm = TRUE))                 # pmax floor must prevent negatives
})

test_that("predict_bike_demand: smoke test -- peak spring morning is a positive integer", {
  result <- predict_bike_demand(
    TEMPERATURE = 15.0,
    HUMIDITY    = 60L,
    WIND_SPEED  = 3.0,
    VISIBILITY  = 10000L,
    SEASONS     = "SPRING",
    HOURS       = 8L                                           # morning commute peak
  )
  expect_true(is.integer(result) && result > 0L && !is.na(result))  # must be a real positive prediction
})


# ── generate_demo_weather_data() ──────────────────────────────────────────────

test_that("generate_demo_weather_data: returns exactly 48 rows", {
  result <- suppressMessages(generate_demo_weather_data())     # 6 cities x 8 forecast slots
  expect_equal(nrow(result), 48L)
})

test_that("generate_demo_weather_data: schema and prediction values are valid", {
  result <- suppressMessages(generate_demo_weather_data())
  expected_cols <- c(                                          # columns server.R expects
    "CITY_ASCII", "LNG", "LAT",
    "TEMPERATURE", "HUMIDITY",
    "BIKE_PREDICTION", "BIKE_PREDICTION_LEVEL",
    "LABEL", "DETAILED_LABEL", "FORECASTDATETIME",
    "data_source"                                              # B3: source label column added
  )
  expect_equal(names(result), expected_cols)                   # schema must match server.R contract
  expect_true(all(result$BIKE_PREDICTION >= 0L))               # no negative predictions
  expect_true(all(result$BIKE_PREDICTION_LEVEL %in% c("small", "medium", "large")))  # valid levels only
})

test_that("generate_demo_weather_data: TEMPERATURE varies across slots within a city", {
  result      <- suppressMessages(generate_demo_weather_data())          # 6 cities x 8 forecast slots
  paris_temps <- result$TEMPERATURE[result$CITY_ASCII == "Paris"]        # 8 temperature values for Paris
  expect_gt(length(unique(paris_temps)), 1L)                             # must not all be identical
})

# ── B3: data_source column ─────────────────────────────────────────────────────

test_that("generate_demo_weather_data adds data_source = 'demo_fallback' to every row", {
  df <- suppressMessages(generate_demo_weather_data())                   # run demo generator
  expect_true("data_source" %in% colnames(df))                          # column must exist
  expect_true(all(df$data_source == "demo_fallback"))                    # every row must carry the fallback label
})

# ── C4: per-city quantile thresholds ─────────────────────────────────────────

test_that("calculate_bike_prediction_level returns 3 small / 2 medium / 3 large on linear 1..8", {
  out <- calculate_bike_prediction_level(1:8)                              # R default type=7 quantile
  expect_equal(sum(out == "small"),  3L)                                   # q33 = 3.31 → {1,2,3}
  expect_equal(sum(out == "medium"), 2L)                                   # (3.31, 5.69] → {4,5}
  expect_equal(sum(out == "large"),  3L)                                   # > 5.69 → {6,7,8}
})

test_that("calculate_bike_prediction_level is monotonically non-decreasing across sorted input", {
  out   <- calculate_bike_prediction_level(1:8)
  order <- c("small" = 1L, "medium" = 2L, "large" = 3L)                    # rank levels
  ranks <- order[out]
  expect_true(all(diff(ranks) >= 0L))                                       # no rank ever drops as inputs rise
})

test_that("calculate_bike_prediction_level returns all-small when all predictions equal (degenerate quantile)", {
  out <- calculate_bike_prediction_level(rep(500, 8))                      # all equal → q33 == q67 == 500
  expect_true(all(out == "small"))                                          # all values <= q33 by definition
})

test_that("calculate_bike_prediction_level handles NA gracefully", {
  out <- calculate_bike_prediction_level(c(1:7, NA))                       # one NA
  expect_equal(length(out), 8L)                                             # one output per input
  expect_true(is.na(out[8]))                                                # NA in → NA out
})
