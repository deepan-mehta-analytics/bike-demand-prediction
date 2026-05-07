# 🚲 Bike-Sharing Demand Prediction System

---

## ⚡ Quick Summary

This project delivers a full-stack predictive analytics system for bike-sharing demand forecasting, built across two independent language tracks (R and Python) as part of the IBM Applied Data Science with R Capstone. Starting from raw Seoul city data, the system spans ETL pipelines, SQL-based exploratory analysis, multi-model regression benchmarking, and a live Shiny dashboard fed by real-time OpenWeather API data.

The R pipeline benchmarks six model classes on a chronological 80/20 held-out split, achieving a Random Forest with R²=0.730 (RMSE 333.89 bikes/hr) — a 39% improvement over the baseline linear model. The Bikecast Shiny dashboard provides live 24-hour demand forecasts for five global cities rendered as an interactive Leaflet map with city drill-down and demand-band filtering.

### End-to-end ML pipeline: raw Seoul data → six competing models → live global demand forecast

---

## 🏷️ Project Badges

[![CI](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml/badge.svg)](https://github.com/deepan-mehta-analytics/bike-demand-prediction/actions/workflows/ci.yml)
![R](https://img.shields.io/badge/R-276DC3?style=for-the-badge&logo=r&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Shiny](https://img.shields.io/badge/Shiny-1F77B4?style=for-the-badge)
![Machine Learning](https://img.shields.io/badge/Machine%20Learning-Regression-orange?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Production%20Ready-success?style=for-the-badge)
![API](https://img.shields.io/badge/API-OpenWeather-blue?style=for-the-badge)
![IBM](https://img.shields.io/badge/IBM-Data%20Analytics%20Capstone-054ADA?style=for-the-badge&logo=ibm&logoColor=white)

---

## 📌 Project Overview

- **Dual-language pipelines** — Parallel R and Python implementations of the complete data science workflow, from raw data ingestion through to model serialisation
- **End-to-end ML** — ETL → SQL EDA → regularised regression → Random Forest → deployed dashboard, all reproducible from source
- **Six models benchmarked** — Baseline OLS, Refined OLS, Ridge, Lasso, Elastic Net, and Random Forest evaluated on a chronological 80/20 held-out split
- **Live weather integration** — Real-time OpenWeather 5-day forecast API feeds the Shiny dashboard with 24-hour demand predictions
- **Five global cities** — Seoul, London, New York, Paris, Chicago rendered on an interactive Leaflet map with colour-coded demand markers
- **IBM Capstone structure** — Three notebook tracks: self-built Python pipeline, self-built R pipeline, and IBM-mandated graded submission R pipeline

---

## ⚙️ Tech Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Data wrangling | dplyr, tidyr, stringr (R) · pandas, numpy (Py) | Reshape, filter, and clean tabular data |
| Database / SQL | RSQLite, DBI (R) · sqlite3, sqlalchemy (Py) | Local SQLite storage and SQL EDA |
| Modelling | caret, glmnet, randomForest (R) · scikit-learn (Py) | Regularised regression, cross-validation, Random Forest |
| Visualisation | ggplot2, Leaflet (R) · matplotlib, seaborn, plotly (Py) | Statistical plots and interactive maps |
| API integration | httr (R) · requests (Py) | OpenWeather 5-day forecast fetch |
| Dashboard | R Shiny, shinythemes, shinyjs | Live Bikecast 24-hr demand web app |
| Development | RStudio, JupyterLab | Notebook authoring and Shiny development |

---

## 🎯 Business Problem

> How can weather and time-of-day patterns be used to forecast hourly bike-sharing demand, enabling operators to pre-position bikes, balance station inventory, and reduce rebalancing costs across global city networks?

The Seoul Bike Sharing dataset provides 8,760 hourly observations (Jan 2017 – Nov 2018), combining weather measurements with ridership counts. The system learns these patterns and generalises them to five peer cities using live weather forecasts.

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         DATA LAYER                               │
│  Seoul UCI dataset (CSV) ──► RSQLite / sqlite3 (local DB)        │
│  OpenWeather 5-day API ────► raw_cities_weather_forecast.csv      │
│  Peer cities lookup ───────► selected_cities.csv                  │
└──────────────────────────────┬───────────────────────────────────┘
                               │
┌──────────────────────────────▼───────────────────────────────────┐
│                       PIPELINE LAYER                             │
│                                                                  │
│   Track 1 — Python                  Track 2 — R                  │
│   NB 01 Data Collection             NB 01 Data Collection         │
│   NB 02 ETL / Wrangling             NB 02 Data Wrangling          │
│   NB 03 SQL EDA                     NB 03 SQL EDA                 │
│   NB 04 Baseline Model              NB 04 Baseline Model          │
│   NB 05 Model Refinement            NB 05 Model Refinement        │
│   NB 06 Evaluation & Diagnostics    NB 06 Evaluation              │
│   NB 07 Feature Importance          NB 07 Feature Importance      │
│   NB 08 Model Selection ──────────► my_trained_model.rds / .pkl  │
│   NB 09 API Integration             NB 09 API Pipeline            │
│   NB 10 Prediction Pipeline         NB 10 Dashboard Data Prep     │
│   NB 11 Dashboard Prep              NB 11 Shiny Integration       │
│   NB 12 Project Summary                                           │
│                                                                  │
│   Track 3 — R (IBM Graded Submission, notebooks 04–08)           │
└──────────────────────────────┬───────────────────────────────────┘
                               │
┌──────────────────────────────▼───────────────────────────────────┐
│                     DEPLOYMENT LAYER                             │
│  IBM model.csv ──────────► shiny_app/ (Bikecast dashboard)       │
│  OpenWeather API ────────►   ui.R + server.R + model_prediction.R │
│  Leaflet map, demand bands, city drill-down, expand-to-modal     │
└──────────────────────────────────────────────────────────────────┘
```

| Layer | Component | Technology |
|-------|-----------|------------|
| Data ingestion | UCI dataset + peer cities + API fetch | R httr / Python requests |
| Storage | Local SQLite database | RSQLite / sqlite3 |
| ETL | Wrangling, normalisation, feature engineering | dplyr / pandas |
| Exploration | SQL queries + visual EDA | ggplot2 / matplotlib, seaborn |
| Modelling | Baseline → Ridge → Lasso → Elastic Net → Random Forest | caret, glmnet, randomForest / scikit-learn |
| Serialisation | Model artefact persistence | RDS + CSV / joblib pkl |
| Dashboard | Live 24-hr forecast + interactive Leaflet map | R Shiny, shinythemes, shinyjs |

---

## 📓 Notebook Tracks — Important Context

This repository contains **three parallel notebook tracks**.

| # | Language | Folder | Purpose |
|---|----------|--------|---------|
| 1 | Python | `notebooks/Python/` | Exploratory parallel implementation of the full pipeline |
| 2 | R | `notebooks/R/` | Full self-built R pipeline — produces own trained model |
| 3 | R | `notebooks/R_submission/` | IBM Coursera-mandated pipeline used for graded submission and presentation |

### Why three tracks?

The capstone runs in two stages:

**Modules 1–4 (self-directed):** The pipeline was built independently. Both Python and R implementations were developed in parallel.

**Module 5 (graded submission):** IBM Coursera provided a specific set of R starter notebooks and their own pre-trained `model.csv` for the Shiny dashboard. The notebooks were completed, all graded artefacts were produced, and those results were used for the capstone presentation.

> The presentation is based on the submission track.  
> The Shiny app uses the IBM-provided deployment model (`model.csv`), which differs from the self-trained models developed in the R pipeline.

This separation reflects real-world machine learning workflows, where experimentation, validation, and deployment often rely on different model pipelines.

---

## 📊 Dashboard Preview

### 🌍 Global Demand Overview
![Overview Map](results/screenshots/dashboard_overview.png)

### 🔍 City Drill-Down
![City Drilldown](results/screenshots/city_drilldown.png)

### 📈 Temperature Trend
![Temperature Trend](results/screenshots/temperature_trend.png)

### 🚲 Bike Demand Forecast — Next 24 Hours
![Demand Forecast](results/screenshots/bike_demand_next_24_hrs.png)

### 💧 Humidity vs Demand Correlation
![Humidity](results/screenshots/humidity_vs_demand.png)

---

## 📁 Repository Structure

```
bike-demand-prediction/
│
├── README.md
│
├── data/
│   ├── raw/
│   │   ├── seoul_bike_sharing.csv              # Original Seoul dataset (UCI)
│   │   └── selected_cities.csv                 # 5 peer cities with lat/lng
│   └── processed/
│       ├── clean_bike_data.csv                 # Wrangled, complete-case dataset
│       └── model.csv                           # IBM-provided model (used by Shiny app)
│
├── notebooks/
│   │
│   ├── Python/                                 # ── TRACK 1: Python pipeline
│   │   ├── 01_data_collection_py.ipynb
│   │   ├── 02_etl_py.ipynb
│   │   ├── 03_eda_py.ipynb
│   │   ├── 04_baseline_model_py.ipynb
│   │   ├── 05_model_refinement_py.ipynb
│   │   ├── 06_model_evaluation_py.ipynb
│   │   ├── 07_feature_importance_py.ipynb
│   │   ├── 08_model_selection_py.ipynb
│   │   ├── 09_api_integration_py.ipynb
│   │   ├── 10_prediction_pipeline_py.ipynb
│   │   ├── 11_dashboard_preparation_py.ipynb
│   │   └── 12_final_project_summary_py.ipynb
│   │
│   ├── R/                                      # ── TRACK 2: R self-built pipeline
│   │   ├── 01_data_collection_R.ipynb
│   │   ├── 02_data_wrangling_R.ipynb
│   │   ├── 03_exploratory_data_analysis_R.ipynb
│   │   ├── 04_baseline_model_R.ipynb
│   │   ├── 05_model_refinement_R.ipynb
│   │   ├── 06_model_evaluation_R.ipynb
│   │   ├── 07_feature_importance_R.ipynb
│   │   ├── 08_model_selection_R.ipynb          # → produces my_trained_model.csv/.rds
│   │   ├── 09_api_pipeline_R.ipynb
│   │   ├── 10_dashboard_data_preparation_R.ipynb
│   │   └── 11_shiny_dashboard_integration_R.ipynb
│   │
│   └── R_submission/                           # ── TRACK 3: IBM graded submission
│       ├── 01_data_collection_R.ipynb
│       ├── 02_data_wrangling_R.ipynb
│       ├── 03_exploratory_data_analysis_R.ipynb
│       ├── 04_baseline_model_R.ipynb
│       ├── 05_model_refinement_R.ipynb
│       ├── 06_model_evaluation_diagnostics_R.ipynb
│       ├── 07_feature_importance_R.ipynb
│       ├── 08_final_model_selection_R.ipynb
│       ├── 09_api_data_collection_and_prediction_pipeline_R.ipynb
│       ├── 10_dashboard_data_preparation_R.ipynb
│       └── 11_shiny_dashboard_integration_R.ipynb
│
├── reports/
│   └── Applied_Data_Science_with_R_Capstone_project.pdf   ← capstone presentation (PDF)
│
├── results/
│   ├── models/
│   │   ├── my_trained_model.csv                # Model comparison table — all 6 evaluated models
│   │   ├── my_trained_model.rds                # Serialised Random Forest model object (R binary)
│   │   └── final_bike_demand_model.pkl         # Serialised Random Forest model object (Python/joblib)
│   └── screenshots/
│       ├── dashboard_overview.png
│       ├── city_drilldown.png
│       ├── temparature_trend.png
│       ├── bike_demand_next_24_hrs.png
│       └── humidity_vs_demand.png
│
├── shiny_app/                                  # ── Bikecast dashboard
│   ├── ui.R
│   ├── server.R
│   └── model_prediction.R
│
└── .gitignore
```

---

## 🤖 Model Summary

Two model pipelines exist in this project, corresponding to each stage of the programme.

### Trained Model — Random Forest Regressor ★
*Track 2 · `notebooks/R/08_model_selection_R.ipynb` · `results/models/my_trained_model.rds`*

Trained on the Seoul Bike Sharing dataset using a chronological 80/20 train-test split
(200 estimators, full feature set, seed 123). Five model classes evaluated on held-out test data.

| Model | Specification | Test RMSE | Test R² |
|-------|--------------|-----------|---------|
| Baseline OLS | temperature + humidity + wind_speed | 549.03 | 0.338 |
| Refined OLS | + temp², humidity², temp×humidity | 509.53 | 0.385 |
| Ridge (α=0) | Full feature set, λ via 10-fold CV | 437.25 | 0.518 |
| Lasso (α=1) | Full feature set, λ via 10-fold CV | 417.52 | 0.536 |
| Elastic Net (α=0.5) | Full feature set, λ via 10-fold CV | 417.54 | 0.536 |
| **Random Forest ★** | **200 trees, full feature set** | **333.89** | **0.730** |

Random Forest achieves a **39% RMSE reduction over the baseline** and explains **73% of variance**
in held-out data — a 19.4 percentage point improvement over the best regularised linear model.
Top predictors by importance: temperature, hour, dew point temperature, humidity, solar radiation.

### Trained Model — Python Track
*Track 1 · `notebooks/Python/08_model_selection_py.ipynb` · `results/models/final_bike_demand_model.pkl`*

Trained on the normalised Seoul dataset using a chronological 80/20 split and serialised via joblib.
The ETL stage applies min-max scaling to all numeric columns; RMSE values below are reported in original units (bikes/hr) via inverse transform: `x = x_norm × (y_max − y_min) + y_min` (y_min=2, y_max=3556).

| Model | Test R² | Test RMSE (bikes/hr) |
|-------|---------|----------------------|
| Polynomial (degree=2) | 0.271 | 462.0 |
| Ridge | 0.430 | 408.7 |
| Lasso | −0.077 | 565.1 |
| Elastic Net | −0.077 | 565.1 |
| **Random Forest ★** | **0.518** | **376.7** |

Random Forest is the selected model. Lasso and Elastic Net produce negative R² at this
regularisation strength (α=0.1), indicating over-penalisation on a normalised target.
Track 2 achieves higher R² (0.730) and lower RMSE (333.89 bikes/hr) through richer feature
engineering and original-scale modelling — a 42.8 bike/hr improvement over the Python RF.

### IBM Deployed Model
*Track 3 · provided by IBM Skills Network · `data/processed/model.csv`*

Used by the Bikecast Shiny app. A fixed-effects linear model with weather coefficients plus per-season and per-hour offsets, applied via `model_prediction.R`.

```
PREDICTED_BIKES =
    938.84
  + TEMPERATURE  × 25.18
  + HUMIDITY     × (−8.45)
  + WIND_SPEED   × 2.42
  + VISIBILITY   × 0.007
  + season_offset   # SPRING +2.32 | AUTUMN +160.19 | WINTER −204.27
  + hour_offset     # 24 individual offsets, floored at 0 via pmax()
```

Scored on the same held-out test set as Track 2 (chronological 80/20 split, Sep–Nov 2018):

| Metric | IBM Linear (model.csv) | Random Forest ★ (Track 2) |
|--------|------------------------|---------------------------|
| Test RMSE | 342.60 bikes/hr | **333.89 bikes/hr** |
| Test R² | 0.6723 | **0.7305** |

The IBM fixed-effects linear model outperforms every regularised model in Track 2 (Ridge, Lasso, Elastic Net) and comes within 8.7 bikes/hr of the Random Forest — a strong result for a linear model, attributable to its 24 individual hour offsets capturing the daily demand cycle with precision.

---

## 🔍 Key EDA Findings

| Finding | Detail | Source |
|---------|--------|--------|
| 🕕 Peak hours | 17:00–19:00 (evening commute) | SQL Query 7 |
| 🌡️ Top predictor | Temperature — strong positive linear relationship | Notebooks 07/08 |
| 📅 Seasonal swing | Summer avg 1,034 bikes/hr vs Winter 226 — a 4.6× range | SQL Query 9 |
| 💧 Humidity response | Concave: positive at low %, suppressive at high % | Notebook 05 |
| 🌧️ Precipitation | Even <1mm rainfall significantly reduces demand | EDA viz |
| 🕐 Daily cycle | Bimodal peaks at 08:00 and 18:00; near-zero 01:00–05:00 | SQL Query 8 |

---

## 🚀 Bikecast — R Shiny Dashboard

A professional three-column dashboard built on the **Yeti Bootswatch** theme.

**Features:**
- Live 24-hour forecast via OpenWeather API (8 × 3-hour slots)
- Interactive Leaflet map with colour-coded demand markers
- Demand filter toggle buttons (Low / Medium / High)
- City drill-down with three charts — all click-to-inspect
- Expand-to-modal on every chart for full-screen view
- City comparison bar chart + summary table in the global overview

**Demand bands:**

| Level | Bikes per 3h slot | Map Marker |
|-------|------------------|------------|
| 🟢 Low | < 1,000 | Green, radius 6 |
| 🟡 Medium | 1,000 – 3,000 | Yellow, radius 10 |
| 🔴 High | > 3,000 | Red, radius 12 |

**Cities covered:** Seoul · London · New York · Paris · Chicago

---

## ▶️ How to Run

### 1. Clone the repository

```bash
git clone https://github.com/deepan-mehta-analytics/bike-demand-prediction.git
cd bike-demand-prediction
```

### 2. Set your OpenWeather API key

Get a free key at [openweathermap.org](https://home.openweathermap.org/api_keys). Store it securely — **never paste it directly into code**.

```r
# Run this in your R console to open .Renviron:
usethis::edit_r_environ()
```

Add this line and save:
```
OPENWEATHER_KEY=your_actual_key_here
```

Restart R. New keys can take up to **2 hours** to activate on OpenWeather's free tier.

### 3. Install dependencies

**R packages (recommended — uses pinned versions from `renv.lock`):**
```r
renv::restore()
```

**R packages (alternative — installs latest CRAN versions):**
```r
source("install_packages.R")
```

**Python packages:**
```bash
pip install -r requirements.txt
```

### 4. Run the Shiny app

```r
shiny::runApp("shiny_app/")
```

All Shiny-specific packages install automatically on first run if not already present.

---

## 🧪 Tests

No automated test suite is implemented in this capstone project. Correctness is verified through:

- **Chronological 80/20 train/test split** — time-aware holdout prevents data leakage by design
- **RMSE and R² on held-out test data** — all model numbers reported from the unseen test set
- **Dashboard manual validation** — Shiny app verified against live OpenWeather responses

> Automated test coverage (pytest / testthat) is listed in the Roadmap below.

---

## 📄 Presentation

The capstone presentation covers the full pipeline from data collection through to the live dashboard.

> **`reports/Applied_Data_Science_with_R_Capstone_project.pdf`**

| Slides | Content |
|--------|---------|
| 1–13 | Executive summary, introduction, methodology |
| 14–20 | EDA results — SQL queries, seasonality, peer-city analysis |
| 21–25 | Visualisation results — scatter plots, histogram, precipitation |
| 26–30 | Modelling — coefficients, RMSE/R² comparison, Q-Q diagnostics |
| 31–34 | Bikecast dashboard screenshots and technical walkthrough |
| 35–52 | Conclusion, appendix, references |

> Results on slides 26–30 are based on the IBM submission notebooks (`notebooks/R_submission/`). The Shiny app uses the IBM-provided `model.csv` rather than the self-trained Random Forest — both models are documented in the Model Summary section above.

---

## ⚠️ Known Limitations

- **Python RF weaker than R RF** — Python Random Forest achieves R²=0.518 / RMSE=376.7 bikes/hr vs R Track R²=0.730 / RMSE=333.89; gap is attributable to richer feature engineering and original-scale modelling in the R pipeline
- **Lasso / Elastic Net over-penalised on Python track** — both produce negative R² at α=0.1 on the normalised target, indicating regularisation is too aggressive at that scale
- **IBM model scored on Track 2 test set** — RMSE 342.60, R² 0.6723; see IBM Deployed Model section for full comparison
- **OpenWeather free tier limits** — new API keys take up to 2 hours to activate; rate limits apply at scale
- **renv library not included** — `renv/library/` is gitignored (platform-specific binaries); run `renv::restore()` to rebuild the local library from `renv.lock`

---

## 🔜 Roadmap

- [ ] Add pytest / testthat unit tests for ETL and model evaluation functions
- [x] Convert Python RMSE to original scale — inverse min-max transform applied; RF RMSE 376.7 bikes/hr
- [x] `requirements.txt` added (Python); `install_packages.R` added (R)
- [x] IBM model scored against held-out test set — RMSE 342.60, R² 0.6723
- [x] Pin R packages via `renv::snapshot()` — `renv.lock` generated (R 4.4.3, 139 packages pinned)
- [x] Add MIT LICENSE (2026, Deepan Mehta)
- [x] Add GitHub Actions CI — Python + R smoke tests, model.csv integrity check
- [ ] Containerise Shiny app (Docker) for portable deployment
- [ ] Extend city coverage beyond the current five

---

## 📂 Dataset

| Attribute | Detail |
|-----------|--------|
| **Name** | Seoul Bike Sharing Demand |
| **Source** | UCI Machine Learning Repository |
| **Records** | 8,760 hourly observations |
| **Period** | January 2017 – November 2018 |
| **Features** | 14 — weather (temperature, humidity, wind speed, visibility, solar radiation, rainfall, snowfall) + temporal (date, hour, season, holiday, functioning day) |
| **Target** | `rented_bike_count` — bikes rented per hour |
| **License** | Creative Commons Attribution 4.0 |

Sathishkumar V.E., Park J., Cho Y. (2020). *Using data mining techniques for bike sharing demand prediction in metropolitan city.* Computer Communications, 153, 353–366.

---

## 👤 Author

**Deepan Mehta**

Data Analytics → Data Engineering → AI/ML Engineering

Focused on building end-to-end data systems combining analytics, machine learning, and deployment. Experience in ETL pipelines, predictive modelling, and interactive dashboards.

🔗 GitHub: [deepan-mehta-analytics](https://github.com/deepan-mehta-analytics)

---

## 📚 References

1. Sathishkumar V.E., Park J., Cho Y. (2020). *Using data mining techniques for bike sharing demand prediction in metropolitan city.* Computer Communications, 153, 353–366.
2. Seoul Bike Sharing Demand Dataset — UCI Machine Learning Repository
3. Luo Y., Grossman J., Ahuja R. et al. — IBM Skills Network / Coursera: *IBM Data Analytics Professional with Excel and R*
4. OpenWeather 5-Day Forecast API — https://openweathermap.org/forecast5

---
