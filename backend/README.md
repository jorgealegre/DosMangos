# Exchange Rate API

FastAPI backend for currency exchange rates with OpenExchangeRates API integration and dolarhoy.com web scraping for ARS rates.

## Setup

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your OpenExchangeRates API key

# Run locally
uvicorn app.main:app --reload
```

## API Documentation

Visit `http://localhost:8000/docs` for interactive Swagger UI documentation.

## Endpoints

- `GET /` - Health check
- `GET /currencies` - List all supported currencies
- `GET /rates?base=USD&symbols=EUR,ARS&date=2024-01-01&rate_type=blue` - Get exchange rates

## Deployment

See `exchange-rate-api.service` for systemd service configuration and `nginx-site.conf` for nginx reverse proxy setup.
