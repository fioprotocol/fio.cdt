#!/usr/bin/env bash

printf "\t=========== Building eosio.cdt ===========\n"

RED='\033[0;31m'
NC='\033[0m'
txtbld=$(tput bold)
bldred=${txtbld}$(tput setaf 1)
txtrst=$(tput sgr0)

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export REPO_ROOT="${SCRIPT_DIR}"
export BUILD_DIR="${REPO_ROOT}/build"

export DISK_MIN=5
export TEMP_DIR="/tmp"
TEMP_DIR='/tmp'
DISK_MIN=5

# Use current directory's tmp directory if noexec is enabled for /tmp
if (mount | grep "/tmp " | grep --quiet noexec); then
   mkdir -p $SOURCE_DIR/tmp
   TEMP_DIR="${SOURCE_DIR}/tmp"
   rm -rf $SOURCE_DIR/tmp/*
fi

. ./.build_vars
. ./scripts/utils.sh

# Set OS and associated system vars
set-system-vars

# CMAKE Installation
if [ -z "$CMAKE" ]; then
   CMAKE=$(command -v cmake)
fi
if [[ $ARCH == "Linux" ]]; then
   export CMAKE=${CMAKE:-${EOSIO_INSTALL_DIR}/bin/cmake}
   ensure-cmake
fi

unamestr=$(uname)
if [[ "${unamestr}" == 'Darwin' ]]; then
   BOOST=/usr/local
   CXX_COMPILER=g++
   export ARCH="Darwin"
   bash ./scripts/eosio_build_darwin.sh
else
   case "$OS_NAME" in
   "Amazon Linux AMI")
      export ARCH="Amazon Linux AMI"
      bash ./scripts/eosio_build_amazon.sh
      ;;
   "CentOS Linux")
      export ARCH="Centos"
      export CMAKE=${HOME}/opt/cmake/bin/cmake
      bash ./scripts/eosio_build_centos.sh
      ;;
   "elementary OS")
      export ARCH="elementary OS"
      bash ./scripts/eosio_build_ubuntu.sh
      ;;
   "Fedora")
      export ARCH="Fedora"
      bash ./scripts/eosio_build_fedora.sh
      ;;
   "Linux Mint")
      export ARCH="Linux Mint"
      bash ./scripts/eosio_build_ubuntu.sh
      ;;
   "Ubuntu")
      export ARCH="Ubuntu"
      bash ./scripts/eosio_build_ubuntu.sh
      if [[ $? -ne 0 ]]; then
         exit 1
      fi
      ;;
   "Debian GNU/Linux")
      export ARCH="Debian"
      bash ./scripts/eosio_build_ubuntu.sh
      ;;
   *)
      printf "\\n\\tUnsupported Linux Distribution. Exiting now.\\n\\n"
      exit 1
      ;;
   esac
fi

#check submodules
if [ $(($(git submodule status --recursive | grep -c "^[+\-]"))) -gt 0 ]; then
   printf "\\n\\tgit submodules are not up to date.\\n"
   printf "\\tPlease run the command 'git submodule update --init --recursive'.\\n"
   exit 1
fi

# Apply patch for ubuntu 20+
echo
if [[ "${unamestr}" != 'Darwin' && "${OS_NAME}" == "Ubuntu" ]]; then
   if [[ "${OS_MAJ}" == "20" || "${OS_MAJ}" == "22" ]]; then
      echo "Applying patch for ubuntu 20+..."
      git apply ./patches/fio.cdt_lexer-source_a702a46.patch
   fi
   if [[ "${OS_MAJ}" == "22" ]]; then
      echo "Applying patch for ubuntu 22..."
      pushd eosio_llvm
      git apply ../patches/fio.cdt_eosio-llvm_limits.patch
      popd
   fi
fi

mkdir -p build
pushd build &>/dev/null

"$CMAKE" -DCMAKE_INSTALL_PREFIX=/usr/local/eosio.cdt ../
if [ $? -ne 0 ]; then
   exit -1
fi
make -j${JOBS}
if [ $? -ne 0 ]; then
   exit -1
fi
popd &>/dev/null

printf "\n${bldred}\t      ___           ___           ___                       ___\n"
printf "\t     /  /\\         /  /\\         /  /\\        ___          /  /\\ \n"
printf "\t    /  /:/_       /  /::\\       /  /:/_      /  /\\        /  /::\\ \n"
printf "\t   /  /:/ /\\     /  /:/\\:\\     /  /:/ /\\    /  /:/       /  /:/\\:\\ \n"
printf "\t  /  /:/ /:/_   /  /:/  \\:\\   /  /:/ /::\\  /__/::\\      /  /:/  \\:\\ \n"
printf "\t /__/:/ /:/ /\\ /__/:/ \\__\\:\\ /__/:/ /:/\\:\\ \\__\\/\\:\\__  /__/:/ \\__\\:\\ \n"
printf "\t \\  \\:\\/:/ /:/ \\  \\:\\ /  /:/ \\  \\:\\/:/~/:/    \\  \\:\\/\\ \\  \\:\\ /  /:/ \n"
printf "\t  \\  \\::/ /:/   \\  \\:\\  /:/   \\  \\::/ /:/      \\__\\::/  \\  \\:\\  /:/ \n"
printf "\t   \\  \\:\\/:/     \\  \\:\\/:/     \\__\\/ /:/       /__/:/    \\  \\:\\/:/ \n"
printf "\t    \\  \\::/       \\  \\::/        /__/:/        \\__\\/      \\  \\::/ \n"
printf "\t     \\__\\/         \\__\\/         \\__\\/                     \\__\\/ \n${txtrst}"

printf "\\tFor more information:\\n"
printf "\\tEOSIO website: https://eos.io\\n"
