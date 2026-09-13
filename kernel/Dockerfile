FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Tokyo

RUN apt-get update \
    && apt-get install --no-install-recommends --yes \
        bc \
        binutils-arm-linux-gnueabihf \
        bison \
        build-essential \
        ca-certificates \
        cpio \
        device-tree-compiler \
        dwarves \
        file \
        flex \
        gcc-arm-linux-gnueabihf \
        git \
        libgnutls28-dev \
        kmod \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        python3 \
        python3-pyelftools \
        rsync \
        swig \
        tzdata \
        uuid-dev \
    && ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime \
    && rm -rf /var/lib/apt/lists/*

ENV ARCH=arm \
    CROSS_COMPILE=arm-linux-gnueabihf-

WORKDIR /workspace/linux

CMD ["bash"]
