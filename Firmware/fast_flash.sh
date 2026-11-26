#!/usr/bin/env bash

set -e

echo "[1/3] Building project..."
pio run

echo
echo "[2/3] Uploading firmware to ESP32..."
pio run --target upload
pio run --target uploadfs
echo
echo "[3/3] Opening serial monitor..."
echo "To exit the serial monitor, press: Ctrl + ]"
pio device monitor
