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
RUN echo "DBX_CONTAINER_HOME_PREFIX=$HOME/distrobox" >> /usr/share/distrobox/distrobox.conf

# :::::: forcefully remove and replace kernel :::::: 
RUN rm -rf /lib/modules
COPY --from=cachyos /lib/modules /lib/modules
COPY --from=cachyos /usr/share/licenses/ /usr/share/licenses/

# :::::: refresh akmods so that nvidia drivers actually catch... :::::: 
RUN dnf5 -y install rpmdevtools akmods

# :::::: Set vm.max_map_count for stability/improved gaming performance :::::: 
# :::::: https://wiki.archlinux.org/title/Gaming#Increase_vm.max_map_count :::::: 
RUN echo -e "vm.max_map_count = 2147483642" > /etc/sysctl.d/80-gamecompatibility.conf

# :::::: install preformence-related stuff :::::: 
RUN dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
RUN dnf5 -y install --allowerasing scx-scheds scx-tools scxctl cachyos-settings uksmd scx-manager
RUN dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

# :::::: install additional stuff :::::: 
RUN dnf5 -y install python3-pygame

##################################################################################################################################################
### :::::: fixes :::::: ###
##################################################################################################################################################

# experimental millennium support
#RUN bash -c 'id(){ echo 1000; }; export -f id; curl -fsSL https://steambrew.app/install.sh -o /tmp/install.sh; sed -i "/:: Proceed with installation? \[Y\/n\]/d" /tmp/install.sh; bash /tmp/install.sh'

# :::::: audio fix ::::::

RUN printf "[Unit]\n\
Description=ALSA restore watchdog\n\
After=multi-user.target\n\n\
[Service]\n\
Type=simple\n\
ExecStart=/usr/bin/alsactl init\n\
Restart=on-failure\n\
RestartSec=10\n\
StartLimitBurst=5\n\
StartLimitIntervalSec=60\n\
User=root\n\n\
[Install]\n\
WantedBy=multi-user.target\n" > /etc/systemd/system/alsactl-start.service

#RUN systemctl enable alsactl-start.service

RUN printf "[Unit]\n\
Description=Run alsactl init on volume key press\n\
After=multi-user.target\n\n\
\[Service]\n\
Type=simple\n\
ExecStart=/bin/sh -c \"/usr/bin/libinput debug-events --device /dev/input/event5 | /usr/bin/awk '/KEY_VOLUME(UP|DOWN).*pressed/ { system(\\\"/usr/bin/alsactl init\\\") }'\"\n\
Restart=always\n\
User=root\n\n\
\[Install]\n\
WantedBy=multi-user.target\n" > /etc/systemd/system/alsactl-fix.service

RUN systemctl enable alsactl-fix.service

##################################################################################################################################################
### :::::: fixes end here :::::: ###
##################################################################################################################################################

# :::::: slot the kernel into place :::::: 
RUN mkdir -p /var/tmp
ENV DRACUT_NO_XATTR=1
RUN printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
      printf 'hostonly=no\nadd_dracutmodules+=" ostree bootc "' | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-modules.conf && \
      sh -c 'export KERNEL_VERSION="$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)")" && \
      dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION"  "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"'

#  :::::: finish :::::: 
RUN bootc container lint
