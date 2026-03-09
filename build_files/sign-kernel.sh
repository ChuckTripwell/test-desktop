#!/bin/bash
set -e

# Config
MOK_CERT_PEM="/usr/share/pki/MOK.pem"
MOK_CERT_DER="/usr/share/pki/MOK.der"
MOK_PRIV="/tmp/MOK.priv"
MOK_PASSWORD="universalblue"

echo "Checking for secret mount..."
if [ ! -f "$KERNEL_SECRET_PATH" ]; then
    echo "Error: KERNEL_SECRET_PATH not found. Check your GitHub Action 'secrets' input."
    exit 1
fi

# 1. Temporarily extract the key
cp "$KERNEL_SECRET_PATH" "$MOK_PRIV"
chmod 600 "$MOK_PRIV"

# 2. Find Kernel (OSTree style)
KERNEL_VERSION=$(ls /usr/lib/modules | head -n 1)
VMLINUZ="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

echo "Signing kernel: $KERNEL_VERSION"
sbsign --key "$MOK_PRIV" --cert "$MOK_CERT_PEM" --output "${VMLINUZ}.signed" "$VMLINUZ"
mv "${VMLINUZ}.signed" "$VMLINUZ"

# 3. Create Enrollment Service
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

# 4. Enable it
mkdir -p /usr/lib/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/enroll-mok.service /usr/lib/systemd/system/multi-user.target.wants/enroll-mok.service

# 5. Cleanup
rm -f "$MOK_PRIV"
echo "Kernel signing complete."
