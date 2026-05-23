# 📂 Processed Data

This directory contains cleaned and transformed datasets used for modelling, analysis, and prediction.

---

## 📌 Description

The processed data represents the **transformation layer** of the pipeline, where raw data is:

- Cleaned
- Standardised
- Enriched with engineered features

These datasets are optimised for machine learning and downstream analytics.

---

## 📄 Files

### 1. `clean_bike_data.csv`

- Cleaned version of the raw dataset
- Includes:
  - Parsed datetime features
  - Removed missing or inconsistent values
  - Standardised column formats
  - Derived temporal features (hour, day, season)

---

### 2. `model.csv`

- Final dataset used for the IBM Capstone Shiny deployment model
- Provided by IBM Skills Network; serves as the linear-model coefficient table consumed by `shiny_app/model_prediction.R`
- Includes:
  - Selected features relevant for prediction
  - Encoded categorical variables
  - Scaled / normalised inputs (if applicable)

---

## ⚙️ Usage

This data is used in:

- **Model Training**
- **Model Evaluation**
- **Feature Importance Analysis**
- **Prediction Pipeline**

---

## 🔁 Pipeline Flow

Raw Data → Cleaning → Feature Engineering → Model Dataset

---

## ⚠️ Notes

- Files in this directory are **generated outputs**
- Should not be manually edited
- Regenerated through notebooks or pipeline scripts
