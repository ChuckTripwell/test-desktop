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

FROM ghcr.io/bootcrew/opensuse-bootc:latest

# :::::: forcefully remove and replace kernel :::::: 
RUN rm -rf /lib/modules/*
COPY --from=cachyos /lib/modules /lib/modules
COPY --from=cachyos /usr/share/licenses /usr/share/licenses

# :::::: SecureBoot stuff :::::: 
RUN dnf5 -y install --allowerasing mokutil sbsigntools
RUN mkdir -p /usr/share/cert
RUN mkdir -p /tmp/cert
COPY MOK.priv /tmp/cert/MOK.priv
COPY build_files/MOK.pem /usr/share/cert/MOK.pem
COPY build_files/sign-kernel.sh /tmp/sign-kernel.sh 
RUN chmod +x /tmp/sign-kernel.sh && /tmp/sign-kernel.sh 



# :::::: slot the kernel into place :::::: 
RUN mkdir -p /var/tmp
RUN printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
      printf 'hostonly=no\nadd_dracutmodules+=" ostree bootc "' | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-modules.conf && \
      sh -c 'export KERNEL_VERSION="$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)")" && \
      dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION"  "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"'

#  :::::: finish :::::: 
RUN rm -rf /usr/etc
LABEL containers.bootc 1
RUN bootc container lint
