#!/bin/bash

# Remove softwareupdate collector (the wrapper as well as the legacy Python version)
rm -f "${MUNKIPATH}preflight.d/softwareupdate"
rm -f "${MUNKIPATH}preflight.d/softwareupdate"

# Remove cache file
rm -f "${CACHEPATH}softwareupdate.plist"
