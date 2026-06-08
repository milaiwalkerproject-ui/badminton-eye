---
name: model-evaluation
description: |
  Model evaluation for data scientists — delegates to ds-model-evaluator agent.
  Use when computing classification or regression metrics, plotting ROC/PR
  curves, calibrating probabilities, tuning decision thresholds, or comparing
  models statistically.
---

# Model Evaluation Command

> Evaluate model performance with metrics, calibration, threshold analysis, and residual diagnostics

## Usage

```bash
/ds-model-evaluation <model-or-description>
```

## Examples

```bash
/ds-model-evaluation "Evaluate churn classifier — AUC, F1, calibration curve"
/ds-model-evaluation "Compare RandomForest vs XGBoost on test set"
/ds-model-evaluation "Tune decision threshold to maximize F1 for fraud detection"
/ds-model-evaluation "Regression diagnostics for house price model"
```

---

## What This Command Does

1. Invokes the **ds-model-evaluator** agent
2. Identifies problem type (classification vs regression) and business objective
3. Loads KB patterns from `scikit-learn` and `data-visualization` domains
4. Generates:
   - Full metric report (AUC, F1, avg precision for clf; RMSE, MAE, R² for reg)
   - ROC and Precision-Recall curve plots
   - Calibration display (reliability diagram)
   - Threshold sensitivity analysis (precision/recall/F1 vs threshold)
   - Residual plots and error distribution

## Agent Delegation

| Agent | Role |
|-------|------|
| `ds-model-evaluator` | Primary — metrics, curves, calibration, threshold tuning |
| `ds-statistician` | Escalation — when statistical model comparison test is needed |
| `ds-time-series-analyst` | Escalation — when evaluating a forecast model |
| `ds-experiment-tracker` | Escalation — when metrics must be logged to MLflow |

## KB Domains Used

- `scikit-learn` — metrics API, calibration, ROC/PR curves
- `data-visualization` — evaluation plots, residual charts
- `statistical-analysis` — model comparison tests, distribution checks

## Output

The agent generates a metric report, evaluation plots, and threshold recommendation tailored to the business objective.
