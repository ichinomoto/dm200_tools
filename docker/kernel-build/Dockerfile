FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --no-install-recommends --yes \
        bc \
        binutils-arm-linux-gnueabihf \
        bison \
        build-essential \
        ca-certificates \
        cpio \
        dwarves \
        file \
        flex \
        gcc-arm-linux-gnueabihf \
        kmod \
        libelf-dev \
        libssl-dev \
        python3 \
        rsync \
    && rm -rf /var/lib/apt/lists/*

ENV ARCH=arm \
    CROSS_COMPILE=arm-linux-gnueabihf-

COPY --chmod=0755 mkkrnlimg.py /usr/local/bin/mkkrnlimg
COPY --chmod=0755 package-dm200.sh /usr/local/bin/package-dm200

WORKDIR /workspace/git/linux

CMD ["bash"]
