from fastapi import FastAPI, Query, HTTPException
from fastapi.responses import JSONResponse
from datetime import datetime
from typing import Optional
from dotenv import load_dotenv
import os
import logging

from . import database as db
from . import oxr_client
from . import rate_service
from . import scheduler as bg_scheduler
from .models import RatesResponse, HealthResponse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Initialize database
db.init_database()

# Create FastAPI app
app = FastAPI(
    title="Exchange Rate API",
    description="Currency exchange rates with OpenExchangeRates integration and alternative rates support",
    version="1.0.0"
)


@app.get("/", response_model=HealthResponse)
async def root():
    """Health check endpoint"""
    return HealthResponse()


@app.get("/currencies")
async def get_currencies():
    """
    Get list of all supported currencies.
    Proxies to OpenExchangeRates /currencies.json endpoint.
    """
    try:
        currencies = await oxr_client.fetch_currencies()
        return currencies
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch currencies: {str(e)}")


@app.get("/rates", response_model=RatesResponse)
async def get_rates(
    base: str = Query(default="USD", description="Base currency code"),
    symbols: Optional[str] = Query(default=None, description="Comma-separated list of target currencies"),
    date: Optional[str] = Query(default=None, description="Date in YYYY-MM-DD format (defaults to latest available)"),
    rate_type: Optional[str] = Query(default=None, description="Rate type (official, blue, mep, ccl, crypto)")
):
    """
    Get exchange rates for base currency.

    - **base**: Base currency code (default: USD)
    - **symbols**: Comma-separated target currencies (optional, returns all if omitted)
    - **date**: ISO date YYYY-MM-DD (optional, defaults to latest available from OXR)
    - **rate_type**: Specific rate type (optional, returns all types if omitted)

    Returns OXR-compatible format: { base, date, rates: {...} }
    """
    # Parse date
    if date:
        try:
            datetime.strptime(date, "%Y-%m-%d")
            date_str = date
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
    else:
        # Use None to let the backend determine the date from OXR's timestamp
        # We'll get the actual date from the database after fetching
        date_str = None

    # Parse symbols
    symbol_list = None
    if symbols:
        symbol_list = [s.strip().upper() for s in symbols.split(",")]

    # Validate base currency
    base = base.upper()

    # Get rates
    try:
        # If no date specified, use the most recent date we have
        if date_str is None:
            date_str = db.get_latest_rate_date()
            # If we don't have any rates yet, fetch latest
            if not date_str:
                await rate_service.ensure_rates_available(None)
                date_str = db.get_latest_rate_date()
                if not date_str:
                    raise HTTPException(status_code=500, detail="No rates available")

        rates = await rate_service.get_rates(base, symbol_list, date_str, rate_type)

        if not rates:
            # Try to ensure rates are available
            await rate_service.ensure_rates_available(date_str)
            rates = await rate_service.get_rates(base, symbol_list, date_str, rate_type)

        return RatesResponse(
            base=base,
            date=date_str,
            rates=rates
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch rates: {str(e)}")


@app.on_event("startup")
async def startup_event():
    """Initialize database and start background scheduler on startup"""
    print("Starting Exchange Rate API...")
    print(f"Database: {db.get_db_path()}")

    # Start background scheduler (includes startup fetch)
    bg_scheduler.start_scheduler()


@app.on_event("shutdown")
async def shutdown_event():
    """Stop background scheduler on shutdown"""
    print("Shutting down Exchange Rate API...")
    bg_scheduler.stop_scheduler()


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    host = os.getenv("HOST", "127.0.0.1")
    uvicorn.run(app, host=host, port=port)
