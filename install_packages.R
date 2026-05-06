# Install all R packages required by the bike demand prediction pipeline.
# Run once before executing any notebook in notebooks/R/ or shiny_app/.

# ── Data wrangling ────────────────────────────────────────────────────────────
install.packages("dplyr")        # data manipulation verbs (filter, mutate, select)
install.packages("tidyr")        # reshaping (pivot_longer, pivot_wider)
install.packages("stringr")      # string manipulation helpers
install.packages("readr")        # fast CSV reading with read_csv()
install.packages("lubridate")    # date/time parsing and arithmetic

# ── Database / SQL ────────────────────────────────────────────────────────────
install.packages("RSQLite")      # SQLite driver for R
install.packages("DBI")          # generic database interface

# ── Modelling ─────────────────────────────────────────────────────────────────
install.packages("caret")        # unified model training and cross-validation
install.packages("glmnet")       # Ridge, Lasso, and Elastic Net via coordinate descent
install.packages("randomForest") # Random Forest regressor and classifier

# ── Visualisation ─────────────────────────────────────────────────────────────
install.packages("ggplot2")      # Grammar-of-Graphics plotting
install.packages("leaflet")      # interactive Leaflet maps

# ── API / web ─────────────────────────────────────────────────────────────────
install.packages("httr")         # HTTP requests (OpenWeather API calls)
install.packages("jsonlite")     # JSON parsing for API responses

# ── Shiny dashboard ───────────────────────────────────────────────────────────
install.packages("shiny")        # reactive web application framework
install.packages("shinythemes")  # Bootswatch theme support (Yeti theme)
install.packages("shinyjs")      # JavaScript helpers for Shiny (toggle buttons)
