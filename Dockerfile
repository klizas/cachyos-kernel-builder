FROM archlinux:latest

# Initialize pacman and install base packages
RUN pacman-key --init && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        base-devel \
        bc \
        cpio \
        gettext \
        libelf \
        pahole \
        perl \
        python \
        rust \
        rust-bindgen \
        rust-src \
        tar \
        xz \
        zstd \
        clang \
        llvm \
        lld \
        git \
        curl \
        pacman-contrib && \
    pacman -Scc --noconfirm

# makepkg refuses to run as root
RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder/build
