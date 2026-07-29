#!/bin/bash

# Overrides vendor/munkireport/managedinstalls/scripts/install.sh
#
# The vendor version downloads managedinstalls.py and depends on the MacAdmins
# Python framework. This one drops a wrapper that calls the built-in collector
# of munkireport-runner instead, so the client needs no Python at all.

# Remove the Python collector from previous installations
rm -f "${MUNKIPATH}postflight.d/managedinstalls.py"

# $0 is <munkipath>/scripts/managedinstalls, so ../munkireport-runner resolves
# regardless of where MunkiReport was installed
cat > "${MUNKIPATH}postflight.d/managedinstalls" <<'MRWRAPPER'
#!/bin/bash
exec "$(/usr/bin/dirname "$0")/../munkireport-runner" --collect managedinstalls
MRWRAPPER

if [ $? = 0 ]; then
	# Make executable
	chmod a+x "${MUNKIPATH}postflight.d/managedinstalls"

	# Set preference to include this file in the postflight check
	setreportpref "managedinstalls" "${POSTFLIGHT_CACHEPATH}managedinstalls.plist"

else
	echo "Failed to install the managedinstalls collector!"
	rm -f "${MUNKIPATH}postflight.d/managedinstalls"

	# Signal that we had an error
	ERR=1
fi
