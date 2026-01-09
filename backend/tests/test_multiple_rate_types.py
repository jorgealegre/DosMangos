import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from app import database as db
from app import rate_service


@pytest.mark.asyncio
async def test_multiple_rate_types_usd_to_ars():
    """Test that USD→ARS returns all available rate types"""
    db.init_database()

    # Use a far future date that won't be auto-fetched
    test_date = "2028-06-15"

    # Insert multiple rate types for USD→ARS
    db.insert_rate("USD", "ARS", 1463.28, "official", test_date, "openexchangerates", "2024-01-08T00:00:00")
    db.insert_rate("USD", "ARS", 1510.00, "blue", test_date, "test", "2024-01-08T00:00:00")
    db.insert_rate("USD", "ARS", 1496.60, "ccl", test_date, "test", "2024-01-08T00:00:00")

    # Get rates
    rates = await rate_service.get_rates("USD", ["ARS"], test_date)

    print(f"USD→ARS rates: {rates}")

    assert "ARS" in rates
    assert "official" in rates["ARS"]
    assert "blue" in rates["ARS"]
    assert "ccl" in rates["ARS"]
    assert rates["ARS"]["official"] == 1463.28
    assert rates["ARS"]["blue"] == 1510.00
    assert rates["ARS"]["ccl"] == 1496.60
    print("✓ USD→ARS returns all 3 rate types")


@pytest.mark.asyncio
async def test_multiple_rate_types_ars_to_usd_inverse():
    """Test that ARS→USD returns all inverted rate types"""
    db.init_database()

    # Use a far future date that won't be auto-fetched
    test_date = "2028-06-15"

    # Insert multiple rate types for USD→ARS
    db.insert_rate("USD", "ARS", 1463.28, "official", test_date, "openexchangerates", "2024-01-08T00:00:00")
    db.insert_rate("USD", "ARS", 1510.00, "blue", test_date, "test", "2024-01-08T00:00:00")
    db.insert_rate("USD", "ARS", 1496.60, "ccl", test_date, "test", "2024-01-08T00:00:00")

    # Get inverse rates (ARS→USD)
    rates = await rate_service.get_rates("ARS", ["USD"], test_date)

    print(f"ARS→USD rates: {rates}")

    assert "USD" in rates
    assert "official" in rates["USD"]
    assert "blue" in rates["USD"]
    assert "ccl" in rates["USD"]

    # Verify inverse calculation
    assert abs(rates["USD"]["official"] - (1.0 / 1463.28)) < 0.0001
    assert abs(rates["USD"]["blue"] - (1.0 / 1510.00)) < 0.0001
    assert abs(rates["USD"]["ccl"] - (1.0 / 1496.60)) < 0.0001
    print("✓ ARS→USD returns all 3 inverted rate types")


@pytest.mark.asyncio
async def test_specific_rate_type():
    """Test that requesting a specific rate type only returns that type"""
    db.init_database()

    # Use a far future date that won't be auto-fetched
    test_date = "2028-06-15"

    # Insert multiple rate types
    db.insert_rate("USD", "ARS", 1463.28, "official", test_date, "openexchangerates", "2024-01-08T00:00:00")
    db.insert_rate("USD", "ARS", 1510.00, "blue", test_date, "test", "2024-01-08T00:00:00")

    # Get only blue rates
    rates = await rate_service.get_rates("USD", ["ARS"], test_date, rate_type="blue")

    print(f"USD→ARS blue rate: {rates}")

    assert "ARS" in rates
    assert "blue" in rates["ARS"]
    assert "official" not in rates["ARS"]  # Should not include official
    assert rates["ARS"]["blue"] == 1510.00
    print("✓ Requesting specific rate type works")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
