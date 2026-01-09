from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import datetime
import asyncio

from . import oxr_client
from . import dolar_scraper


# Global scheduler instance
scheduler = AsyncIOScheduler()


async def fetch_daily_rates():
    """
    Background job to fetch rates daily.
    Runs at 00:00 UTC every day.
    """
    print(f"[{datetime.utcnow()}] Starting daily rate fetch...")

    # Fetch OpenExchangeRates data
    try:
        count = await oxr_client.fetch_and_store_rates()
        print(f"✓ Fetched and stored {count} rates from OpenExchangeRates")
    except Exception as e:
        print(f"✗ Failed to fetch OpenExchangeRates data: {e}")

    # Scrape dolarhoy.com for ARS rates
    try:
        count = await dolar_scraper.scrape_and_store_ars_rates()
        print(f"✓ Scraped and stored {count} ARS rates from dolarhoy.com")
    except Exception as e:
        print(f"✗ Failed to scrape dolarhoy.com: {e}")

    print(f"[{datetime.utcnow()}] Daily rate fetch completed")


def start_scheduler():
    """
    Start the background scheduler.
    Schedules daily rate fetching at 00:00 UTC.
    """
    # Schedule daily job at 00:00 UTC
    scheduler.add_job(
        fetch_daily_rates,
        trigger=CronTrigger(hour=0, minute=0, timezone="UTC"),
        id="daily_rate_fetch",
        name="Fetch daily exchange rates",
        replace_existing=True
    )

    # Also run immediately on startup (optional)
    scheduler.add_job(
        fetch_daily_rates,
        trigger="date",
        id="startup_fetch",
        name="Fetch rates on startup",
        replace_existing=True
    )

    scheduler.start()
    print("Background scheduler started")


def stop_scheduler():
    """Stop the background scheduler"""
    scheduler.shutdown()
    print("Background scheduler stopped")


# For testing
if __name__ == "__main__":
    async def test():
        await fetch_daily_rates()

    asyncio.run(test())
