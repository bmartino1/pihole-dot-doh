#!/bin/sh
set -eux

# Define variables
INSTALLER_URL="https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh"
INSTALLER="/temp/basic-install.sh"

# Download the official Pi-hole installer script to /temp
echo "Downloading Pi-hole installer from ${INSTALLER_URL}..."
curl -sSL "$INSTALLER_URL" -o "$INSTALLER"

# Patch the installer:
# Remove lines checking for systemctl availability.
sed -i '/command -v systemctl/d' "$INSTALLER"
# Remove lines mentioning SELinux not detected.
sed -i '/SELinux not detected/d' "$INSTALLER"
# Remove any exit commands that would abort the install.
sed -i '/exit 1/d' "$INSTALLER"

echo "Pi-hole installer patched successfully."

# Run the patched installer in unattended mode.
bash "$INSTALLER" --unattended

# Optionally remove the patched installer.
rm -f "$INSTALLER"

echo "Pi-hole installation completed on Alpine."
