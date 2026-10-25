#!/bin/sh
# Builds and runs the firmware logic tests on a computer (needs g++ with C++17). No ESP32 required.
set -e
cd "$(dirname "$0")"
INC=../arduino/lifetwin_band
echo "== firmware logic: steps, posture, minutes, timers, non-wear"
g++ -std=c++17 -O1 -Wall -I$INC host_test.cpp -o /tmp/lt_host_test && /tmp/lt_host_test | tail -3
echo "== day summary: dates, JSON, merge after restart, one record per minute"
g++ -std=c++17 -O1 -Wall -I$INC day_unit_test.cpp -o /tmp/lt_day_test && /tmp/lt_day_test | tail -3
