#!/bin/sh
set -e

if [ -z "${1}" ]; then
    echo "Usage: ${0} <OpenSSL Version>"
    exit 1
fi

############
# DOWNLOAD #
############

VERSION=${1}
ARCHIVE=openssl-${VERSION}.tar.gz

if [ ! -f ${ARCHIVE} ]; then
    echo "Downloading openssl ${VERSION}"
    curl "https://www.openssl.org/source/openssl-${VERSION}.tar.gz" > "${ARCHIVE}"
fi

###########
# COMPILE #
###########

ROOTDIR=${PWD}

export OUTDIR=output
export BUILDDIR=build
export IPHONEOS_DEPLOYMENT_TARGET="9.3"
export CC=$(xcrun -find -sdk iphoneos clang)

function build() {
    ARCH=${1}
    HOST=${2}
    SDKDIR=${3}
    LOG="../${ARCH}_build.log"
    echo "Building openssl for ${ARCH}..."

    WORKDIR=openssl_${ARCH}
    mkdir -p "${WORKDIR}"
    tar -xzf "../${ARCHIVE}" -C "${WORKDIR}" --strip-components 1
    cd "${WORKDIR}"

    for FILE in $(find ../../patches -name '*.patch'); do
        patch -p1 < ${FILE}
    done

    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SDKDIR} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"

    export LDFLAGS="-arch ${ARCH} -isysroot ${SDKDIR}"

    echo "+ Activating Static Engine for ${ARCH}"
    sed -ie 's/\"engine/\"dynamic-engine/' ./Configurations/15-ios.conf

    ./configure no-shared no-asm no-async no-hw --prefix=${ROOTDIR}/${OUTDIR}/${ARCH}/openssl ${HOST} > "${LOG}" 2>&1

    make -j $(sysctl -n hw.logicalcpu_max) >> "${LOG}" 2>&1
    make install_sw >> "${LOG}" 2>&1

    cd ../
}

rm -rf ${OUTDIR} ${BUILDDIR}
mkdir ${OUTDIR}
mkdir ${BUILDDIR}
cd ${BUILDDIR}

build armv7    ios-xcrun           $(xcrun --sdk iphoneos --show-sdk-path)
build arm64    ios64-xcrun         $(xcrun --sdk iphoneos --show-sdk-path)
build x86_64   iossimulator-xcrun  $(xcrun --sdk iphonesimulator --show-sdk-path)

cd ../

rm ${ARCHIVE}

mkdir -p ${OUTDIR}/combined/openssl/lib/pkgconfig/
mkdir -p ${OUTDIR}/combined/openssl/include/openssl/

lipo \
   -arch x86_64 ${OUTDIR}/x86_64/openssl/lib/libssl.a \
   -arch armv7 ${OUTDIR}/armv7/openssl/lib/libssl.a \
   -arch arm64 ${OUTDIR}/arm64/openssl/lib/libssl.a \
   -create -output ${OUTDIR}/combined/openssl/lib/libssl.a

lipo \
   -arch x86_64 ${OUTDIR}/x86_64/openssl/lib/libcrypto.a \
   -arch armv7 ${OUTDIR}/armv7/openssl/lib/libcrypto.a \
   -arch arm64 ${OUTDIR}/arm64/openssl/lib/libcrypto.a \
   -create -output ${OUTDIR}/combined/openssl/lib/libcrypto.a

cp -r ${OUTDIR}/x86_64/openssl/include/openssl/*.h ${OUTDIR}/combined/openssl/include/openssl/

###########
# PACKAGE #
###########

FWNAME=openssl

if [ -d ${FWNAME}.framework ]; then
    echo "Removing previous ${FWNAME}.framework copy"
    rm -rf ${FWNAME}.framework
fi

LIBTOOL_FLAGS="-no_warning_for_no_symbols -static"

echo "Creating ${FWNAME}.framework"
mkdir -p ${FWNAME}.framework/Headers/
libtool ${LIBTOOL_FLAGS} -o ${FWNAME}.framework/${FWNAME} ${OUTDIR}/combined/openssl/lib/libssl.a ${OUTDIR}/combined/openssl/lib/libcrypto.a
cp -r ${OUTDIR}/combined/openssl/include/${FWNAME}/*.h ${FWNAME}.framework/Headers/

rm -rf ${BUILDDIR}
# rm -rf ${OUTDIR}/armv7
# rm -rf ${OUTDIR}/arm64
# rm -rf ${OUTDIR}/x86_64

cp "Info.plist" ${FWNAME}.framework/Info.plist

set +e
check_bitcode=$(otool -arch arm64 -l ${FWNAME}.framework/${FWNAME} | grep __bitcode)
if [ -z "${check_bitcode}" ]
then
    echo "INFO: ${FWNAME}.framework doesn't contain Bitcode"
else
    echo "INFO: ${FWNAME}.framework contains Bitcode"
fi
