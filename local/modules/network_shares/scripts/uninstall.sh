#!/bin/bash

# Remove network_shares collector (the wrapper as well as the legacy Python version)
rm -f "${MUNKIPATH}preflight.d/network_shares"
rm -f "${MUNKIPATH}preflight.d/network_shares.py"

# Remove cache file
rm -f "${CACHEPATH}network_shares.plist"
