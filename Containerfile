##################################################################################################################################################
### :::::: pull cachyos :::::: ###
##################################################################################################################################################
FROM docker.io/cachyos/cachyos-v3:latest AS cachyos

# :::::: prepare the kernel :::::: 
RUN rm -rf /lib/modules/*
RUN pacman -Sy --noconfirm
RUN pacman -S --noconfirm linux-cachyos-nvidia-open


##################################################################################################################################################
### :::::: pull ublue-os :::::: ###
##################################################################################################################################################
FROM ghcr.io/ublue-os/bazzite-nvidia-open:latest

# :::::: disable countme ( we always disable it anyway, so this  is to save us time. you can enable it if you want... ) :::::: 
RUN sed -i -e s,countme=1,countme=0, /etc/yum.repos.d/*.repo && systemctl mask --now rpm-ostree-countme.timer

# :::::: force distrobox to use a sub-directory for home :::::: 
RUN mkdir -p /usr/share/distrobox/
RUN touch /usr/share/distrobox/distrobox.conf
RUN echo "DBX_CONTAINER_HOME_PREFIX=~/distrobox" >> /usr/share/distrobox/distrobox.conf

# :::::: forcefully remove and replace kernel :::::: 
RUN rm -rf /lib/modules
COPY --from=cachyos /lib/modules /lib/modules
COPY --from=cachyos /usr/share/licenses/ /usr/share/licenses/

# :::::: refresh akmods so that nvidia drivers actually catch... :::::: 
RUN dnf5 -y install rpmdevtools akmods

# :::::: Set vm.max_map_count for stability/improved gaming performance :::::: 
# :::::: https://wiki.archlinux.org/title/Gaming#Increase_vm.max_map_count :::::: 
RUN echo -e "vm.max_map_count = 2147483642" > /etc/sysctl.d/80-gamecompatibility.conf
#RUN echo "vm.swappiness=10" >> /etc/sysctl.conf
RUN echo "kernel.sched_migration_cost_ns=5000000" >> /etc/sysctl.d/80-gamecompatibility.conf

# :::::: install preformence-related stuff :::::: 
RUN dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
RUN dnf5 -y install --allowerasing scx-scheds scx-tools scxctl cachyos-settings uksmd scx-manager
RUN dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

# :::::: install additional stuff :::::: 
RUN dnf5 -y install python3-pygame

##################################################################################################################################################
### :::::: fixes :::::: ###
##################################################################################################################################################

# :::::: install sbctl to sign some keys later..? ::::::
RUN dnf5 -y copr enable chenxiaolong/sbctl
RUN dnf5 -y install sbctl


# :::::: experimental millennium support :::::: 
#RUN bash -c 'id(){ echo 1000; }; export -f id; curl -fsSL https://steambrew.app/install.sh -o /tmp/install.sh; sed -i "/:: Proceed with installation? \[Y\/n\]/d" /tmp/install.sh; bash /tmp/install.sh'

# test for grub signing
RUN ln -s '/usr/lib/grub/i386-pc' '/usr/lib/grub/x86_64-efi'

# attempt to sign kernel after each update

# Create the enroll script safely (echo shebang first)
RUN mkdir -p /usr/local/sbin && \
    echo "#!/usr/bin/env bash" > /usr/local/sbin/enroll-sbctl.sh && \
    echo "" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "# enroll-sbctl.sh: Create SBCTL keys if missing, then enroll Microsoft keys on new deployment" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "STAMP_FILE=\"/var/lib/sbctl/enrolled\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "LAST_DEPLOYMENT_FILE=\"/var/lib/sbctl/last_deployment\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "KEYS_DIR=\"/etc/secureboot/keys\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "mkdir -p \"\$(dirname \"\$STAMP_FILE\")\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "# 1. Create keys if they don't exist" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "if [ ! -d \"\$KEYS_DIR\" ] || [ -z \"\$(ls -A \$KEYS_DIR 2>/dev/null)\" ]; then" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    echo \"Creating SBCTL keys...\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    sbctl create-keys" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "fi" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "# 2. Determine current deployment checksum (side-B detection)" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "CURRENT_DEPLOYMENT=\$(ostree admin status | awk '/^\\*/{getline; print \$1}')" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "# 3. Read last deployment checksum if exists" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "if [ -f \"\$LAST_DEPLOYMENT_FILE\" ]; then" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    LAST_DEPLOYMENT=\$(cat \"\$LAST_DEPLOYMENT_FILE\")" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "else" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    LAST_DEPLOYMENT=\"\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "fi" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "# 4. Run enroll only if this is a new deployment" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "if [ \"\$CURRENT_DEPLOYMENT\" != \"\$LAST_DEPLOYMENT\" ] && [ ! -f \"\$STAMP_FILE\" ]; then" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    echo \"Enrolling Microsoft Secure Boot keys...\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    sbctl enroll-keys --microsoft" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    echo \"\$CURRENT_DEPLOYMENT\" > \"\$LAST_DEPLOYMENT_FILE\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "    touch \"\$STAMP_FILE\"" >> /usr/local/sbin/enroll-sbctl.sh && \
    echo "fi" >> /usr/local/sbin/enroll-sbctl.sh && \
    chmod +x /usr/local/sbin/enroll-sbctl.sh

# Create systemd service inside Dockerfile
RUN cat > /etc/systemd/system/sbctl-enroll.service <<'EOF'
[Unit]
Description=Enroll Secure Boot keys only on new OSTree deployment
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/enroll-sbctl.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

# Enable service
RUN systemctl enable sbctl-enroll.service


##################################################################################################################################################
### :::::: fixes end here :::::: ###
##################################################################################################################################################

# :::::: slot the kernel into place :::::: 
RUN mkdir -p /var/tmp
RUN printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
      printf 'hostonly=no\nadd_dracutmodules+=" ostree bootc "' | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-modules.conf && \
      sh -c 'export KERNEL_VERSION="$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)")" && \
      dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION"  "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"'

# test 
#RUN sbctl-batch-sign
#RUN sbctl enroll-keys --microsoft

#  :::::: finish :::::: 
ENV DRACUT_NO_XATTR=1
RUN bootc container lint
