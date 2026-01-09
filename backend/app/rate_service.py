from typing import Optional
import logging
from . import database as db
from . import oxr_client
from . import dolar_scraper

logger = logging.getLogger(__name__)


async def get_rates(
    base: str,
    symbols: Optional[list[str]],
    date_str: str,
    rate_type: Optional[str] = None
) -> dict[str, dict[str, float]]:
    """
    Get exchange rates for base currency to target currencies.
    Uses bidirectional view which handles both direct and inverse rates.
    Performs interpolation through USD for cross-currency rates.

    Args:
        base: Base currency code (e.g., 'USD')
        symbols: List of target currency codes, or None for all
        date_str: Date in YYYY-MM-DD format
        rate_type: Specific rate type ('official', 'blue', etc.) or None for all types

    Returns:
        dict of {currency_code: {rate_type: rate}}
    """
    logger.info(f"get_rates: base={base}, symbols={symbols}, date={date_str}, rate_type={rate_type}")

    # RULE: For USD base, we need official rates from OXR for this date
    # Check if we have official rates (not blue/mep/ccl) for USD base
    if base == "USD":
        official_rates = db.get_all_rates_for_base(base, date_str, "official")

        if not official_rates:
            logger.info("No official rates found for USD, fetching from OXR...")
            try:
                await oxr_client.fetch_and_store_rates(date_str)
            except Exception as e:
                logger.warning(f"OXR fetch failed: {e}")

    # RULE: For ARS rates, check if we need blue rates
    # This is separate from official rates - blue rates are supplemental
    if base in ("USD", "ARS") or (symbols and any(s in ("USD", "ARS") for s in symbols)):
        ars_in_request = not symbols or "ARS" in symbols or base == "ARS"

        if ars_in_request:
            # Check if we have blue rates for ARS/USD
            check_base = base if base in ("USD", "ARS") else "USD"
            existing_blue = db.get_all_rates_for_base(check_base, date_str, "blue")

            # Look for ARS specifically in blue rates
            has_ars_blue = existing_blue and "ARS" in existing_blue

            if not has_ars_blue:
                logger.info("No blue ARS rates found, fetching from ambito.com...")
                try:
                    await dolar_scraper.scrape_and_store_ars_rates(date_str)
                except Exception as e:
                    logger.warning(f"Ambito scrape failed: {e}")

    # Now get the rates filtered by requested type
    all_base_rates = db.get_all_rates_for_base(base, date_str, rate_type)
    logger.info(f"Final: {len(all_base_rates)} currencies available")

    # Filter to requested symbols if specified
    if symbols:
        rates = {
            symbol: all_base_rates[symbol]
            for symbol in symbols
            if symbol in all_base_rates
        }
    else:
        rates = all_base_rates

    # Handle interpolation for missing currencies
    # (Only if we have some rates but missing specific symbols)
    if symbols and len(rates) < len(symbols):
        missing_symbols = [s for s in symbols if s not in rates]
        logger.info(f"Interpolating missing symbols: {missing_symbols}")
        interpolated = await _interpolate_via_usd(base, missing_symbols, date_str, rate_type)
        rates.update(interpolated)

    logger.info(f"Returning rates for {len(rates)} currencies")
    return rates


async def _interpolate_via_usd(
    base: str,
    targets: list[str],
    date_str: str,
    rate_type: Optional[str] = None
) -> dict[str, dict[str, float]]:
    """
    Interpolate rates for missing currencies via USD.
    Formula: base → target = (base → USD) × (USD → target)

    Returns dict of {currency_code: {rate_type: rate}}
    """
    rates = {}

    # Get base → USD rates (VIEW handles inverse automatically)
    base_to_usd_rates = db.get_all_rates_for_base(base, date_str, rate_type)
    if "USD" not in base_to_usd_rates:
        return rates  # Can't interpolate without base → USD

    # Get USD → all rates
    usd_rates = db.get_all_rates_for_base("USD", date_str, rate_type)
    if not usd_rates:
        # Try fetching
        try:
            await oxr_client.fetch_and_store_rates(date_str)
            usd_rates = db.get_all_rates_for_base("USD", date_str, rate_type)
        except Exception:
            pass

    if not usd_rates:
        return rates

    # Interpolate for each target
    for target in targets:
        if target not in usd_rates:
            continue

        # Interpolate for each matching rate type
        interpolated = {}
        for rt in base_to_usd_rates["USD"]:
            if rt in usd_rates[target]:
                interpolated[rt] = base_to_usd_rates["USD"][rt] * usd_rates[target][rt]

        if interpolated:
            rates[target] = interpolated

    return rates


async def ensure_rates_available(date_str: str) -> None:
    """
    Ensure rates are available for the given date.
    Fetches from OXR if not in cache.
    """
    # Check if we have any rates for this date
    usd_rates = db.get_all_rates_for_base("USD", date_str)

    if not usd_rates:
        # Fetch from OXR
        try:
            await oxr_client.fetch_and_store_rates(date_str)
        except Exception as e:
            # Log error but don't fail - we might have other rates
            print(f"Failed to fetch rates for {date_str}: {e}")
