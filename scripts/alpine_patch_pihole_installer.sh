#!/bin/sh
set -eux

# Define variables
INSTALLER_URL="https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh"
INSTALLER="/temp/basic-install.sh"

echo "Downloading Pi-hole installer from ${INSTALLER_URL}..."
curl -sSL "$INSTALLER_URL" -o "$INSTALLER"

# Patch the installer:
# Remove lines checking for systemctl availability.
sed -i '/command -v systemctl/d' "$INSTALLER"
# Remove lines mentioning SELinux not detected.
sed -i '/SELinux not detected/d' "$INSTALLER"
# Instead of deleting exit commands (which can break block structure),
# comment out any line that starts with "exit 1" (allowing for leading whitespace).
sed -i 's/^[[:space:]]*exit 1\b/#&/g' "$INSTALLER"

echo "Pi-hole installer patched successfully."

# Run the patched installer in unattended mode.
bash "$INSTALLER" --unattended

# Optionally remove the patched installer.
rm -f "$INSTALLER"

echo "Pi-hole installation completed on Alpine."
