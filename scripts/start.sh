#!/usr/bin/env bash
set -euo pipefail

# Start both SPA and API for local development
# Usage: ./scripts/start.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SPA_DIR="$ROOT_DIR/sample-app/spa"
API_DIR="$ROOT_DIR/sample-app/api"

cleanup() {
    echo ""
    echo "Shutting down..."
    kill "$API_PID" 2>/dev/null || true
    kill "$SPA_PID" 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# --- Install SPA dependencies if needed ---
if [ ! -d "$SPA_DIR/node_modules" ]; then
    echo "Installing SPA dependencies..."
    (cd "$SPA_DIR" && npm install)
fi

# --- Start API (Spring Boot with dev profile) ---
echo "Starting API on http://localhost:8080 ..."
(cd "$API_DIR" && mvn spring-boot:run -Dspring-boot.run.profiles=dev -q) &
API_PID=$!

# --- Start SPA (Angular dev server with proxy) ---
echo "Starting SPA on http://localhost:4200 ..."
(cd "$SPA_DIR" && npx ng serve --proxy-config proxy.conf.json --open) &
SPA_PID=$!

echo ""
echo "  SPA: http://localhost:4200"
echo "  API: http://localhost:8080"
echo ""
echo "Press Ctrl+C to stop both."

wait
