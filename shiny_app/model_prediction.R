# =============================================================================
# model_prediction.R
# -----------------------------------------------------------------------------
# This file contains all the "behind the scenes" logic for the app:
#   1. Fetching live weather forecasts from the OpenWeather API
#   2. Loading a pre-trained regression model from a CSV file
#   3. Predicting bike-sharing demand using that model
#   4. Categorising demand into levels (small / medium / large)
#   5. Combining everything into one tidy data frame for the Shiny app
# =============================================================================


# -----------------------------------------------------------------------------
# SECTION 1 — Load required packages
# -----------------------------------------------------------------------------
# 'if (!require(...))' means: "if this package is NOT already installed,
# install it now, then load it."  This ensures the app works on any machine
# without the user having to run install.packages() manually first.

if (!require(tidyverse)) install.packages("tidyverse")  # Data wrangling tools (dplyr, tibble, etc.)
if (!require(httr))      install.packages("httr")       # Tools for making HTTP/API web requests


# -----------------------------------------------------------------------------
# SECTION 2 — Helper function: safe_val()
# -----------------------------------------------------------------------------
# The OpenWeather API sometimes returns NULL for a field instead of a number.
# In R, appending NULL to a vector silently drops it, making the vector shorter
# than the others — this causes errors later when building a data frame.
#
# safe_val() fixes this: if the value is NULL it returns NA instead,
# which R DOES keep in a vector (it shows up as a missing value placeholder).
#
# Arguments:
#   x       — the value to check (could be a number or NULL)
#   default — what to return if x is NULL (defaults to NA_real_, a numeric NA)

safe_val <- function(x, default = NA_real_) {
  if (is.null(x)) default else x   # Return default if NULL, otherwise return x as-is
}


# -----------------------------------------------------------------------------
# SECTION 3 — get_weather_forecaset_by_cities()
# -----------------------------------------------------------------------------
# Loops over a list of city names, calls the OpenWeather forecast API
# for each one, and collects the results into vectors which are then combined
# into a single tidy data frame (tibble) at the end.
#
# Argument:
#   city_names — a character vector of city names e.g. c("Seoul", "London")
#
# Returns: a tibble with one row per forecast time slot per city

get_weather_forecaset_by_cities <- function(city_names) {
  
  # --- Initialise empty typed vectors ---
  # We use typed empty vectors (character(0), numeric(0)) instead of plain c().
  # In R, c() returns NULL, and tibble() will refuse NULL columns.
  # Typed empty vectors are safe — they just produce a zero-row tibble if
  # the API returns nothing at all.
  
  city                   <- character(0)  # Will hold the city name for each forecast row
  weather                <- character(0)  # Weather condition e.g. "Rain", "Clouds"
  temperature            <- numeric(0)    # Temperature in Celsius
  visibility             <- numeric(0)    # Visibility in metres
  humidity               <- numeric(0)    # Relative humidity as a percentage
  wind_speed             <- numeric(0)    # Wind speed in metres per second
  seasons                <- character(0)  # Season derived from the forecast month
  hours                  <- numeric(0)    # Hour of day (0–23) of each forecast slot
  forecast_date          <- character(0)  # Full datetime string from the API
  weather_labels         <- character(0)  # Short HTML label for the overview map popup
  weather_details_labels <- character(0)  # Detailed HTML label for the drill-down popup
  
  
  # --- Loop over each city ---
  for (city_name in city_names) {
    
    # The base URL for the OpenWeather 5-day / 3-hour forecast endpoint
    url_get <- "https://api.openweathermap.org/data/2.5/forecast"
    
    # Your OpenWeather API key — stored in .Renviron so it stays out of source code.
    # To set this up: run usethis::edit_r_environ() and add the line:
    #   OPENWEATHER_KEY=your_actual_key_here
    # Then restart R. Sys.getenv() reads it back safely at runtime.
    api_key <- Sys.getenv("OPENWEATHER_KEY")
    
    # Build the query parameters that get appended to the URL:
    #   q     = city name to search for
    #   appid = your API key for authentication
    #   units = "metric" means temperatures come back in Celsius
    forecast_query <- list(q = city_name, appid = api_key, units = "metric")
    
    # Make the HTTP GET request to the API and store the response object
    response <- GET(url_get, query = forecast_query)
    
    # --- Check for HTTP errors ---
    # http_error() returns TRUE if the server responded with an error code
    # (e.g. 401 Unauthorised = bad API key, 404 Not Found = city not recognised)
    if (http_error(response)) {
      json_err <- content(response, as = "parsed")   # Parse the error response body
      stop(paste0(
        "API error for city '", city_name, "': ",
        "HTTP ", status_code(response), " -- ",       # Show the numeric status code
        safe_val(json_err$message, "no message returned"),  # Show API's error message
        "\nCheck that your API key is valid and active."
      ))
    }
    
    # Parse the successful JSON response into an R list
    json_list <- content(response, as = "parsed")
    
    # The forecast data lives inside the "list" element of the response
    # Limit to first 8 slots = next 24 hours (8 x 3h intervals)
    results <- head(json_list$list, 8)
    
    # --- Guard: skip city if the results list is empty ---
    # is.null() catches a missing element; length() == 0 catches an empty list
    if (is.null(results) || length(results) == 0) {
      warning(paste("No forecast results returned for city:", city_name))
      next   # 'next' skips the rest of this loop iteration and moves to the next city
    }
    
    
    # --- Loop over each forecast time slot for this city ---
    # The full API returns up to 40 slots (5 days × 8 slots per day, every 3 hours)
    for (result in results) {
      
      # Append the city name to the city vector (one entry per forecast slot)
      city <- c(city, city_name)
      
      # Extract the main weather condition (e.g. "Rain", "Clouds", "Clear")
      # safe_val() protects against the field being NULL in the API response
      weather <- c(weather, safe_val(result$weather[[1]]$main, "Unknown"))
      
      # --- Extract numeric weather variables ---
      # Each is wrapped in safe_val() so a missing API field becomes NA
      # rather than being silently dropped (which would shorten the vector)
      temp_val <- safe_val(result$main$temp)       # Temperature °C
      vis_val  <- safe_val(result$visibility)      # Visibility in metres
      hum_val  <- safe_val(result$main$humidity)   # Humidity %
      wind_val <- safe_val(result$wind$speed)      # Wind speed m/s
      
      # Append each value to its respective vector
      temperature <- c(temperature, temp_val)
      visibility  <- c(visibility,  vis_val)
      humidity    <- c(humidity,    hum_val)
      wind_speed  <- c(wind_speed,  wind_val)
      
      # --- Parse the forecast datetime string ---
      # dt_txt comes from the API as a string like "2024-04-13 12:00:00"
      forecast_datetime <- result$dt_txt
      
      # Convert the string to a proper POSIXct datetime object so we can
      # extract the hour and month as numbers reliably
      forecast_dt_parsed <- as.POSIXct(forecast_datetime,
                                       format = "%Y-%m-%d %H:%M:%S",
                                       tz = "UTC")
      
      hour  <- as.numeric(format(forecast_dt_parsed, "%H"))  # Extract hour  (0–23)
      month <- as.numeric(format(forecast_dt_parsed, "%m"))  # Extract month (1–12)
      
      # Store the original datetime string for display in the popup
      forecast_date <- c(forecast_date, forecast_datetime)
      
      # --- Determine season from month number ---
      # !is.na(month) guards against a failed datetime parse returning NA
      if      (!is.na(month) && month >= 3 && month <= 5)   season <- "SPRING"
      else if (!is.na(month) && month >= 6 && month <= 8)   season <- "SUMMER"
      else if (!is.na(month) && month >= 9 && month <= 11)  season <- "AUTUMN"
      else                                                    season <- "WINTER"  # Dec, Jan, Feb
      
      # --- Build HTML popup labels ---
      # paste() with sep="" concatenates strings with no separator between them.
      # These strings contain HTML tags (<b>, </br> etc.) that Leaflet renders
      # as formatted text inside the map popup bubble.
      
      # Short label — just city name + weather condition (used on the overview map)
      weather_label <- paste(sep = "",
                             "<b><a href=''>", city_name, "</a></b>", "</br>",
                             "<b>", safe_val(result$weather[[1]]$main, "N/A"), "</b></br>"
      )
      
      # Detailed label — all weather fields (used in the city drill-down view)
      weather_detail_label <- paste(sep = "",
                                    "<b><a href=''>", city_name, "</a></b>", "</br>",
                                    "<b>", safe_val(result$weather[[1]]$main, "N/A"), "</b></br>",
                                    "Temperature: ", temp_val, " C </br>",
                                    "Visibility: ",  vis_val,  " m </br>",
                                    "Humidity: ",    hum_val,  " % </br>",
                                    "Wind Speed: ",  wind_val, " m/s </br>",
                                    "Datetime: ", forecast_datetime, " </br>"
      )
      
      # Append both labels to their respective vectors
      weather_labels         <- c(weather_labels,         weather_label)
      weather_details_labels <- c(weather_details_labels, weather_detail_label)
      
      # Append season and hour to their vectors
      seasons <- c(seasons, season)
      hours   <- c(hours,   hour)
      
    }  # end inner for loop (forecast slots)
  }    # end outer for loop (cities)
  
  
  # --- Combine all vectors into a single tidy tibble ---
  # Every vector must be the same length — one element per forecast slot.
  # Note: SEASONS uses the full 'seasons' vector (built in the loop),
  # NOT 'season' (which would just be the last single value — a common bug!)
  weather_df <- tibble(
    CITY_ASCII      = city,
    WEATHER         = weather,
    TEMPERATURE     = temperature,
    VISIBILITY      = visibility,
    HUMIDITY        = humidity,
    WIND_SPEED      = wind_speed,
    SEASONS         = seasons,         # <-- plural vector, NOT scalar 'season'
    HOURS           = hours,
    FORECASTDATETIME = forecast_date,
    LABEL           = weather_labels,
    DETAILED_LABEL  = weather_details_labels
  )
  
  return(weather_df)  # Return the completed data frame to the caller
}


# -----------------------------------------------------------------------------
# SECTION 4 — load_saved_model()
# -----------------------------------------------------------------------------
# Reads a pre-trained linear regression model from a CSV file.
# The CSV has two columns: "Variable" (predictor name) and "Coef" (coefficient).
# We turn this into a named numeric vector so we can do:
#   model["TEMPERATURE"]  →  25.17  (the coefficient for temperature)
#
# Argument:
#   model_name — file path to the CSV e.g. "model.csv"
#
# Returns: a named numeric vector of model coefficients

load_saved_model <- function(model_name) {
  
  model <- read_csv(model_name)   # Read the CSV into a data frame
  
  # The Variable column may contain stray quote characters from the CSV export.
  # gsub() finds and removes all " characters from the Variable column.
  model <- model %>%
    mutate(Variable = gsub('"', '', Variable))
  
  # setNames() creates a named vector: the VALUES are the coefficients,
  # and the NAMES are the variable names — so we can look them up by name later.
  coefs <- setNames(model$Coef, as.list(model$Variable))
  
  return(coefs)
}


# -----------------------------------------------------------------------------
# SECTION 5 — predict_bike_demand()
# -----------------------------------------------------------------------------
# Uses the loaded regression model to predict how many bikes will be needed.
# A linear regression model predicts an outcome as a weighted sum of inputs:
#
#   prediction = Intercept
#              + (TEMPERATURE × coef_temp)
#              + (HUMIDITY    × coef_humidity)
#              + ...
#              + season_coefficient
#              + hour_coefficient
#
# Arguments: vectors of weather values — one element per forecast row
# Returns:   integer vector of predicted bike counts (minimum 0, no negatives)

predict_bike_demand <- function(TEMPERATURE, HUMIDITY, WIND_SPEED, VISIBILITY, SEASONS, HOURS) {
  
  # Load the model coefficients from CSV
  model <- load_saved_model("model.csv")
  
  # --- Calculate the continuous weather terms ---
  # This is a vectorised operation: R multiplies each element of TEMPERATURE
  # by model['TEMPERATURE'] simultaneously for all rows at once.
  # model['Intercept'] is the baseline prediction before any inputs are applied.
  weather_terms <- model['Intercept'] +
    TEMPERATURE * model['TEMPERATURE'] +
    HUMIDITY    * model['HUMIDITY']    +
    WIND_SPEED  * model['WIND_SPEED']  +
    VISIBILITY  * model['VISIBILITY']
  
  # --- Calculate season coefficients ---
  # The model has a separate coefficient for each season.
  # We loop over each row's season value and look up the matching coefficient.
  # switch() works like a lookup table: given a season string, return its coefficient.
  # The trailing '0' is a default — if the season doesn't match any case,
  # return 0 instead of NULL (NULL would silently shorten the vector and cause errors).
  season_terms <- c()   # Start with an empty vector to collect results into
  for (season in SEASONS) {
    season_term <- switch(season,
                          'SPRING' = model['SPRING'],
                          'SUMMER' = model['SUMMER'],
                          'AUTUMN' = model['AUTUMN'],
                          'WINTER' = model['WINTER'],
                          0                             # Default: unknown season contributes 0
    )
    season_terms <- c(season_terms, season_term)  # Append this row's season term
  }
  
  # --- Calculate hour-of-day coefficients ---
  # Bike demand varies greatly by time of day (peak commute hours vs. overnight).
  # The model has a separate coefficient for each of the 24 hours.
  # as.character(hour) converts the number to a string for switch() to match on.
  hour_terms <- c()   # Start with an empty vector to collect results into
  for (hour in HOURS) {
    hour_term <- switch(as.character(hour),
                        '0'  = model['0'],  '1'  = model['1'],  '2'  = model['2'],  '3'  = model['3'],
                        '4'  = model['4'],  '5'  = model['5'],  '6'  = model['6'],  '7'  = model['7'],
                        '8'  = model['8'],  '9'  = model['9'],  '10' = model['10'], '11' = model['11'],
                        '12' = model['12'], '13' = model['13'], '14' = model['14'], '15' = model['15'],
                        '16' = model['16'], '17' = model['17'], '18' = model['18'], '19' = model['19'],
                        '20' = model['20'], '21' = model['21'], '22' = model['22'], '23' = model['23'],
                        0                             # Default: unknown hour contributes 0
    )
    hour_terms <- c(hour_terms, hour_term)  # Append this row's hour term
  }
  
  # --- Sum all terms and clamp negatives to zero ---
  # Add all three term vectors together to get the raw prediction for each row.
  # as.integer() rounds to whole numbers (you can't have 1.5 bikes).
  # pmax(..., 0, na.rm=TRUE) is the "parallel maximum" function:
  #   - It compares each element against 0 and keeps whichever is larger.
  #   - This prevents negative predictions (a model can predict < 0 but
  #     you can't have negative bikes in reality).
  #   - na.rm=TRUE means any NA value is treated as 0 rather than crashing.
  regression_terms <- pmax(
    as.integer(weather_terms + season_terms + hour_terms),
    0,           # Floor value — predictions cannot go below zero
    na.rm = TRUE # Treat NA predictions as 0 instead of propagating the error
  )
  
  return(regression_terms)  # Return the vector of predicted bike counts
}


# -----------------------------------------------------------------------------
# SECTION 6 — calculate_bike_prediction_level()
# -----------------------------------------------------------------------------
# Takes the numeric bike predictions and bins them into three named levels.
# These levels are used to colour-code the map markers (green / yellow / red).
#
# Argument:  predictions — integer vector of predicted bike counts
# Returns:   character vector of "small", "medium", or "large"

calculate_bike_prediction_level <- function(predictions) {
  
  levels <- c()   # Empty vector to collect the level label for each prediction
  
  for (prediction in predictions) {
    if      (prediction >= 0    && prediction <= 1000) levels <- c(levels, 'small')   # Green marker
    else if (prediction >  1000 && prediction <  3000) levels <- c(levels, 'medium')  # Yellow marker
    else                                               levels <- c(levels, 'large')   # Red marker
  }
  
  return(levels)
}


# -----------------------------------------------------------------------------
# SECTION 7 — generate_city_weather_bike_data()
# -----------------------------------------------------------------------------
# This is the main entry point called by server.R.
# It orchestrates all the functions above into one pipeline:
#   1. Load the list of cities from CSV
#   2. Fetch live weather forecasts for those cities
#   3. Add bike demand predictions to each forecast row
#   4. Add demand level labels (small / medium / large)
#   5. Join city coordinates back in and return the final data frame
#
# Returns: a tibble with one row per forecast slot per city,
#          containing weather data, bike predictions, and map labels

generate_city_weather_bike_data <- function() {
  
  # Read the list of cities (with their lat/lng coordinates) from the CSV file
  cities_df <- read_csv("selected_cities.csv")
  
  # Fetch live 24-hour weather forecast data (next 8 x 3-hour slots) for every city in the list
  weather_df <- get_weather_forecaset_by_cities(cities_df$CITY_ASCII)
  
  # Add a BIKE_PREDICTION column by running the regression model on each row,
  # then add a BIKE_PREDICTION_LEVEL column by binning those predictions.
  # %>% is the "pipe" operator — it passes the result on the left into the
  # next function on the right, making code easier to read top-to-bottom.
  results <- weather_df %>%
    mutate(BIKE_PREDICTION = predict_bike_demand(
      TEMPERATURE, HUMIDITY, WIND_SPEED, VISIBILITY, SEASONS, HOURS
    )) %>%
    mutate(BIKE_PREDICTION_LEVEL = calculate_bike_prediction_level(BIKE_PREDICTION))
  
  # Join the city coordinates (LAT, LNG) from cities_df back onto the results.
  # left_join() matches rows by the shared column (CITY_ASCII) and adds the
  # coordinate columns from cities_df to every matching row in results.
  # select() then keeps only the columns the Shiny app actually needs.
  cities_bike_pred <- cities_df %>%
    left_join(results) %>%
    select(
      CITY_ASCII,            # City name (used to filter by dropdown selection)
      LNG, LAT,             # Coordinates (used to place markers on the map)
      TEMPERATURE,           # Temperature for display in the popup
      HUMIDITY,              # Humidity for display in the popup
      BIKE_PREDICTION,       # Predicted number of bikes needed
      BIKE_PREDICTION_LEVEL, # "small", "medium", or "large" (controls marker colour)
      LABEL,                 # Short HTML popup for the overview map
      DETAILED_LABEL,        # Full HTML popup for the city drill-down view
      FORECASTDATETIME       # Forecast date and time string
    )
  
  return(cities_bike_pred)  # Return the complete data frame to server.R
}