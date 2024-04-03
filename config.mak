COMMON_CONFIG += CC="gcc -static --static" CXX="g++ -static --static"
COMMON_CONFIG += --disable-nls --disable-shared --enable-languages=c,c++ --with-sysroot --disable-werror

MUSL_CONFIG += LDFLAGS="-s"
MUSL_CONFIG += --disable-shared --enable-debug --syslibdir=/lib