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
















# Prepare output directory for scripts and systemd unit
RUN mkdir -p /output

# One-time host systemd service to initialize and enroll sbctl key
RUN echo '[Unit]' > /output/sbctl-init.service && \
    echo 'Description=One-time sbctl key enrollment for Secure Boot' >> /output/sbctl-init.service && \
    echo 'After=network.target' >> /output/sbctl-init.service && \
    echo '[Service]' >> /output/sbctl-init.service && \
    echo 'Type=oneshot' >> /output/sbctl-init.service && \
    echo 'ExecStart=/usr/local/bin/init_sbctl.sh' >> /output/sbctl-init.service && \
    echo 'RemainAfterExit=yes' >> /output/sbctl-init.service && \
    echo '[Install]' >> /output/sbctl-init.service && \
    echo 'WantedBy=multi-user.target' >> /output/sbctl-init.service

# Host init script called by the above systemd service
RUN echo '#!/bin/bash' > /output/init_sbctl.sh && \
    echo 'set -e' >> /output/init_sbctl.sh && \
    echo 'if [ ! -d "$HOME/.sbctl" ]; then' >> /output/init_sbctl.sh && \
    echo '    echo "Initializing sbctl keys..."' >> /output/init_sbctl.sh && \
    echo '    sudo sbctl init' >> /output/init_sbctl.sh && \
    echo 'fi' >> /output/init_sbctl.sh && \
    echo 'if ! mokutil --list-enrolled | grep -q "sbctl"; then' >> /output/init_sbctl.sh && \
    echo '    echo "Enrolling sbctl keys..."' >> /output/init_sbctl.sh && \
    echo '    sudo sbctl enroll-keys' >> /output/init_sbctl.sh && \
    echo '    echo "Reboot required to complete enrollment."' >> /output/init_sbctl.sh && \
    echo 'else' >> /output/init_sbctl.sh && \
    echo '    echo "Keys already enrolled."' >> /output/init_sbctl.sh

RUN chmod +x /output/init_sbctl.sh

# Sign current kernel and modules at build time
RUN sbctl sign --kver $(uname -r)

# Post-upgrade signing hook for future kernels
RUN echo '#!/bin/bash' > /output/post_upgrade_sign.sh && \
    echo 'set -e' >> /output/post_upgrade_sign.sh && \
    echo 'KVER=$(uname -r)' >> /output/post_upgrade_sign.sh && \
    echo 'sbctl sign --kver "$KVER"' >> /output/post_upgrade_sign.sh && \
    echo 'sbctl verify --kver "$KVER"' >> /output/post_upgrade_sign.sh

RUN chmod +x /output/post_upgrade_sign.sh
















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
