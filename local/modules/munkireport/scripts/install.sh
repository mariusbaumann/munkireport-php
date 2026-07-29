#!/bin/bash

# Overrides vendor/munkireport/munkireport/scripts/install.sh
#
# The vendor version downloads munkireport.py and depends on the MacAdmins
# Python framework. This one drops a wrapper that calls the built-in collector
# of munkireport-runner instead, so the client needs no Python at all.

# Remove the Python collector and its cache from previous installations
rm -f "${MUNKIPATH}postflight.d/munkireport.py"
rm -f "${MUNKIPATH}preflight.d/munkireport.py"
rm -f "${MUNKIPATH}preflight.d/cache/munkireport.plist"

# $0 is <munkipath>/scripts/munkireport, so ../munkireport-runner resolves
# regardless of where MunkiReport was installed
cat > "${MUNKIPATH}postflight.d/munkireport" <<'MRWRAPPER'
#!/bin/bash
exec "$(/usr/bin/dirname "$0")/../munkireport-runner" --collect munkireport
MRWRAPPER

if [ $? = 0 ]; then
	# Make executable
	chmod a+x "${MUNKIPATH}postflight.d/munkireport"

	# Set preference to include this file in the postflight check
	setreportpref "munkireport" "${POSTFLIGHT_CACHEPATH}munkireport.plist"

else
	echo "Failed to install the munkireport collector!"
	rm -f "${MUNKIPATH}postflight.d/munkireport"

	# Signal that we had an error
	ERR=1
fi
