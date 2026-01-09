import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from app import database as db
from app import rate_service


@pytest.mark.asyncio
async def test_ars_to_usd_inverse():
    """Test that ARS→USD works when we only have USD→ARS"""
    db.init_database()

    # Insert USD→ARS rate
    db.insert_rate("USD", "ARS", 1463.28213, "official", "2024-01-08", "test", "2024-01-08T00:00:00")

    # Try to get ARS→USD (inverse)
    rates = await rate_service.get_rates("ARS", ["USD"], "2024-01-08")

    assert "USD" in rates
    assert "official" in rates["USD"]
    expected = 1.0 / 1463.28213
    assert abs(rates["USD"]["official"] - expected) < 0.0001
    print(f"✓ ARS→USD inverse rate: {rates['USD']['official']:.8f} (expected ~{expected:.8f})")


@pytest.mark.asyncio
async def test_eur_to_usd_inverse():
    """Test that EUR→USD works when we only have USD→EUR"""
    db.init_database()

    # Insert USD→EUR rate
    db.insert_rate("USD", "EUR", 0.857621, "official", "2024-01-08", "test", "2024-01-08T00:00:00")

    # Try to get EUR→USD (inverse)
    rates = await rate_service.get_rates("EUR", ["USD"], "2024-01-08")

    assert "USD" in rates
    assert "official" in rates["USD"]
    expected = 1.0 / 0.857621
    assert abs(rates["USD"]["official"] - expected) < 0.0001
    print(f"✓ EUR→USD inverse rate: {rates['USD']['official']:.6f} (expected ~{expected:.6f})")


@pytest.mark.asyncio
async def test_priority_official_over_blue():
    """Test that official rate is returned by default over blue"""
    db.init_database()

    # Insert blue rate first
    db.insert_rate("ARS", "USD", 0.00066, "blue", "2024-01-08", "dolarhoy", "2024-01-08T00:00:00")

    # Insert official rate
    db.insert_rate("ARS", "USD", 0.00067, "official", "2024-01-08", "openexchangerates", "2024-01-08T00:00:00")

    # Get rate without specifying type (should return official)
    rate = db.get_rate("ARS", "USD", "2024-01-08")
    assert rate == 0.00067
    print(f"✓ Priority works: official rate returned ({rate})")

    # Can still get blue explicitly
    rate_blue = db.get_rate("ARS", "USD", "2024-01-08", "blue")
    assert rate_blue == 0.00066
    print(f"✓ Can retrieve specific rate type: blue ({rate_blue})")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
