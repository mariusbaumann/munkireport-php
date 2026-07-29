#!/bin/bash

# Overrides vendor/munkireport/softwareupdate/scripts/install.sh
#
# The vendor version downloads softwareupdate and depends on the MacAdmins Python
# framework. This one drops a wrapper that calls the built-in collector of
# munkireport-runner instead, so the client needs no Python at all.

# Remove the Python collector from previous installations
rm -f "${MUNKIPATH}preflight.d/softwareupdate"

# $0 is <munkipath>/scripts/softwareupdate, so ../munkireport-runner resolves
# regardless of where MunkiReport was installed
cat > "${MUNKIPATH}preflight.d/softwareupdate" <<'MRWRAPPER'
#!/bin/bash
exec "$(/usr/bin/dirname "$0")/../munkireport-runner" --collect softwareupdate
MRWRAPPER

if [ $? = 0 ]; then
	# Make executable
	chmod a+x "${MUNKIPATH}preflight.d/softwareupdate"

	# Set preference to include this file in the preflight check
	setreportpref "softwareupdate" "${CACHEPATH}softwareupdate.plist"

else
	echo "Failed to install the softwareupdate collector!"
	rm -f "${MUNKIPATH}preflight.d/softwareupdate"

	# Signal that we had an error
	ERR=1
fi
