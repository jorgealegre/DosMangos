import httpx
from datetime import datetime
from typing import Optional
import os
from dotenv import load_dotenv
from . import database as db

# Load environment variables
load_dotenv()

OXR_API_KEY = os.getenv("OPENEXCHANGERATES_API_KEY", "")
OXR_BASE_URL = "https://openexchangerates.org/api"


class OpenExchangeRatesError(Exception):
    """Exception raised for OXR API errors"""
    pass


async def fetch_latest_rates() -> dict[str, float]:
    """
    Fetch latest rates from OpenExchangeRates API (USD base).
    Returns dict of {currency_code: rate}
    """
    if not OXR_API_KEY:
        raise OpenExchangeRatesError("OPENEXCHANGERATES_API_KEY not set")

    url = f"{OXR_BASE_URL}/latest.json"
    params = {"app_id": OXR_API_KEY}

    async with httpx.AsyncClient() as client:
        response = await client.get(url, params=params, timeout=10.0)

        if response.status_code != 200:
            raise OpenExchangeRatesError(
                f"OXR API returned {response.status_code}: {response.text}"
            )

        data = response.json()
        return data.get("rates", {})


async def fetch_historical_rates(date_str: str) -> dict[str, float]:
    """
    Fetch historical rates from OpenExchangeRates API for specific date (USD base).
    date_str format: YYYY-MM-DD
    Returns dict of {currency_code: rate}
    """
    if not OXR_API_KEY:
        raise OpenExchangeRatesError("OPENEXCHANGERATES_API_KEY not set")

    url = f"{OXR_BASE_URL}/historical/{date_str}.json"
    params = {"app_id": OXR_API_KEY}

    async with httpx.AsyncClient() as client:
        response = await client.get(url, params=params, timeout=10.0)

        if response.status_code != 200:
            raise OpenExchangeRatesError(
                f"OXR API returned {response.status_code}: {response.text}"
            )

        data = response.json()
        return data.get("rates", {})


async def fetch_currencies() -> dict[str, str]:
    """
    Fetch list of all currencies from OpenExchangeRates API.
    Returns dict of {currency_code: currency_name}
    """
    url = f"{OXR_BASE_URL}/currencies.json"

    async with httpx.AsyncClient() as client:
        response = await client.get(url, timeout=10.0)

        if response.status_code != 200:
            raise OpenExchangeRatesError(
                f"OXR API returned {response.status_code}: {response.text}"
            )

        return response.json()


async def fetch_and_store_rates(date_str: Optional[str] = None) -> int:
    """
    Fetch rates from OXR and store them in database.
    If date_str is None, fetches latest rates.
    Always uses OXR's timestamp field to determine the date.
    Returns number of rates stored.
    """
    if not OXR_API_KEY:
        raise OpenExchangeRatesError("OPENEXCHANGERATES_API_KEY not set")

    # Choose endpoint based on whether date is specified
    if date_str:
        url = f"{OXR_BASE_URL}/historical/{date_str}.json"
    else:
        url = f"{OXR_BASE_URL}/latest.json"

    params = {"app_id": OXR_API_KEY}

    async with httpx.AsyncClient() as client:
        response = await client.get(url, params=params, timeout=10.0)

        if response.status_code != 200:
            raise OpenExchangeRatesError(
                f"OXR API returned {response.status_code}: {response.text}"
            )

        data = response.json()
        rates = data.get("rates", {})

        # ALWAYS use OXR's timestamp to determine the date (converts Unix timestamp to date)
        timestamp = data.get("timestamp")
        if timestamp:
            target_date = datetime.fromtimestamp(timestamp).date().isoformat()
        else:
            # This shouldn't happen with OXR, but fallback to requested date
            target_date = date_str or datetime.utcnow().date().isoformat()

    fetched_at = datetime.utcnow().isoformat()
    count = 0

    # Store all USD → X rates
    for currency, rate in rates.items():
        if currency == "USD":
            continue  # Skip USD to USD

        db.insert_rate(
            from_currency="USD",
            to_currency=currency,
            rate=rate,
            rate_type="official",
            date_str=target_date,
            source="openexchangerates",
            fetched_at=fetched_at
        )
        count += 1

    return count
