"""Survival forecast from the trained model artifacts (Track A)."""

from lifetwin.prediction.survival import SurvivalModel, load_model

__all__ = ["SurvivalModel", "load_model"]
