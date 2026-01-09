import sqlite3
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from typing import Optional
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

DATABASE_PATH = os.getenv("DATABASE_PATH", "data/exchange_rates.db")


def get_db_path() -> Path:
    """Get absolute path to database file"""
    base_dir = Path(__file__).parent.parent
    db_path = base_dir / DATABASE_PATH
    db_path.parent.mkdir(parents=True, exist_ok=True)
    return db_path


@contextmanager
def get_db():
    """Context manager for database connections"""
    conn = sqlite3.connect(get_db_path())
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_database():
    """Initialize database schema"""
    with get_db() as conn:
        cursor = conn.cursor()

        # Create exchange_rates table with STRICT mode for type safety
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS exchange_rates (
                id TEXT PRIMARY KEY,
                from_currency TEXT NOT NULL,
                to_currency TEXT NOT NULL,
                rate REAL NOT NULL,
                rate_type TEXT NOT NULL DEFAULT 'official',
                date TEXT NOT NULL,
                source TEXT NOT NULL,
                fetched_at TEXT NOT NULL,
                UNIQUE(from_currency, to_currency, date, rate_type)
            ) STRICT
        """)

        # Create bidirectional view with priority: stored rates > computed inverses
        cursor.execute("""
            CREATE VIEW IF NOT EXISTS exchange_rates_bidirectional AS
            -- Direct rates (highest priority)
            SELECT
                from_currency,
                to_currency,
                rate,
                rate_type,
                date,
                source,
                'direct' as rate_source
            FROM exchange_rates
            WHERE rate > 0

            UNION ALL

            -- Inverse rates ONLY where direct rate doesn't exist
            SELECT
                e1.to_currency as from_currency,
                e1.from_currency as to_currency,
                1.0 / e1.rate as rate,
                e1.rate_type,
                e1.date,
                e1.source || ' (computed inverse)' as source,
                'inverse' as rate_source
            FROM exchange_rates e1
            WHERE e1.rate > 0
              AND NOT EXISTS (
                -- Don't create inverse if direct rate already exists
                SELECT 1
                FROM exchange_rates e2
                WHERE e2.from_currency = e1.to_currency
                  AND e2.to_currency = e1.from_currency
                  AND e2.rate_type = e1.rate_type
                  AND e2.date = e1.date
              )
        """)

        # Create index for fast lookups
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_rates_lookup
            ON exchange_rates(from_currency, to_currency, date, rate_type)
        """)

        conn.commit()


def insert_rate(
    from_currency: str,
    to_currency: str,
    rate: float,
    rate_type: str,
    date_str: str,
    source: str,
    fetched_at: str
) -> None:
    """Insert or replace a rate in the database"""
    import uuid

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO exchange_rates
            (id, from_currency, to_currency, rate, rate_type, date, source, fetched_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            str(uuid.uuid4()),
            from_currency,
            to_currency,
            rate,
            rate_type,
            date_str,
            source,
            fetched_at
        ))
        conn.commit()


def get_rate(
    from_currency: str,
    to_currency: str,
    date_str: str,
    rate_type: Optional[str] = None
) -> Optional[float]:
    """
    Get rate for a currency pair on a specific date.
    If rate_type is specified, returns that exact type.
    Otherwise, uses priority: blue > official
    """
    with get_db() as conn:
        cursor = conn.cursor()

        if rate_type:
            # Query for specific rate type
            cursor.execute("""
                SELECT rate FROM exchange_rates
                WHERE from_currency = ? AND to_currency = ?
                  AND date = ? AND rate_type = ?
                LIMIT 1
            """, (from_currency, to_currency, date_str, rate_type))
        else:
            # Query with priority: official > blue > others
            cursor.execute("""
                SELECT rate FROM exchange_rates
                WHERE from_currency = ? AND to_currency = ? AND date = ?
                ORDER BY
                    CASE rate_type
                        WHEN 'official' THEN 1
                        WHEN 'blue' THEN 2
                        WHEN 'mep' THEN 3
                        WHEN 'ccl' THEN 4
                        ELSE 5
                    END
                LIMIT 1
            """, (from_currency, to_currency, date_str))

        row = cursor.fetchone()
        return row['rate'] if row else None


def get_all_rates_for_base(
    base_currency: str,
    date_str: str,
    rate_type: Optional[str] = None
) -> dict[str, dict[str, float]]:
    """
    Get all rates from base currency to other currencies for a specific date.
    Uses bidirectional view which includes both direct and computed inverse rates.
    Returns dict of {currency_code: {rate_type: rate}}
    """
    with get_db() as conn:
        cursor = conn.cursor()

        if rate_type:
            # Only get specific rate type
            cursor.execute("""
                SELECT to_currency, rate, rate_type FROM exchange_rates_bidirectional
                WHERE from_currency = ? AND date = ? AND rate_type = ?
            """, (base_currency, date_str, rate_type))
        else:
            # Get ALL rate types for each currency
            cursor.execute("""
                SELECT to_currency, rate_type, rate FROM exchange_rates_bidirectional
                WHERE from_currency = ? AND date = ?
                ORDER BY to_currency, rate_type
            """, (base_currency, date_str))

        rows = cursor.fetchall()

        # Group by currency, then by rate_type
        result = {}
        for row in rows:
            currency = row['to_currency']
            if currency not in result:
                result[currency] = {}
            result[currency][row['rate_type']] = row['rate']

        return result


def get_latest_rate_date() -> Optional[str]:
    """
    Get the most recent date for which we have exchange rates.
    Returns date in YYYY-MM-DD format.
    """
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT date
            FROM exchange_rates
            ORDER BY date DESC
            LIMIT 1
        """)
        row = cursor.fetchone()
        return row['date'] if row else None


if __name__ == "__main__":
    # Initialize database when run as script
    init_database()
    print(f"Database initialized at {get_db_path()}")
