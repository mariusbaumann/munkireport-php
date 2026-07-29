#!/bin/bash

# Remove mdm_status collector (the wrapper as well as the legacy Python version)
rm -f "${MUNKIPATH}preflight.d/mdm_status"
rm -f "${MUNKIPATH}preflight.d/mdm_status.py"

# Remove cache file
rm -f "${CACHEPATH}mdm_status.plist"
