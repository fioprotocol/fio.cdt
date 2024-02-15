#! /bin/bash

printf "\t=========== Building eosio.cdt ===========\n\n"

RED='\033[0;31m'
NC='\033[0m'
txtbld=$(tput bold)
bldred=${txtbld}$(tput setaf 1)
txtrst=$(tput sgr0)

export DISK_MIN=10
export TEMP_DIR="/tmp"
TEMP_DIR='/tmp'
DISK_MIN=10

# Use current directory's tmp directory if noexec is enabled for /tmp
if (mount | grep "/tmp " | grep --quiet noexec); then
  mkdir -p $SOURCE_DIR/tmp
  TEMP_DIR="${SOURCE_DIR}/tmp"
  rm -rf $SOURCE_DIR/tmp/*
else # noexec wasn't found
  TEMP_DIR="/tmp"
fi

unamestr=`uname`
OS_NAME=$(grep ^NAME /etc/os-release | cut -d'=' -f2 | sed 's/\"//gI' )
OS_VER=$(grep VERSION_ID /etc/os-release | cut -d'=' -f2 | sed 's/[^0-9\.]//gI' )
OS_MAJ=$(echo "${OS_VER}" | cut -d'.' -f1)
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
         ;;
      "Debian GNU/Linux")
         export ARCH="Debian"
         bash ./scripts/eosio_build_ubuntu.sh
	 ;;
      *)
         printf "\\n\\tUnsupported Linux Distribution. Exiting now.\\n\\n"
         exit 1
   esac
fi

CORES=`getconf _NPROCESSORS_ONLN`

#check submodules
if [ $(( $(git submodule status --recursive | grep -c "^[+\-]") )) -gt 0 ]; then
   printf "\\n\\tgit submodules are not up to date.\\n"
   printf "\\tPlease run the command 'git submodule update --init --recursive'.\\n"
   exit 1
fi

# Apply patch for ubuntu OSs
echo "Checking if ubuntu 20+ patch should be applied..."
echo "unamestr: ${unamestr}"
echo "OS Name: $OS_NAME"
echo "OS Major Release Nbr: $OS_MAJ"
if [[ "${unamestr}" != 'Darwin'  && "${OS_NAME}" == "Ubuntu" ]]; then
  if [[ "${OS_MAJ}" == "20" ]]; then
    echo "Applying patch for ubuntu 20+..."
    git apply ./patches/fio.cdt-lexer-source-a702a46.patch
  fi
fi

mkdir -p build
pushd build &> /dev/null

if [ -z "$CMAKE" ]; then
  CMAKE=$( command -v cmake )
fi

"$CMAKE" -DCMAKE_INSTALL_PREFIX=/usr/local/eosio.cdt ../
if [ $? -ne 0 ]; then
   exit -1;
fi
make -j${CORES}
if [ $? -ne 0 ]; then
   exit -1;
fi
popd &> /dev/null

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
