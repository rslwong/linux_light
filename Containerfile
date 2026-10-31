# Build environment for Linux Light: Debian live-build plus the bootloader
# bits it needs on the "host" side (we run lb with --build-with-chroot false).
FROM docker.io/library/debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        live-build debootstrap ca-certificates wget \
        xorriso squashfs-tools mtools dosfstools e2fsprogs \
        grub-common grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin \
        grub-efi-amd64-signed shim-signed \
        apt-utils dctrl-tools cpio xz-utils zstd rsync file procps \
        librsvg2-bin fonts-dejavu-core isolinux \
 && rm -rf /var/lib/apt/lists/*

# Build dependencies of the Debian packages that scripts/build-packages.sh
# rebuilds with the patches in packages/.
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends build-essential dpkg-dev \
 && apt-get build-dep -y xserver-xorg-input-libinput \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
