OS_NAME=$(grep ^NAME /etc/os-release | cut -d'=' -f2 | sed 's/\"//gI')
OS_VER=$(grep VERSION_ID /etc/os-release | cut -d'=' -f2 | sed 's/[^0-9\.]//gI')
OS_MAJ=$(echo "${OS_VER}" | cut -d'.' -f1)
OS_MIN=$(echo "${OS_VER}" | cut -d'.' -f2)

MEM_MEG=$(free -m | sed -n 2p | tr -s ' ' | cut -d\  -f2 || cut -d' ' -f2)
CPU_SPEED=$(lscpu | grep -m1 "MHz" | tr -s ' ' | cut -d\  -f3 || cut -d' ' -f3 | cut -d'.' -f1)
CPU_CORE=$(lscpu | grep "^CPU(s)" | tr -s ' ' | cut -d\  -f2 || cut -d' ' -f2)

MEM_GIG=$((((MEM_MEG / 1000) / 2)))
JOBS=$((MEM_GIG > CPU_CORE ? CPU_CORE : MEM_GIG))

DISK_INSTALL=$(df -h . | tail -1 | tr -s ' ' | cut -d\  -f1 || cut -d' ' -f1)
DISK_TOTAL_KB=$(df . | tail -1 | awk '{print $2}')
DISK_AVAIL_KB=$(df . | tail -1 | awk '{print $4}')
DISK_TOTAL=$((DISK_TOTAL_KB / 1048576))
DISK_AVAIL=$((DISK_AVAIL_KB / 1048576))

printf "\\nOS name: %s\\n" "${OS_NAME}"
printf "OS Version: %s\\n" "${OS_VER}"
printf "CPU speed: %sMhz\\n" "${CPU_SPEED}"
printf "CPU cores: %s\\n" "${CPU_CORE}"
printf "Physical Memory: %s Mgb\\n" "${MEM_MEG}"
printf "Disk install: %s\\n" "${DISK_INSTALL}"
printf "Disk space total: %sG\\n" "${DISK_TOTAL%.*}"
printf "Disk space available: %sG\\n" "${DISK_AVAIL%.*}"

if [ "${MEM_MEG}" -lt 7000 ]; then
    printf "Your system must have 7 or more Gigabytes of physical memory installed.\\n"
    printf "Exiting now.\\n"
    exit 1
fi

case "${OS_NAME}" in
"Linux Mint")
    if [ "${OS_MAJ}" -lt 18 ]; then
        printf "You must be running Linux Mint 18.x or higher to install EOSIO.\\n"
        printf "Exiting now.\\n"
        exit 1
    fi
    ;;
"Ubuntu")
    if [ "${OS_MAJ}" -lt 16 ]; then
        printf "You must be running Ubuntu 16.04.x or higher to install EOSIO.\\n"
        printf "Exiting now.\\n"
        exit 1
    fi
    ;;
esac

if [ "${DISK_AVAIL%.*}" -lt "${DISK_MIN}" ]; then
    printf "You must have at least %sGB of available storage to install EOSIO.\\n" "${DISK_MIN}"
    printf "Exiting now.\\n"
    exit 1
fi

#DEP_ARRAY=(clang-4.0 lldb-4.0 libclang-4.0-dev cmake make automake libbz2-dev libssl-dev \
DEP_ARRAY=(make automake libbz2-dev libssl-dev
    libgmp3-dev autotools-dev build-essential libicu-dev python2.7-dev python3-dev
    autoconf libtool curl zlib1g-dev doxygen graphviz)
COUNT=1
DISPLAY=""
DEP=""

if [[ -z ${CMAKE} ]]; then
    DEP_ARRAY+=(cmake)
fi

if [[ "${ENABLE_CODE_COVERAGE}" == true ]]; then
    DEP_ARRAY+=(lcov)
fi

printf "\\nChecking for installed dependencies.\\n\\n"

for ((i = 0; i < ${#DEP_ARRAY[@]}; i++)); do
    pkg=$(dpkg -s "${DEP_ARRAY[$i]}" 2>/dev/null | grep Status | tr -s ' ' | cut -d\  -f4)
    if [ -z "$pkg" ]; then
        DEP=$DEP" ${DEP_ARRAY[$i]} "
        DISPLAY="${DISPLAY}${COUNT}. ${DEP_ARRAY[$i]}\\n\\t"
        printf "Package %s ${bldred} NOT ${txtrst} found.\\n" "${DEP_ARRAY[$i]}"
        ((COUNT++))
    else
        printf "Package %s found.\\n" "${DEP_ARRAY[$i]}"
        continue
    fi
done

if [ "${COUNT}" -gt 1 ]; then
    printf "\\nThe following dependencies are required to install EOSIO.\\n"
    printf "\\n${DISPLAY}\\n\\n"
    printf "\\tDo you wish to install these packages?\\n"
    select yn in "Yes" "No"; do
        case $yn in [Yy]*)
            printf "\\n\\nInstalling dependencies\\n\\n"
            sudo apt-get update
            if ! sudo apt-get -y install ${DEP}; then
                printf "\\nDPKG dependency failed.\\n"
                printf "\\nExiting now.\\n"
                exit 1
            else
                printf "\\nDPKG dependencies installed successfully.\\n"
            fi
            break
            ;;
        [Nn]*)
            echo "User aborting installation of required dependencies, Exiting now."
            exit 1
            ;;
        *) echo "Please type 1 for yes or 2 for no." ;;
        esac
    done
else
    printf "\\nNo required dpkg dependencies to install.\\n"
fi

function print_instructions() {
    printf '\\nexport PATH=${HOME}/opt/mongodb/bin:$PATH\n'
    printf "%s -f %s &\\n" "$(command -v mongod)" "${MONGOD_CONF}"
    printf "cd %s; make test\\n\\n" "${BUILD_DIR}"
    return 0
}
