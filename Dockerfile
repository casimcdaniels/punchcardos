FROM ubuntu:latest

RUN apt update && apt install -y \
   git curl gpg debianutils tar grep gzip gawk wget build-essential cmake bzip2 unzip parted xz-utils \
   qemu-system-x86 python3 file texinfo

RUN curl -sSL https://ftp.gnu.org/gnu/gnu-keyring.gpg | gpg --import

RUN git clone --depth 1 https://github.com/vvaltchev/tilck.git

ENV TC /tilck/toolchain2
ENV BUILD_SRC /build

ENV MTOOLS_VERSION 4.0.23
ENV GNUEFI_VERSION 3.0.17 
ENV ZLIB_VERSION 1.2.11
ENV BUSYBOX_VERSION=1.33.1

WORKDIR ${TC}
RUN mkdir -p ${TC}/i386
RUN echo -n "9.4.0" >> /tilck/toolchain2/.gcc_tc_ver_i386
RUN echo -n "debian" >> /tilck/toolchain2/.distro

WORKDIR ${BUILD_SRC}

RUN git clone https://github.com/richfelker/musl-cross-make.git
WORKDIR ${BUILD_SRC}/musl-cross-make

COPY config.mak .

# Build i386 cross compile toolchain
RUN make -j$(nproc) TARGET=i686-linux-musl
RUN make install TARGET=i686-linux-musl OUTPUT=${TC}/host_$(uname -m)/gcc_9_4_0_i686_musl
RUN cd ${TC}/host_$(uname -m)/gcc_9_4_0_i686_musl/bin && for x in *-linux-musl-*; do if [ -f "$x" ]; then n=$(echo $x | sed s/musl-//);  mv $x $n; fi; done

# Build x86_64 cross compile toolchain which is used to compile the UEFI bootloader
RUN make -j$(nproc) TARGET=x86_64-linux-musl
RUN make install TARGET=x86_64-linux-musl OUTPUT=${TC}/host_$(uname -m)/gcc_9_4_0_x86_64_musl
RUN cd ${TC}/host_$(uname -m)/gcc_9_4_0_x86_64_musl/bin && for x in *-linux-musl-*; do if [ -f "$x" ]; then n=$(echo $x | sed s/musl-//);  mv $x $n; fi; done

## Symlink toolchain directories that tilck make expects to exist
RUN ln -s ${TC}/host_$(uname -m)/gcc_9_4_0_i686_musl ${TC}/host_$(uname -m)/gcc_9_4_0_i386_musl
RUN ln -s ${TC}/host_$(uname -m) ${TC}/host

# ########### System toolchain dependencies #############

WORKDIR $TC/host/mtools
RUN curl -O https://ftp.gnu.org/gnu/mtools/mtools-${MTOOLS_VERSION}.tar.bz2 && \
  curl -O https://ftp.gnu.org/gnu/mtools/mtools-${MTOOLS_VERSION}.tar.bz2.sig && \
  gpg --verify mtools-${MTOOLS_VERSION}.tar.bz2.sig && \
  tar --strip-components 1 -xvf mtools-${MTOOLS_VERSION}.tar.bz2 && \
  ./configure && \
  make -j$(nproc)

COPY scripts /scripts

############ Cache ################
WORKDIR $TC/cache
RUN  git clone --branch "$GNUEFI_VERSION" https://github.com/vvaltchev/gnu-efi-fork.git gnu-efi && \
  cd gnu-efi && /scripts/gnuefi_patch.sh

# ########## i386 (i686) toolchain dependencies

WORKDIR $TC/i386
ENV PREFIX $TC/host/gcc_9_4_0_i386_musl/bin/i686-linux
ENV CC $PREFIX-gcc 
ENV CXX $PREFIX-g++
ENV AR $PREFIX-ar
ENV NM $PREFIX-nm
ENV RANLIB=$PREFIX-ranlib

# GNU-EFI (i386)
RUN cp -r $TC/cache/gnu-efi . && cd gnu-efi && \
    /scripts/gnuefi_patch.sh && \
    ARCH_EFI=$(/scripts/get_efi_arch.sh i386) && \
    make ARCH=$ARCH_EFI prefix=$TC/host/gcc_9_4_0_i386_musl/bin/i686-linux-

# ZLIB
RUN mkdir zlib && cd zlib && \
    curl -O https://www.zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz && \
    curl -O https://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz.asc && \
    gpg --keyserver pgp.surfnet.nl --recv-keys 783FCD8E58BCAFBA && \
    tar --strip-components 1 -xvzf zlib-${ZLIB_VERSION}.tar.gz && \
    export CROSS_PREFIX=$TC/host/gcc_9_4_0_i386_musl/bin/i686-linux- && \
    ./configure --prefix=$TC/i386/zlib/install --static && \
    make -j$(nproc) && \
    make install

# Busybox
RUN mkdir -p busybox && cd busybox && \
  curl -O https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 && \
  curl -O https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2.sha256 && \
  sha256sum -c busybox-${BUSYBOX_VERSION}.tar.bz2.sha256 && \
  tar --strip-components 1 -xvf busybox-${BUSYBOX_VERSION}.tar.bz2 && \
  cp -f /tilck/other/busybox.config $TC/i386/busybox/.config && \
  CROSS_COMPILE=$TC/host/gcc_9_4_0_i386_musl/bin/i686-linux- make && \
  cp -f /tilck/other/busybox.config $TC/i386/busybox/.config

########### x86_64 toolchain dependencies

WORKDIR $TC/x86_64
ENV PREFIX $TC/host/gcc_9_4_0_x86_64_musl/bin/x86_64-linux
ENV CC $PREFIX-gcc 
ENV CXX $PREFIX-g++
ENV AR $PREFIX-ar
ENV NM $PREFIX-nm
ENV RANLIB=$PREFIX-ranlib

# GNU-EFI (x86_64)
RUN cp -r $TC/cache/gnu-efi . && cd gnu-efi && \
    ARCH_EFI=$(/scripts/get_efi_arch.sh x86_64) && \
    make ARCH=$ARCH_EFI prefix=$PREFIX-

WORKDIR /tilck/

ENV ARCH i386
ENV PREFIX ""
ENV CC ""
ENV CXX ""
ENV AR ""
ENV NM ""
ENV RANLIB ""

ENV ARCH_SHORT "x86"
ENV ARCH_FAMILY "generic_x86"
ENV ARCH_ELF_NAME "elf32-i386"
ENV ARCH_LD_OUTPUT "elf_i386"
ENV ARCH_EFI i32
ENV ARCH_GCC_TC "i686"
ENV ARCH_GCC_FLAGS "-m32 -march=$ARCH_GCC_TC"
ENV ARCH_GCC_TC_CODENAME "x86-i686"


RUN ./scripts/cmake_run
RUN cd build && make
