FROM ghcr.io/lumaeris/cachyos-deckify-bootc:latest


RUN pacman --noconfirm -Sy gamescope-session-cachyos

ENV DRACUT_NO_XATTR=1
RUN bootc container lint
