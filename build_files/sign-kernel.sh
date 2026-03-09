#!/bin/bash
set -e

# Setup paths
MOK_CERT_PEM="/usr/share/pki/MOK.pem"
MOK_CERT_DER="/usr/share/pki/MOK.der"
MOK_PRIV="/tmp/MOK.priv"
MOK_PASSWORD="universalblue"
SECRET_MOUNT="/run/secrets/KERNEL_SECRET"

echo "Locating secret..."
if [ -f "$SECRET_MOUNT" ]; then
    cp "$SECRET_MOUNT" "$MOK_PRIV"
    chmod 600 "$MOK_PRIV"
else
    echo "Error: Secret not found at $SECRET_MOUNT."
    echo "Existing secrets:"
    ls -la /run/secrets 2>/dev/null || echo "/run/secrets/ does not exist."
    exit 1
fi

# Find Kernel Version (OSTree-safe)
KERNEL_VERSION=$(ls /usr/lib/modules | head -n 1)
VMLINUZ="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

echo "Signing kernel: $KERNEL_VERSION"
sbsign --key "$MOK_PRIV" --cert "$MOK_CERT_PEM" --output "${VMLINUZ}.signed" "$VMLINUZ"
mv "${VMLINUZ}.signed" "$VMLINUZ"

# Create Enrollment Service
cat <<EOF > /usr/lib/systemd/system/enroll-mok.service
[Unit]
Description=Enroll MOK key on first boot
ConditionPathExists=${MOK_CERT_DER}
ConditionPathExists=!/var/lib/mok-enrolled

[Service]
Type=oneshot
ExecStart=/usr/bin/sh -c '(echo "${MOK_PASSWORD}"; echo "${MOK_PASSWORD}") | mokutil --import "${MOK_CERT_DER}"'
ExecStartPost=/usr/bin/touch /var/lib/mok-enrolled
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
mkdir -p /usr/lib/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/enroll-mok.service /usr/lib/systemd/system/multi-user.target.wants/enroll-mok.service

# Cleanup
rm -f "$MOK_PRIV"
echo "Done."
