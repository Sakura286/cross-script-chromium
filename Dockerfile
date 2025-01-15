FROM ubuntu:noble 

MAINTAINER CHEN Xuan 

ARG WORKSPACE=/workspace 
ARG CHROMIUM_DIR=$WORKSPACE/chromium-rokcos-master 
ARG LLVM_DIR=$CHROMIUM_DIR/third_party/llvm-build/Release+Asserts/bin 
ARG SCRIPT_DIR=$WORKSPACE/eswin-scripts 

ARG USER_EMAIL=chenxuan@iscas.ac.cn 
ARG USER_NAME='CHEN Xuan' 

USER root 

# Prepare Environment
RUN mkdir $WORKSPACE
WORKDIR $WORKSPACE 
RUN --mount=target=/var/lib/apt/lists,type=cache,sharing=locked \
    --mount=target=/var/cache/apt,type=cache,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list.d/ubuntu.sources && \
    apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y \
        zip wget multistrap curl git lsb-release python3 git file ninja-build build-essential ca-certificates gnutls-bin   \
        sudo elfutils wget flex yasm xvfb wdiff gperf bison nodejs rollup valgrind xz-utils x11-apps xcb-proto xfonts-base \
        libdav1d-dev libx11-xcb-dev libxshmfence-dev libgl-dev libglu1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev         \
        libopenh264-dev generate-ninja mesa-common-dev rapidjson-dev libva-dev libxt-dev libgbm-dev libpng-dev libxss-dev  \
        libelf-dev libpci-dev libcap-dev libdrm-dev libffi-dev libhwy-dev libkrb5-dev libexif-dev libflac-dev libudev-dev  \
        libpipewire-0.3-dev libopus-dev libxtst-dev libjpeg-dev libxml2-dev libgtk-3-dev libxslt1-dev liblcms2-dev         \
        libpulse-dev libpam0g-dev libtiff-dev libdouble-conversion-dev libxnvctrl-dev libglib2.0-dev libasound2-dev        \
        libsecret-1-dev libspeechd-dev libminizip-dev libhunspell-dev libharfbuzz-dev libxcb-dri3-dev libusb-1.0-0-dev     \
        libopenjp2-7-dev libmodpbase64-dev libnss3-dev libnspr4-dev libcups2-dev libevent-dev libevdev-dev libgcrypt20-dev \
        libcurl4-openssl-dev libzstd-dev fonts-ipafont-gothic fonts-ipafont-mincho && \
    git config --global user.email $USER_EMAIL && \
    git config --global user.name $USER_NAME && \
    git config --global http.version HTTP/1.1

# Get patches and sysroot conf
RUN git clone --depth=1 https://github.com/Sakura286/cross-chromium-dl $SCRIPT_DIR
RUN curl -o multistrap-auth.patch "https://bugs.debian.org/cgi-bin/bugreport.cgi?att=1;bug=908451;filename=multistrap.patch;msg=17"

# Get depot_tools
RUN git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git 
RUN echo 'export PATH=$HOME/depot_tools:$PATH' >> ~/.bashrc 

# Get Source Code
# TODO: Use rockos source repo and patch the patches seperately
RUN git clone --progress --depth=1 https://github.com/Sakura286/chromium-rokcos.git $CHROMIUM_DIR
RUN $CHROMIUM_DIR/build/install-build-deps.sh 

# Prepare Sysroot
## (1) Patch multistrap
WORKDIR $WORKSPACE 
RUN patch -p0 /usr/sbin/multistrap multistrap-auth.patch 
WORKDIR $CHROMIUM_DIR 
## (2) Get riscv64 sysroot
### You can also run
###   multistrap -a riscv64 -d build/linux/debian_sid_riscv64-sysroot -f $SCRIPT_DIR/sysroot-riscv64.conf
### to get riscv64 sysroot here
RUN cd build/linux/ && \
    wget http://etherpad.sakura286.ink/share/debian_sid_riscv64-sysroot-0110.tar.gz && \
    tar xf debian_sid_riscv64-sysroot-0110.tar.gz && \
    cd debian_sid_riscv64-sysroot && \
    mv usr/lib/riscv64-linux-gnu/pkgconfig/* usr/lib/pkgconfig/ && \
    rm -f usr/bin/python* 
## (3) Get amd64 chroot
### TODO: Check bookwork and bullseye chroot define in gn files
RUN multistrap -a amd64 -d build/linux/debian_bookworm_amd64-sysroot -f $SCRIPT_DIR/sysroot-amd64.conf 
RUN cd build/linux/debian_bookworm_amd64-sysroot && \
    mv usr/lib/x86_64-linux-gnu/pkgconfig/* usr/lib/pkgconfig/ && \
    rm -f usr/bin/python* && \
    cd usr/lib/x86_64-linux-gnu/ && \
    for i in $(find . -type l -lname '/*' | grep lib); do STR=$(ls -l $i); rm $i; ln -s ./$(echo $STR | sed 's/  */ /g' | cut -d' ' -f 11 | cut -d'/' -f 4) $i; done
RUN mkdir -p third_party/llvm-build-tools && \
    ln -s ../../build/linux/debian_sid_riscv64-sysroot third_party/llvm-build-tools/debian_sid_riscv64_sysroot && \
    ln -s ../../build/linux/debian_bookworm_amd64-sysroot third_party/llvm-build-tools/debian_bookworm_amd64-sysroot

# Build Rust and LLVM
WORKDIR $CHROMIUM_DIR
RUN tools/rust/package_rust.py

# Build GN
WORKDIR $WORKSPACE
RUN git clone https://gn.googlesource.com/gn && \
    cd gn && \
    CXX=$LLVM_DIR/clang++ AR=$LLVM_DIR/llvm-ar python3 build/gen.py && \
    ninja -C out
RUN echo 'export $HOME/gn/out:$PATH' >> ~/.bashrc

# Configure node support
WORKDIR $CHROMIUM_DIR
RUN mkdir -p third_party/node/linux/node-linux-x64/bin && \
    cp /usr/bin/node third_party/node/linux/node-linux-x64/bin && \
    cp -ra /usr/share/nodejs/rollup third_party/node/node_modules/

# Prefer unbundled (system) library
RUN debian/scripts/unbundle

# Configure chromium
RUN $SCRIPT_DIR/build.sh

# Some other hack
## v8_snapshot_generator use some lib that only exist in amd64 sysroot
RUN apt install -y libjpeg62 && cp third_party/llvm-build-tools/debian_bullseye_amd64_sysroot/usr/lib/x86_64-linux-gnu/libdav1d.so.6 /usr/lib/x86_64-linux-gnu/

# Source: Build chromium
CMD echo shit

