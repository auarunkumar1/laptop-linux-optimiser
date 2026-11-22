#!/usr/bin/env bash
# Compatibility runner for laptop-linux-optimiser test suite
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test_laptop_linux_optimiser.sh" "$@"
