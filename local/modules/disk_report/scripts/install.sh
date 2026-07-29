#!/bin/bash

# Overrides vendor/munkireport/disk_report/scripts/install.sh
#
# The vendor version downloads disk_info and depends on the MacAdmins Python
# framework. This one drops a wrapper that calls the built-in collector of
# munkireport-runner instead, so the client needs no Python at all.

# Remove the Python collector from previous installations
rm -f "${MUNKIPATH}preflight.d/disk_info"

# $0 is <munkipath>/scripts/disk_info, so ../munkireport-runner resolves
# regardless of where MunkiReport was installed
cat > "${MUNKIPATH}preflight.d/disk_info" <<'MRWRAPPER'
#!/bin/bash
exec "$(/usr/bin/dirname "$0")/../munkireport-runner" --collect disk_report
MRWRAPPER

if [ $? = 0 ]; then
	# Make executable
	chmod a+x "${MUNKIPATH}preflight.d/disk_info"

	# Set preference to include this file in the preflight check
	setreportpref "disk_report" "${CACHEPATH}disk.plist"

else
	echo "Failed to install the disk_report collector!"
	rm -f "${MUNKIPATH}preflight.d/disk_info"
	ERR=1
fi
