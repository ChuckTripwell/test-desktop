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

FROM ghcr.io/viggle-by/pikaos-docker:nightly AS base

FROM base AS builder



RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root --mount=type=tmpfs,dst=/boot \
    apt update -y && \
    apt install -y git curl make build-essential go-md2man libzstd-dev pkgconf dracut libostree-dev ostree

ENV CARGO_HOME=/tmp/rust
ENV RUSTUP_HOME=/tmp/rust
WORKDIR /home/build





RUN git clone "https://github.com/bootc-dev/bootc.git" .
RUN make bin install-all DESTDIR=/output






FROM base AS system
COPY --from=builder /output /

RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root --mount=type=tmpfs,dst=/boot apt update -y && \
  apt install -y btrfs-progs dosfstools e2fsprogs fdisk firmware-linux-free linux-image-generic skopeo systemd systemd-boot* xfsprogs libostree-dev && \
  cp /boot/vmlinuz-* "$(find /usr/lib/modules -maxdepth 1 -type d | tail -n 1)/vmlinuz" && \
  apt clean -y

RUN mkdir -p /usr/lib/dracut/dracut.conf.d/
RUN printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf
RUN printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" bootc "' | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf"
RUN dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img"


# :::::: forcefully remove and replace kernel :::::: 
RUN rm -rf /lib/modules/*
COPY --from=cachyos /lib/modules /lib/modules
COPY --from=cachyos /usr/share/licenses /usr/share/licenses

# :::::: SecureBoot stuff :::::: 
RUN deb install -y mokutil sbsigntools diffutils
RUN mkdir -p /usr/share/cert
RUN mkdir -p /tmp/cert
COPY MOK.priv /tmp/cert/MOK.priv
COPY build_files/MOK.pem /usr/share/cert/MOK.pem
COPY build_files/sign-kernel.sh /tmp/sign-kernel.sh 
RUN chmod +x /tmp/sign-kernel.sh && /tmp/sign-kernel.sh 


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
