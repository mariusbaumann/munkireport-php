#!/bin/bash

# Remove munkireport collector (both the wrapper and the legacy Python script)
rm -f "${MUNKIPATH}postflight.d/munkireport"
rm -f "${MUNKIPATH}postflight.d/munkireport.py"
rm -f "${MUNKIPATH}preflight.d/munkireport.py"

# Remove munkireport.plist file
rm -f "${MUNKIPATH}postflight.d/cache/munkireport.plist"
rm -f "${MUNKIPATH}preflight.d/cache/munkireport.plist"
