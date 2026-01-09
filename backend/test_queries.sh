#!/bin/bash

# Test script for Exchange Rate API
# Make sure the server is running: uvicorn app.main:app --reload

BASE_URL="http://127.0.0.1:8000"

echo "=================================="
echo "Exchange Rate API Test Queries"
echo "=================================="
echo ""

echo "1. Health Check"
echo "----------------"
curl -s "$BASE_URL/" | jq '.'
echo ""

echo "2. Get All Currencies"
echo "---------------------"
curl -s "$BASE_URL/currencies" | jq '. | to_entries | .[0:5] | from_entries'
echo "... (173 total currencies)"
echo ""

echo "3. Latest Rates (USD base, showing first 5)"
echo "--------------------------------------------"
curl -s "$BASE_URL/rates?base=USD" | jq '{base, date, rates: (.rates | to_entries | .[0:5] | from_entries)}'
echo ""

echo "4. Specific Currencies (USD → EUR, ARS, GBP)"
echo "---------------------------------------------"
curl -s "$BASE_URL/rates?base=USD&symbols=EUR,ARS,GBP" | jq '.'
echo ""

echo "5. Cross-Currency with Interpolation (ARS → EUR, GBP)"
echo "------------------------------------------------------"
curl -s "$BASE_URL/rates?base=ARS&symbols=EUR,GBP,USD" | jq '.'
echo ""

echo "6. Historical Rates (2024-01-01)"
echo "---------------------------------"
curl -s "$BASE_URL/rates?base=USD&symbols=EUR,ARS&date=2024-01-01" | jq '.'
echo ""

echo "7. EUR to Multiple Currencies"
echo "------------------------------"
curl -s "$BASE_URL/rates?base=EUR&symbols=USD,GBP,JPY,ARS" | jq '.'
echo ""

echo "=================================="
echo "All tests completed!"
echo "=================================="
echo ""
echo "API Documentation: $BASE_URL/docs"
