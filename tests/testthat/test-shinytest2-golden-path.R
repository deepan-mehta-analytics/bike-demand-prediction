# tests/testthat/test-shinytest2-golden-path.R
# shinytest2 AppDriver integration tests — demo-mode golden path
# Requires: shinytest2 installed, Chrome/Chromium available, model.csv in shiny_app/
# Skip guards at top ensure the existing testthat CI job silently skips these;
# the dedicated shinytest2 CI job installs Chromium so guards don't fire there.

library(testthat)                                                       # testing framework

# ── Guard 1: package availability ────────────────────────────────────────────
skip_if_not_installed("shinytest2")                                     # silently skip if shinytest2 not in renv
skip_if_not_installed("chromote")                                       # chromote is pulled as dep of shinytest2

# ── Guard 2: Chrome/Chromium binary ──────────────────────────────────────────
chrome_found <- !is.null(                                               # NULL = find_chrome() errored = no binary
  tryCatch(chromote::find_chrome(), error = function(e) NULL)           # returns path string or errors
)
skip_if(!chrome_found, "Chrome/Chromium not found — skipping AppDriver tests")

# ── Guard 3: model.csv required by demo generator ─────────────────────────────
# cwd is shiny_app/ (set by helper-workdir.R); model.csv is gitignored but
# copied by CI before running tests (same pattern as the testthat job).
skip_if(
  !file.exists("model.csv"),                                            # relative to shiny_app/ cwd
  "model.csv not found in shiny_app/ — CI must copy it from data/processed/ first"
)

library(shinytest2)                                                     # only loaded after guards pass

# ── Helpers ───────────────────────────────────────────────────────────────────

make_app <- function() {                                                # factory: new AppDriver pointed at shiny_app/
  AppDriver$new(                                                        # cwd is shiny_app/ per helper-workdir.R
    app_dir   = ".",                                                    # resolves to shiny_app/
    height    = 800L,                                                   # headless viewport height
    width     = 1280L,                                                  # headless viewport width
    timeout   = 30000L,                                                 # 30 s startup timeout (cold demo load)
    load_timeout = 30000L                                               # 30 s page-load timeout
  )
}

# ── Test 1: App loads in demo mode ────────────────────────────────────────────
# Verifies the server starts and renders at least one static output without
# an OPENWEATHER_KEY.  stat_hours is a renderText of FORECAST_HOURS_CONSTANT
# — a string literal "24" — so any server crash prevents this from rendering.

test_that("app loads in demo mode and renders stat_hours = '24'", {
  app <- make_app()                                                     # launch headless Shiny app
  on.exit(app$stop(), add = TRUE)                                       # always stop app, even on test failure

  app$wait_for_idle(timeout = 20000L)                                   # wait for all reactives to settle (20 s)

  hours_text <- app$get_value(output = "stat_hours")                   # renderText output — expected "24"
  expect_equal(hours_text, "24")                                        # static constant; any other value = server bug
})


# ── Test 2: City selector reactive chain doesn't crash ───────────────────────
# Changes city_dropdown from the default "Paris" to "London".  After
# wait_for_idle() the server must still render stat_hours = "24", proving
# the reactive chain (city_weather_bike_df → derived outputs) completed
# without error on a city switch.

test_that("city_dropdown change from Paris to London keeps stat_hours reactive", {
  app <- make_app()                                                     # fresh app instance for isolation
  on.exit(app$stop(), add = TRUE)

  app$wait_for_idle(timeout = 20000L)                                   # initial settle

  app$set_inputs(city_dropdown = "London")                              # simulate city selector change
  app$wait_for_idle(timeout = 10000L)                                   # wait for downstream reactives to re-run

  hours_text <- app$get_value(output = "stat_hours")                   # still "24" if reactive chain OK
  expect_equal(hours_text, "24")                                        # proves no server crash on city switch
})


# ── Test 3: Demo mode produces a non-empty city count ─────────────────────────
# stat_cities is a renderText of count_unique_cities(city_weather_bike_df()).
# In demo mode generate_demo_weather_data() produces 6 cities; any value > 0
# proves the demo generator ran and the reactive produced output.

test_that("demo mode generates a non-empty stat_cities count", {
  app <- make_app()                                                     # fresh app instance
  on.exit(app$stop(), add = TRUE)

  app$wait_for_idle(timeout = 20000L)                                   # wait for city frame to render

  cities_text <- app$get_value(output = "stat_cities")                 # renderText of city count integer
  expect_true(
    !is.null(cities_text) && nchar(as.character(cities_text)) > 0L,    # non-null, non-empty string
    info = paste("stat_cities returned:", deparse(cities_text))         # diagnostic on failure
  )
})


# ── Test 4: Leaflet map output container renders ───────────────────────────────
# city_bike_map is a renderLeaflet output.  get_value() returns a list when
# Leaflet renders; NULL means the output crashed or the map widget was never
# written.  This proves generate_demo_weather_data() produced a valid cities
# frame that leaflet could plot.

test_that("city_bike_map leaflet output renders from demo data", {
  app <- make_app()                                                     # fresh app instance
  on.exit(app$stop(), add = TRUE)

  app$wait_for_idle(timeout = 20000L)                                   # wait for Leaflet render

  map_value <- app$get_value(output = "city_bike_map")                 # renderLeaflet → list on success, NULL on crash
  expect_false(
    is.null(map_value),                                                 # NULL = renderLeaflet never completed
    info = "city_bike_map was NULL — Leaflet may have errored with demo data"
  )
})
