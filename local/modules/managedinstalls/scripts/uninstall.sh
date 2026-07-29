#!/bin/bash

# Remove managedinstalls collector (both the wrapper and the legacy Python script)
rm -f "${MUNKIPATH}postflight.d/managedinstalls"
rm -f "${MUNKIPATH}postflight.d/managedinstalls.py"

# Remove managedinstalls.plist file
rm -f "${CACHEPATH}managedinstalls.plist"
