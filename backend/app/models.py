from pydantic import BaseModel, Field
from typing import Optional


class RatesResponse(BaseModel):
    """Response model with multiple rate types per currency"""
    base: str = Field(..., description="Base currency code")
    date: str = Field(..., description="Date in YYYY-MM-DD format")
    rates: dict[str, dict[str, float]] = Field(..., description="Currency rates by type {currency: {type: rate}}")


class CurrenciesResponse(BaseModel):
    """Response model for currencies list"""
    currencies: dict[str, str] = Field(..., description="Currency code to name mapping")


class HealthResponse(BaseModel):
    """Health check response"""
    status: str = "ok"
    message: str = "Exchange Rate API"
