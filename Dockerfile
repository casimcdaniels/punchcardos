FROM ubuntu:latest

ARG ARCH=x86_64

###############################################################
### Validate the build arguments first, so time isn't wasted 
COPY scripts ./scripts
RUN ./scripts/check_args.sh $ARCH
###############################################################

RUN apt update && apt install -y \
    wget git gpg curl build-essential texinfo cmake rpm2cpio cpio

RUN curl -sSL https://ftp.gnu.org/gnu/gnu-keyring.gpg | gpg --import

RUN git clone --depth 1 https://github.com/vvaltchev/tilck.git

ENV BUILD_SRC /build/
ENV TCROOT /tilck/toolchain2
ENV TC ${TCROOT}

WORKDIR ${TCROOT}
RUN mkdir -p ${TCROOT}/$ARCH
RUN echo -n "9.4.0" >> /tilck/toolchain2/.gcc_tc_ver_$ARCH
RUN echo -n "debian" >> /tilck/toolchain2/.distro

WORKDIR ${BUILD_SRC}

## Build our GCC toolchains
RUN git clone https://github.com/richfelker/musl-cross-make.git
WORKDIR ${BUILD_SRC}/musl-cross-make

COPY config.mak .
RUN make -j$(nproc) TARGET=${ARCH}-linux-musl
RUN make install TARGET=${ARCH}-linux-musl OUTPUT=${TC}/host_$(uname -m)/gcc_9_4_0_${ARCH}_musl

RUN ln -s ${TC}/host_$(uname -m) ${TC}/host

RUN make -j$(nproc) TARGET=i686-linux-musl
RUN make install TARGET=i686-linux-musl OUTPUT=${TC}/host_$(uname -m)/gcc_9_4_0_i386_musl

RUN cd ${TC}/host_$(uname -m)/gcc_9_4_0_${ARCH}_musl/bin && for x in *-linux-musl-*; do if [ -f "$x" ]; then n=$(echo $x | sed s/musl-//);  mv $x $n; fi; done
RUN cd ${TC}/host_$(uname -m)/gcc_9_4_0_i386_musl/bin && for x in *-linux-musl-*; do if [ -f "$x" ]; then n=$(echo $x | sed s/musl-//);  mv $x $n; fi; done
RUN cd ${TC}/host_$(uname -m)/gcc_9_4_0_i386_musl/bin && for x in i386-linux-*; do if [ -f "$x" ]; then n=$(echo $x | sed s/i386/i686/);  mv $x $n; fi; done


WORKDIR $TC/$ARCH

ENV ARCH_GCC_TC $TC/host/gcc_9_4_0_${ARCH}_musl/bin/$ARCH
ENV CC $ARCH_GCC_TC-linux-gcc 
ENV CXX $ARCH_GCC_TC-linux-g++
ENV AR $ARCH_GCC_TC-linux-ar
ENV NM $ARCH_GCC_TC-linux-nm
ENV RANLIB=$ARCH_GCC_TC-linux-ranlib

RUN git clone https://github.com/vvaltchev/gnu-efi-fork.git gnu-efi
RUN GNUEFI_VERSION=3.0.17 && \
    cd gnu-efi && \
    git checkout ${GNUEFI_VERSION} && \
    /scripts/gnuefi_patch.sh && \
    ARCH_EFI=$(/scripts/get_efi_arch.sh $ARCH) && \
    make ARCH=$ARCH_EFI prefix=$TC/host/gcc_9_4_0_${ARCH}_musl/bin/$ARCH-linux-

RUN ZLIB_VERSION=1.3.1 && \
    mkdir zlib && cd zlib && \
    curl -O https://www.zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz && \
    curl -O https://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz.asc && \
    gpg --keyserver pgp.surfnet.nl --recv-keys 783FCD8E58BCAFBA && \
    gpg --verify zlib-${ZLIB_VERSION}.tar.gz.asc && \
    tar --strip-components 1 -xvzf zlib-${ZLIB_VERSION}.tar.gz && \
    ./configure --prefix=$TCROOT/$ARCH/zlib/install --static && \
    make -j$(nproc) && \
    make install

RUN  BUSYBOX_VERSION=1.33.1 && \
  mkdir -p busybox && cd busybox && \
  curl -O https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 && \
  curl -O https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2.sha256 && \
  sha256sum -c busybox-${BUSYBOX_VERSION}.tar.bz2.sha256 && \
  tar --strip-components 1 -xvf busybox-${BUSYBOX_VERSION}.tar.bz2 && \
  cp -f /tilck/other/busybox.config $TC/$ARCH/busybox/.config && \
  CROSS_COMPILE=$TC/host/gcc_9_4_0_${ARCH}_musl/bin/$ARCH-linux- make && \
  cp -f /tilck/other/busybox.config $TC/$ARCH/busybox/.config

RUN MUSL_VERSION=1.2.4 && \
  mkdir musl && cd musl && \
  curl -O https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz && \
  curl -O https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz.asc && \
  tar --strip-components 1 -xvzf musl-${MUSL_VERSION}.tar.gz && \
  ./configure \
    --target=${ARCH} \
    --build=$(uname -m) \
    --disable-shared \
    --prefix=$TC/$ARCH/musl/install \
    --exec-prefix=$TC/$ARCH/musl/install \
    --enable-debug \
    --syslibdir=$TC/$ARCH/musl/install/lib \
    --enable-wrapper=gcc && \
  make && \
  make install


  
ENV CC ""
ENV CXX ""

WORKDIR $TCROOT/host/mtools
RUN  MTOOLS_VERSION=4.0.43 && \
  curl -O https://ftp.gnu.org/gnu/mtools/mtools-${MTOOLS_VERSION}.tar.bz2 && \
  curl -O https://ftp.gnu.org/gnu/mtools/mtools-${MTOOLS_VERSION}.tar.bz2.sig && \
  gpg --verify mtools-${MTOOLS_VERSION}.tar.bz2.sig && \
  tar --strip-components 1 -xvf mtools-${MTOOLS_VERSION}.tar.bz2 && \
  ./configure && \
  make -j$(nproc)

  # Maybe needs this, not sure...
  # cd $MUSL_INSTALL/bin && \
  # cp musl-gcc musl-g++ && \
  # sed -i 's/-${ARCH}-gcc/-${ARCH}-g++/' musl-g++ && \
  # cd $MUSL_INSTALL/include && \
  # ln -s /usr/include/linux . && \
  # ln -s /usr/include/asm-generic .


WORKDIR /tilck/

RUN ./scripts/cmake_run
RUN cd build && make
