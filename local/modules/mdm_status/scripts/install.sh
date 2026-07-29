#!/bin/bash

# Overrides vendor/munkireport/mdm_status/scripts/install.sh
#
# The vendor version downloads mdm_status.py and depends on the MacAdmins Python
# framework. This one drops a wrapper that calls the built-in collector of
# munkireport-runner instead, so the client needs no Python at all.

# Remove the Python collector from previous installations
rm -f "${MUNKIPATH}preflight.d/mdm_status.py"

# $0 is <munkipath>/scripts/mdm_status, so ../munkireport-runner resolves
# regardless of where MunkiReport was installed
cat > "${MUNKIPATH}preflight.d/mdm_status" <<'MRWRAPPER'
#!/bin/bash
exec "$(/usr/bin/dirname "$0")/../munkireport-runner" --collect mdm_status
MRWRAPPER

if [ $? = 0 ]; then
	# Make executable
	chmod a+x "${MUNKIPATH}preflight.d/mdm_status"

	# Set preference to include this file in the preflight check
	setreportpref "mdm_status" "${CACHEPATH}mdm_status.plist"

else
	echo "Failed to install the mdm_status collector!"
	rm -f "${MUNKIPATH}preflight.d/mdm_status"

	# Signal that we had an error
	ERR=1
fi
