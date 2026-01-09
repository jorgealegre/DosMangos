import pytest
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app import database as db
from app import oxr_client
from app import rate_service


@pytest.mark.asyncio
async def test_database_initialization():
    """Test database initialization"""
    db.init_database()
    db_path = db.get_db_path()
    assert db_path.exists()
    print(f"✓ Database initialized at {db_path}")


@pytest.mark.asyncio
async def test_insert_and_get_rate():
    """Test inserting and retrieving a rate"""
    db.init_database()

    # Insert a test rate
    db.insert_rate(
        from_currency="USD",
        to_currency="EUR",
        rate=0.85,
        rate_type="official",
        date_str="2024-01-08",
        source="test",
        fetched_at="2024-01-08T00:00:00"
    )

    # Retrieve it
    rate = db.get_rate("USD", "EUR", "2024-01-08", "official")
    assert rate == 0.85
    print(f"✓ Inserted and retrieved rate: USD→EUR = {rate}")


@pytest.mark.asyncio
async def test_rate_priority():
    """Test rate type priority (official > blue)"""
    db.init_database()

    # Insert official rate
    db.insert_rate(
        from_currency="ARS",
        to_currency="USD",
        rate=0.00067,
        rate_type="official",
        date_str="2024-01-08",
        source="test",
        fetched_at="2024-01-08T00:00:00"
    )

    # Insert blue rate
    db.insert_rate(
        from_currency="ARS",
        to_currency="USD",
        rate=0.00066,
        rate_type="blue",
        date_str="2024-01-08",
        source="test",
        fetched_at="2024-01-08T00:00:00"
    )

    # Get rate without specifying type (should return official)
    rate = db.get_rate("ARS", "USD", "2024-01-08")
    assert rate == 0.00067
    print(f"✓ Rate priority works: blue rate returned ({rate})")

    # Get specific rate type (official)
    rate_official = db.get_rate("ARS", "USD", "2024-01-08", "official")
    assert rate_official == 0.00067
    print(f"✓ Can retrieve specific rate type: official ({rate_official})")


@pytest.mark.asyncio
async def test_fetch_oxr_rates():
    """Test fetching rates from OpenExchangeRates API"""
    try:
        count = await oxr_client.fetch_and_store_rates()
        assert count > 0
        print(f"✓ Fetched {count} rates from OpenExchangeRates")

        # Verify rates were stored
        rate = db.get_rate("USD", "EUR", "2024-01-08")
        if rate:
            print(f"✓ Sample rate USD→EUR: {rate}")
    except oxr_client.OpenExchangeRatesError as e:
        print(f"✗ OpenExchangeRates API error: {e}")
        pytest.skip("OXR API not available")


@pytest.mark.asyncio
async def test_fetch_currencies():
    """Test fetching currency list from OpenExchangeRates"""
    try:
        currencies = await oxr_client.fetch_currencies()
        assert len(currencies) > 0
        assert "USD" in currencies
        assert "EUR" in currencies
        print(f"✓ Fetched {len(currencies)} currencies")
        print(f"  Sample: USD = {currencies.get('USD')}")
    except oxr_client.OpenExchangeRatesError as e:
        print(f"✗ OpenExchangeRates API error: {e}")
        pytest.skip("OXR API not available")


@pytest.mark.asyncio
async def test_interpolation():
    """Test cross-currency interpolation"""
    db.init_database()

    # Insert USD → EUR and USD → GBP rates
    db.insert_rate("USD", "EUR", 0.85, "official", "2024-01-08", "test", "2024-01-08T00:00:00")
    db.insert_rate("USD", "GBP", 0.75, "official", "2024-01-08", "test", "2024-01-08T00:00:00")

    # Get EUR → GBP rate (should interpolate)
    rates = await rate_service.get_rates("EUR", ["GBP"], "2024-01-08")

    # EUR → GBP = (EUR → USD) * (USD → GBP) = (1/0.85) * 0.75
    expected = (1.0 / 0.85) * 0.75
    assert "GBP" in rates
    assert "official" in rates["GBP"]
    assert abs(rates["GBP"]["official"] - expected) < 0.0001
    print(f"✓ Interpolation works: EUR→GBP official = {rates['GBP']['official']:.4f} (expected ~{expected:.4f})")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
