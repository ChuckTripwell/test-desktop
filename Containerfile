##################################################################################################################################################
### :::::: pull cachyos :::::: ###
##################################################################################################################################################
FROM docker.io/cachyos/cachyos-v3:latest AS cachyos

# :::::: prepare the kernel :::::: 
  RUN rm -rf /lib/modules/*
  RUN pacman -Sy --noconfirm
# "*-headers" file is required for SecureBoot to work properly
  RUN pacman -S --noconfirm linux-cachyos-rc-nvidia-open linux-cachyos-rc-headers

##################################################################################################################################################
### :::::: pull os :::::: ###
##################################################################################################################################################




##################################################################################################################################################
### :::::: pull ublue-os :::::: ###
##################################################################################################################################################
FROM ghcr.io/ublue-os/bazzite-nvidia-open:testing

# :::::: disable countme ( we always disable it anyway, so this  is to save us time. you can enable it if you want... ) :::::: 
RUN sed -i -e s,countme=1,countme=0, /etc/yum.repos.d/*.repo && systemctl mask --now rpm-ostree-countme.timer

# :::::: force distrobox to use a sub-directory for home :::::: 
RUN mkdir -p /usr/share/distrobox/
RUN touch /usr/share/distrobox/distrobox.conf
RUN echo "DBX_CONTAINER_HOME_PREFIX=~/distrobox" >> /usr/share/distrobox/distrobox.conf

# :::::: forcefully remove and replace kernel :::::: 
RUN rm -rf /lib/modules/*
COPY --from=cachyos /lib/modules /lib/modules
COPY --from=cachyos /usr/share/licenses /usr/share/licenses

# :::::: Fix Vulkan :::::: 
RUN TMPDIR="$(mktemp -d)" && \
    dnf5 download "VK_hdr_layer" --destdir "$TMPDIR" && \
    RPM_FILE=$(ls "$TMPDIR"/*.rpm) && \
    mkdir "$TMPDIR/VK_hdr_layer" && \
    cd "$TMPDIR/VK_hdr_layer" && \
    # Extract RPM
    rpm2cpio "$RPM_FILE" | cpio -idmv && \
    # Libraries
    mkdir -p /usr/lib64/VK_hdr_layer && \
    cp -v usr/lib64/VK_hdr_layer/* /usr/lib64/VK_hdr_layer/ && \
    # Vulkan implicit layer
    mkdir -p /usr/share/vulkan/implicit_layer.d && \
    mkdir -p /usr/share/vulkan/implicit_layer.d && \
    cp -v usr/share/vulkan/implicit_layer.d/VkLayer_hdr_wsi.*.json /usr/share/vulkan/implicit_layer.d/ && \
    # License & Docs
    mkdir -p /usr/share/licenses/VK_hdr_layer && \
    cp -v usr/share/licenses/VK_hdr_layer/* /usr/share/licenses/VK_hdr_layer/ && \
    mkdir -p /usr/share/doc/VK_hdr_layer && \
    cp -v usr/share/doc/VK_hdr_layer/* /usr/share/doc/VK_hdr_layer/

# :::::: preformence-related stuff :::::: 
# scx gui and settings - essential for performance
  RUN dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
  RUN dnf5 -y install --allowerasing scx-scheds scx-tools scxctl cachyos-settings uksmd scx-manager
  RUN dnf5 -y copr disable bieszczaders/kernel-cachyos-addons
# Set vm.max_map_count for stability/improved gaming performance
# https://wiki.archlinux.org/title/Gaming#Increase_vm.max_map_count
  RUN echo -e "vm.max_map_count = 2147483642" > /etc/sysctl.d/80-gamecompatibility.conf
  #RUN echo "vm.swappiness=10" >> /etc/sysctl.conf
# found it somewhere... seems legit.
  RUN echo "kernel.sched_migration_cost_ns=5000000" >> /etc/sysctl.d/80-gamecompatibility.conf

# :::::: install additional stuff :::::: 
RUN dnf5 -y install --allowerasing install python3-pygame
RUN dnf5 -y install --allowerasing tlp
RUN dnf5 -y install --allowerasing zcfan

# :::::: SecureBoot stuff :::::: 
RUN dnf5 -y install --allowerasing mokutil sbsigntools
RUN mkdir -p /usr/share/cert
RUN mkdir -p /tmp/cert
COPY MOK.priv /tmp/cert/MOK.priv
COPY build_files/MOK.pem /usr/share/cert/MOK.pem
COPY build_files/sign-kernel.sh /tmp/sign-kernel.sh 
RUN chmod +x /tmp/sign-kernel.sh && /tmp/sign-kernel.sh 

# :::::: refresh akmods so that nvidia drivers actually catch... :::::: 
# do not move this segment!
RUN dnf5 -y install --allowerasing install rpmdevtools akmods

# :::::: slot the kernel into place :::::: 
#RUN mkdir -p /var/tmp


RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg && \
    mkdir -p /sysroot /boot /usr/lib/ostree /var && \
    ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local && \
    echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"

#  :::::: finish :::::: 
RUN rm -rf /usr/etc
LABEL containers.bootc 1
RUN bootc container lint
