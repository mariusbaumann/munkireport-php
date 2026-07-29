#!/bin/bash

# Overrides vendor/munkireport/network_shares/scripts/install.sh
#
# The vendor version downloads network_shares.py and depends on the MacAdmins Python
# framework. This one drops a wrapper that calls the built-in collector of
# munkireport-runner instead, so the client needs no Python at all.

# Remove the Python collector from previous installations
rm -f "${MUNKIPATH}preflight.d/network_shares.py"

# $0 is <munkipath>/scripts/network_shares, so ../munkireport-runner resolves
# regardless of where MunkiReport was installed
cat > "${MUNKIPATH}preflight.d/network_shares" <<'MRWRAPPER'
#!/bin/bash
exec "$(/usr/bin/dirname "$0")/../munkireport-runner" --collect network_shares
MRWRAPPER

if [ $? = 0 ]; then
	# Make executable
	chmod a+x "${MUNKIPATH}preflight.d/network_shares"

	# Set preference to include this file in the preflight check
	setreportpref "network_shares" "${CACHEPATH}network_shares.plist"

else
	echo "Failed to install the network_shares collector!"
	rm -f "${MUNKIPATH}preflight.d/network_shares"

	# Signal that we had an error
	ERR=1
fi
