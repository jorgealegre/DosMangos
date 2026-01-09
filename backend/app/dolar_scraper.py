"""
Scraper for alternative ARS exchange rates from ambito.com
"""
import httpx
from datetime import datetime, timedelta
from typing import Optional
from zoneinfo import ZoneInfo
from . import database as db


AMBITO_API_URL = "https://mercados.ambito.com/dolar/informal/historico-general"
ARGENTINA_TZ = ZoneInfo("America/Argentina/Buenos_Aires")


class DolarScraperError(Exception):
    """Raised when scraping fails"""
    pass


def parse_ambito_date(date_str: str) -> str:
    """Convert DD/MM/YYYY to YYYY-MM-DD"""
    day, month, year = date_str.split("/")
    return f"{year}-{month}-{day}"


def parse_rate_value(text: str) -> Optional[float]:
    """Parse rate value from text like '1.490,50' (Argentine format)"""
    if not text:
        return None
    cleaned = text.replace(".", "").replace(",", ".").strip()
    try:
        return float(cleaned)
    except (ValueError, AttributeError):
        return None


async def fetch_historical_blue_rates(from_date: str, to_date: str) -> dict[str, tuple[float, float]]:
    """
    Fetch historical blue dollar rates from ambito.com API.

    Args:
        from_date: Start date in YYYY-MM-DD format
        to_date: End date in YYYY-MM-DD format

    Returns:
        Dict mapping YYYY-MM-DD dates to (compra, venta) tuples
    """
    url = f"{AMBITO_API_URL}/{from_date}/{to_date}"

    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    }

    async with httpx.AsyncClient(follow_redirects=True) as client:
        try:
            response = await client.get(url, headers=headers, timeout=10.0)
            if response.status_code != 200:
                raise DolarScraperError(f"HTTP {response.status_code}")

            data = response.json()
            if not isinstance(data, list) or len(data) < 2:
                raise DolarScraperError("Invalid API response format")

            # First row is headers, skip it
            rates = {}
            for row in data[1:]:
                if len(row) != 3:
                    continue

                date_str, compra_str, venta_str = row
                compra = parse_rate_value(compra_str)
                venta = parse_rate_value(venta_str)

                if compra and venta:
                    normalized_date = parse_ambito_date(date_str)
                    rates[normalized_date] = (compra, venta)

            return rates

        except httpx.RequestError as e:
            raise DolarScraperError(f"Request failed: {e}")
        except Exception as e:
            raise DolarScraperError(f"Failed to parse: {e}")


async def scrape_and_store_ars_rates(date_str: Optional[str] = None) -> int:
    """
    Scrape blue ARS rates from ambito.com and store in database.
    Fetches a 30-day range around the target date to populate cache.
    Also copies Friday rates to Saturday and Sunday (market closed on weekends).

    Args:
        date_str: Target date in YYYY-MM-DD format (defaults to today in Argentina timezone)

    Returns:
        Number of rates stored
    """
    if date_str:
        target_date = datetime.fromisoformat(date_str)
    else:
        # Use Argentina timezone for "today" since ambito.com operates in Argentina time
        target_date = datetime.now(ARGENTINA_TZ).replace(tzinfo=None)

    # Fetch 15 days before and after target date for good cache coverage
    from_date = (target_date - timedelta(days=15)).strftime("%Y-%m-%d")
    to_date = (target_date + timedelta(days=15)).strftime("%Y-%m-%d")

    rates_data = await fetch_historical_blue_rates(from_date, to_date)

    if not rates_data:
        raise DolarScraperError("No rates found from ambito.com API")

    fetched_at = datetime.utcnow().isoformat()
    count = 0

    # First, store all the rates we fetched
    for date, (compra, venta) in rates_data.items():
        # Store USD -> ARS (compra: how many ARS to BUY 1 USD)
        db.insert_rate(
            from_currency="USD",
            to_currency="ARS",
            rate=compra,
            rate_type="blue",
            date_str=date,
            source="ambito",
            fetched_at=fetched_at
        )
        count += 1

        # Store ARS -> USD (1 / venta: how many USD to BUY 1 ARS)
        ars_to_usd_rate = 1.0 / venta
        db.insert_rate(
            from_currency="ARS",
            to_currency="USD",
            rate=ars_to_usd_rate,
            rate_type="blue",
            date_str=date,
            source="ambito",
            fetched_at=fetched_at
        )
        count += 1

    # Now copy Friday rates to Saturday and Sunday
    # Markets are closed on weekends, so Friday rate applies
    for date_str, (compra, venta) in rates_data.items():
        date_obj = datetime.fromisoformat(date_str)

        # If this is a Friday (weekday() returns 4 for Friday)
        if date_obj.weekday() == 4:
            # Copy to Saturday
            saturday = (date_obj + timedelta(days=1)).strftime("%Y-%m-%d")
            db.insert_rate(
                from_currency="USD",
                to_currency="ARS",
                rate=compra,
                rate_type="blue",
                date_str=saturday,
                source="ambito (weekend)",
                fetched_at=fetched_at
            )
            count += 1

            ars_to_usd_rate = 1.0 / venta
            db.insert_rate(
                from_currency="ARS",
                to_currency="USD",
                rate=ars_to_usd_rate,
                rate_type="blue",
                date_str=saturday,
                source="ambito (weekend)",
                fetched_at=fetched_at
            )
            count += 1

            # Copy to Sunday
            sunday = (date_obj + timedelta(days=2)).strftime("%Y-%m-%d")
            db.insert_rate(
                from_currency="USD",
                to_currency="ARS",
                rate=compra,
                rate_type="blue",
                date_str=sunday,
                source="ambito (weekend)",
                fetched_at=fetched_at
            )
            count += 1

            db.insert_rate(
                from_currency="ARS",
                to_currency="USD",
                rate=ars_to_usd_rate,
                rate_type="blue",
                date_str=sunday,
                source="ambito (weekend)",
                fetched_at=fetched_at
            )
            count += 1

    return count
