#!/usr/bin/env bash

# Execution helpers; necessary for BATS testing and log output in buildkite
function execute() {
  $VERBOSE && echo "--- Executing: $@"
  $DRYRUN || "$@"
}

function execute-quiet() {
  $VERBOSE && echo "--- Executing: $@ &>/dev/null"
  $DRYRUN || "$@" &>/dev/null
}

function execute-always() {
  ORIGINAL_DRYRUN=$DRYRUN
  DRYRUN=false
  execute "$@"
  DRYRUN=$ORIGINAL_DRYRUN
}

function execute-without-verbose() {
  ORIGINAL_VERBOSE=$VERBOSE
  VERBOSE=false
  execute "$@"
  VERBOSE=$ORIGINAL_VERBOSE
}

function pushd () {
    command pushd "$@" &> /dev/null
}

function popd () {
    command popd "$@" &> /dev/null
}

function set-system-vars() {
    if [[ $ARCH == "Darwin" ]]; then
        export OS_VER=$(sw_vers -productVersion)
        export OS_MAJ=$(echo "${OS_VER}" | cut -d'.' -f1)
        export OS_MIN=$(echo "${OS_VER}" | cut -d'.' -f2)
        export OS_PATCH=$(echo "${OS_VER}" | cut -d'.' -f3)
        export MEM_GIG=$(bc <<< "($(sysctl -in hw.memsize) / 1024000000)")
        export DISK_INSTALL=$(df -h . | tail -1 | tr -s ' ' | cut -d\  -f1 || cut -d' ' -f1)
        export blksize=$(df . | head -1 | awk '{print $2}' | cut -d- -f1)
        export gbfactor=$(( 1073741824 / blksize ))
        export total_blks=$(df . | tail -1 | awk '{print $2}')
        export avail_blks=$(df . | tail -1 | awk '{print $4}')
        export DISK_TOTAL=$((total_blks / gbfactor ))
        export DISK_AVAIL=$((avail_blks / gbfactor ))
    else
        export DISK_INSTALL=$( df -h . | tail -1 | tr -s ' ' | cut -d\  -f1 )
        export DISK_TOTAL_KB=$( df . | tail -1 | awk '{print $2}' )
        export DISK_AVAIL_KB=$( df . | tail -1 | awk '{print $4}' )
        export MEM_GIG=$(( ( ( $(cat /proc/meminfo | grep MemTotal | awk '{print $2}') / 1000 ) / 1000 ) ))
        export DISK_TOTAL=$(( DISK_TOTAL_KB / 1048576 ))
        export DISK_AVAIL=$(( DISK_AVAIL_KB / 1048576 ))
    fi
    export CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu)
    export JOBS=${JOBS:-$(( MEM_GIG > CPU_CORES ? CPU_CORES : MEM_GIG ))}
}

function setup() {
    if $VERBOSE; then
        echo "VERBOSE: ${VERBOSE}"
        echo "TEMP_DIR: ${TEMP_DIR}"
        echo "FIO_CDT_APTS_DIR: ${FIO_CDT_APTS_DIR}"
    fi
    ensure-temp
    execute mkdir -p ${FIO_CDT_APTS_DIR}
}

function ensure-temp() {
    # Use current directory's tmp directory if noexec is enabled for /tmp
    if (mount | grep "${TEMP_DIR} " | grep --quiet noexec); then
        mkdir -p $REPO_ROOT/tmp
        export TEMP_DIR="${REPO_ROOT}/tmp"
        rm -rf $REPO_ROOT/tmp/*
    fi
    execute-always mkdir -p ${TEMP_DIR}
}

function is-cdt-built() {
    if [[ -d ${BUILD_DIR} && -x ${BUILD_DIR}/bin/eosio-cpp  ]]; then
       cdt_version=$(${BUILD_DIR}/bin/eosio-cpp -version | awk '{print $4}')
        if [[ $cdt_version =~ 1.5.0 ]]; then
            return
        fi
    fi
    false
}

function is-cdt-installed() {
    if [[ -d ${FIO_CDT_INSTALL_DIR}/eosio.cdt && -x ${FIO_CDT_INSTALL_DIR}/eosio.cdt/bin/eosio-cpp  ]]; then
       cdt_version=$(${FIO_CDT_INSTALL_DIR}/eosio.cdt/bin/eosio-cpp -version | awk '{print $4}')
        if [[ $cdt_version =~ 1.5.0 ]]; then
            return
        fi
    fi
    false
}

OPENSSL_NAME=openssl-1.1.1w
OPENSSL_TAG_NAME=OpenSSL_1_1_1w
OPENSSL_ROOT=/usr/local/ssl
# Check openssl root (install dir) for openssl, otherwise, download, build and install
function ensure-openssl() {
    if ! $DO_OPENSSL; then
        # Use set -e to exit on error, unset it before moving on
        set -e
        which openssl &>/dev/null || (
            echo "${COLOR_RED}ERROR: Unable to find openssl! Set DO_OPENSSL=true to install it. ${COLOR_NC}"
            false
        )
        set -e
    fi

    if $DO_OPENSSL; then
        echo "${COLOR_CYAN}[Ensuring OpenSSL support]${COLOR_NC}"
        if ! is-openssl-installed; then
            # Check tmp dir for previous openssl build
            if ! is-openssl-built; then
                build-openssl
            fi
            install-openssl
            echo " - OpenSSL 1.1.1w successfully installed @ ${OPENSSL_ROOT}"
            echo ""
        else
            echo " - OpenSSL 1.1.1w found @ ${OPENSSL_ROOT}"
            echo ""
        fi
        do-openssl-postinstall
    fi
}

# Check previous build of openssl, incl version
# export LD_LIBRARY_PATH=/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
function is-openssl-built() {
    if [[ -x ${TEMP_DIR}/${OPENSSL_NAME}/apps/openssl ]]; then
        TMP_LD_LIB_PATH=${LD_LIBRARY_PATH}
        openssl_version=$(LD_LIBRARY_PATH=${TEMP_DIR}/${OPENSSL_NAME} ${TEMP_DIR}/${OPENSSL_NAME}/apps/openssl version | awk '{print $2}')
        if [[ $openssl_version =~ 1.1.1 ]]; then
            return
        fi
    fi
    false
}

# Check previous install of openssl, incl version
function is-openssl-installed() {
    if [[ -x ${OPENSSL_ROOT}/bin/openssl ]]; then
        TMP_LIB_PATH=${LD_LIBRARY_PATH}
        openssl_version=$(LD_LIBRARY_PATH=${OPENSSL_ROOT}/lib ${OPENSSL_ROOT}/bin/openssl version | awk '{print $2}')
        if [[ $openssl_version =~ 1.1.1 ]]; then
            return
        fi
    fi
    false
}

function clean-openssl() {
    execute bash -c "rm -f ${TEMP_DIR}/${OPENSSL_NAME}.tar.gz \
        && rm -rf ${TEMP_DIR}/${OPENSSL_NAME}"
}

# Clone openssl
function clone-openssl() {
    execute bash -c "cd ${TEMP_DIR} \
        && git clone https://github.com/openssl/openssl.git ${OPENSSL_NAME} \
        && cd ${OPENSSL_NAME} && git checkout ${OPENSSL_TAG_NAME}"
}

# Download openssl
function download-openssl() {
    execute bash -c "cd ${TEMP_DIR} \
        && curl -LO https://github.com/openssl/openssl/releases/download/${OPENSSL_TAG_NAME}/${OPENSSL_NAME}.tar.gz \
        && tar -xzf openssl-1.1.1w.tar.gz"
}

# Build openssl in temp dir
function build-openssl() {
    echo "Building openssl..."
    clean-openssl
    download-openssl
    execute bash -c "cd ${TEMP_DIR}/${OPENSSL_NAME} \
        && ./config --prefix=${OPENSSL_ROOT} \
        && make -j${JOBS}"
}

# Install openssl
function install-openssl() {
    echo "Installing openssl..."
    execute bash -c "cd ${TEMP_DIR}/${OPENSSL_NAME} \
        && sudo make install"
}

function do-openssl-postinstall() {
    sudo rm -f /usr/local/lib/libcrypto.a
    sudo rm -f /usr/local/lib/libcrypto.so
    sudo rm -f /usr/local/lib/libssl.a
    sudo rm -f /usr/local/lib/libssl.so
    sudo rm -f /usr/local/lib/libcrypto.so.1.1
    sudo rm -f /usr/local/lib/libssl.so.1.1

    sudo ln -s ${OPENSSL_ROOT}/lib/libcrypto.a /usr/local/lib
    sudo ln -s ${OPENSSL_ROOT}/lib/libcrypto.so /usr/local/lib
    sudo ln -s ${OPENSSL_ROOT}/lib/libssl.a /usr/local/lib
    sudo ln -s ${OPENSSL_ROOT}/lib/libssl.so /usr/local/lib
    sudo ln -s ${OPENSSL_ROOT}/lib/libcrypto.so.1.1 /usr/local/lib
    sudo ln -s ${OPENSSL_ROOT}/lib/libssl.so.1.1 /usr/local/lib

    sudo ldconfig /usr/local/lib
    export LD_LIBRARY_PATH=/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export OPENSSL_ROOT_DIR=${OPENSSL_ROOT}
    export PKG_CONFIG_PATH=${OPENSSL_ROOT}/lib/pkgconfig
}

# Check cmake env var definition, otherwise, build if necessary, install and set env
function ensure-cmake() {
    echo
    echo "${COLOR_CYAN}[Ensuring CMAKE installation]${COLOR_NC}"
    if [[ ! -x "${CMAKE}" ]]; then
        if ! is-cmake-built; then
            build-cmake
        fi
        install-cmake
        export APTS_DIR=${CMAKE_INSTALL_DIR}
        export CMAKE="${CMAKE_INSTALL_DIR}/bin/cmake"
        echo " - CMAKE successfully installed @ ${CMAKE}"
        echo ""
    else
        echo " - CMAKE found @ ${CMAKE}"
        echo ""
    fi
}

# Check previous build of cmake, incl version
function is-cmake-built() {
    if [[ -x ${TEMP_DIR}/cmake-${CMAKE_VERSION}/build/bin/cmake ]]; then
        cmake_version=$(${TEMP_DIR}/cmake-${CMAKE_VERSION}/build/bin/cmake --version | grep version | awk '{print $3}')
        if [[ $cmake_version =~ 3.2 ]]; then
            return
        fi
    fi
    false
}

# Download and build cmake
function build-cmake() {
    echo "Building cmake..."
    execute bash -c "cd $TEMP_DIR \
        && rm -rf cmake-${CMAKE_VERSION} \
        && curl -LO https://cmake.org/files/v${CMAKE_VERSION_MAJOR}.${CMAKE_VERSION_MINOR}/cmake-${CMAKE_VERSION}.tar.gz \
        && tar -xzf cmake-${CMAKE_VERSION}.tar.gz \
        && rm -f cmake-${CMAKE_VERSION}.tar.gz \
        && cd cmake-${CMAKE_VERSION} \
        && mkdir build && cd build \
        && ../bootstrap --prefix=${CMAKE_INSTALL_DIR} \
        && make -j${JOBS}"
}

function install-cmake() {
    echo "Installing cmake..."
    execute bash -c "cd $TEMP_DIR/cmake-${CMAKE_VERSION} \
        && cd build \
        && make install"
}

function apply-clang-ubuntu20-patches() {
    echo "Applying lexer-source redundant move patch for ubuntu 20+..."
    $(git apply --check ./patches/fio.cdt_lexer-source_a702a46.patch &>/dev/null) && git apply ./patches/fio.cdt_lexer-source_a702a46.patch
}

function apply-clang-ubuntu22-patches() {
    apply-clang-ubuntu20-patches

    echo "Applying limits patch to fio.cdt eosio-llvm submodule for ubuntu 22..."
    pushd eosio_llvm
    $(git apply --check ../patches/fio.cdt_eosio-llvm_limits.patch &>/dev/null) && git apply ../patches/fio.cdt_eosio-llvm_limits.patch
    popd
}
