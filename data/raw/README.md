# 📂 Raw Data

This directory contains the original, unmodified datasets used as inputs for the bike demand prediction system.

---

## 📌 Description

The raw data represents the **initial ingestion layer** of the pipeline and is preserved in its original format to ensure reproducibility and traceability.

No transformations, cleaning, or feature engineering steps are applied at this stage.

---

## 📄 Files

### 1. `seoul_bike_sharing.csv`

- Core dataset containing historical bike rental data
- Includes:
  - Date and time information
  - Weather conditions (temperature, humidity, wind speed)
  - Holiday and seasonal indicators
  - Bike rental counts

---

### 2. `selected_cities.csv`

- List of cities used for API-based forecasting
- Supports real-time prediction workflows
- Used in conjunction with the OpenWeather API

---

## ⚙️ Usage

This data is used in:

- **Data Collection / Ingestion**
- **Exploratory Data Analysis (EDA)**
- **Initial feature extraction**

---

## ⚠️ Notes

- Files in this folder should remain **unchanged**
- Any preprocessing must be done in the `data/processed/` directory
- Acts as the **single source of truth** for the pipeline
