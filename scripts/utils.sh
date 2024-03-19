#!/usr/bin/env bash

function ensure-cmake() {
    echo
    echo "${COLOR_CYAN}[Ensuring CMAKE installation]${COLOR_NC}"
    if [[ ! -e "${CMAKE}" ]]; then
        execute bash -c "mkdir -p $SRC_DIR \
            && cd $SRC_DIR \
            && curl -LO https://cmake.org/files/v${CMAKE_VERSION_MAJOR}.${CMAKE_VERSION_MINOR}/cmake-${CMAKE_VERSION}.tar.gz \
            && tar -xzf cmake-${CMAKE_VERSION}.tar.gz \
            && cd cmake-${CMAKE_VERSION} \
            && ./bootstrap --prefix=${CMAKE_INSTALL_DIR} \
            && make -j${JOBS} \
            && mkdir -p ${CMAKE_INSTALL_DIR} \
            && make install \
            && cd .. \
            && rm -f cmake-${CMAKE_VERSION}.tar.gz"
        [[ -z "${CMAKE}" ]] && export CMAKE="${BIN_DIR}/cmake"
        echo " - CMAKE successfully installed @ ${CMAKE}"
        echo ""
    else
        echo " - CMAKE found @ ${CMAKE}."
        echo ""
    fi
}

function execute() {
  $VERBOSE && echo "--- Executing: $@"
  $DRYRUN || "$@"
}

function set-system-vars() {
    [[ -z "${ARCH}" ]] && export ARCH=$(uname)
    if [[ -z "${NAME}" ]]; then
        if [[ $ARCH == "Linux" && -e /etc/os-release ]]; then
            . /etc/os-release
            export OS_NAME=${NAME}
            export OS_VER=${VERSION}
            export OS_MAJ=$(echo "${OS_VER}" | cut -d'.' -f1)
            export OS_MIN=$(echo "${OS_VER}" | cut -d'.' -f2)
            export OS_PATCH=$(echo "${OS_VER}" | cut -d'.' -f3)
        elif [[ $ARCH == "Darwin" ]]; then
            export NAME=$(sw_vers -productName)
        fi
    fi

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
    export JOBS=${JOBS:-$(( MEM_GIG > CPU_CORES ? CPU_CORES : $(getconf _NPROCESSORS_ONLN) ))}
}

function apply-clang-ubuntu20-patches() {
    echo "Applying lexer-source redundant move patch for ubuntu 20+..."
    $(git apply --check ./patches/fio.cdt_lexer-source_a702a46.patch &>/dev/null) && git apply ./patches/fio.cdt_lexer-source_a702a46.patch
}

function apply-clang-ubuntu22-patches() {
    apply-clang-ubuntu20-patches

    echo "Applying limits patch to fio.cdt eosio-llvm submodule for ubuntu 22..."
    pushd eosio_llvm > /dev/null
    $(git apply --check ../patches/fio.cdt_eosio-llvm_limits.patch &>/dev/null) && git apply ../patches/fio.cdt_eosio-llvm_limits.patch
    popd > /dev/null
}
