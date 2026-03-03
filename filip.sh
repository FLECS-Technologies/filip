#!/bin/bash
# Copyright 2021-2023 FLECS Technologies GmbH
#
# Licensed under the Apache License, Version 2.  (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

cat <<'EOF' > /tmp/filip.sh
#!/bin/bash
ME="FILiP"
SCRIPTNAME=`readlink -f ${0}`
ARGS="$*"
STDOUT=/dev/null
STDERR=/dev/null

BASE_PROTO=https
BASE_URL=dl.flecs.tech

print_usage() {
  echo "Usage: ${SCRIPTNAME}" [options]
  echo
  echo "  -d --debug                 print additional debug messages"
  echo "  -y --yes                   assume yes as answer to all prompts (unattended mode)"
  echo "     --no-banner             do not print ${ME} banner"
  echo "     --no-welcome            do not print welcome message"
  echo "     --core-version <ver>    Install version <ver> of flecs-core instead of the latest version"
  echo "     --webapp-version <ver>  Install version <ver> of flecs-webapp instead of the latest version"
  echo "     --help                  print this help and exit"
}

# some log functions...
log_debug() {
  if [ ! -z "${LOG_DEBUG}" ]; then
    while true; do
      case ${1} in
        -n)
          local ECHO_ARGS="-n"
          shift
          ;;
        -q)
          local NO_PREFIX=true
          shift
          ;;
        *)
          break;;
      esac
    done
    if [ -z "${NO_PREFIX}" ]; then
      echo ${ECHO_ARGS} "*** Debug: $@"
    else
      echo ${ECHO_ARGS} "$@"
    fi
  fi
}
log_info() {
  while true; do
    case ${1} in
      -n)
        local ECHO_ARGS="-n"
        shift
        ;;
      -q)
        local NO_PREFIX=true
        shift
        ;;
      *)
        break;;
    esac
  done
  if [ -z "${NO_PREFIX}" ]; then
    echo ${ECHO_ARGS} "Info: $@"
  else
    echo ${ECHO_ARGS} "$@"
  fi
}
log_warning() {
  if [ -z "$@" ]; then
    echo 1>&2
  else
    echo "Warning: $@" 1>&2
  fi
}
log_error() {
  while true; do
    case ${1} in
      -n)
        local ECHO_ARGS="-n"
        shift
        ;;
      -q)
        local NO_PREFIX=true
        shift
        ;;
      *)
        break;;
    esac
  done
  if [ -z "${NO_PREFIX}" ]; then
    echo ${ECHO_ARGS} "Error: $@" 1>&2
  else
    echo ${ECHO_ARGS} "$@" 1>&2
  fi
}
# log_fatal will terminate with exit code 1 after logging
log_fatal() {
  if [ -z "$@" ]; then
    echo 1>&2
  else
    echo "Fatal: $@. ${ME} out." 1>&2
  fi
  exit 1
}
# internal_error should *only* be called if guaranteed preconditions are not met
internal_error() {
  log_error "Internal error: $@" 1>&2
  exit -1
}

# print a message and wait for user input. does nothing in unattended mode
require_stdin() {
  if ! (exec >/dev/null 2>&1 3</dev/tty); then
    log_fatal "User input required but no tty allocated."
  fi
}
confirm() {
  if [ -z "${ASSUME_YES}" ]; then
    require_stdin
    read -s -p "$@"
  fi
}
confirm_yn() {
  if [ -z "${ASSUME_YES}" ]; then
    require_stdin
    while true; do
      read -p "$*? [y/n]: " input
      case ${input} in
        [yY]*)
          return 0
          ;;
        [nN]*)
          return 1
          ;;
      esac
    done
  else
    return 0
  fi
}

# compare two version numbers in a robust way
cmp_less() {
  if [ -z "${1}" ] || [ -z "${2}" ]; then
    internal_error "attempt to compare with empty value: ${1} < ${2}"
  fi
  if [ "${1}" = "${2}" ]; then
    return 1
  fi
  local RES=`${SORT} -t . -k 1,1n -k 2,2n -k 3,3n <(echo "${1}") <(echo "${2}") | ${HEAD} -n1`
  if [ "${RES}" = "${1}" ]; then
    return 0
  fi
  return 1
}

parse_args() {
  while [ ! -z "${1}" ]; do
    case ${1} in
      -d|--debug)
        LOG_DEBUG=1
        STDOUT=/dev/stdout
        STDERR=/dev/stderr
        log_debug "Running with debug output"
        ;;
      -y|--yes)
        ASSUME_YES=1
        ;;
      --no-welcome)
        NO_WELCOME=1
        ;;
      --no-banner)
        NO_BANNER=1
        ;;
      --dev)
        BASE_URL=dl-dev.flecs.tech
        DEV_MODE=1
        ;;
      --core-version)
        VERSION_CORE=${2}
        if [ -z "${VERSION_CORE}" ]; then
          log_error "argument --core-version requires a value"
          log_error -q
          print_usage
          exit 1
        fi
        ;;
      --webapp-version)
        VERSION_WEBAPP=${2}
        if [ -z "${VERSION_WEBAPP}" ]; then
          log_error "argument --webapp-version requires a value"
          log_error -q
          print_usage
          exit 1
        fi
        ;;
      --filip-version)
        VERSION_FILIP=${2}
        if [ -z "${VERSION_FILIP}" ]; then
          log_error "argument --filip-version requires a value"
          log_error -q
          print_usage
          exit 1
        fi
        ;;
      --whitelabel)
        WHITELABEL=${2}
        if [ -z "${WHITELABEL}" ]; then
          log_error "argument --whitelabel requires a value"
          log_error -q
          print_usage
          exit 1
        fi
        ;;
      --help)
        print_usage
        exit 0
        ;;
    esac
    shift
  done
}

welcome() {
  if [ -z "${NO_WELCOME}" ]; then
    # print welcome message and wait for confirmation, if not unattended
    log_info -n "${ME} is about to install FLECS for ${ARCH} on"
    if [ ! -z "${NAME}" ]; then
      log_info -n -q " ${NAME}"
      [ ! -z "${OS_VERSION}" ] && log_info -n -q " ${OS_VERSION}"
      [ ! -z "${CODENAME}" ] && log_info -n -q " (${CODENAME})"
      log_info -q
    else
      log_info -q " your device"
    fi
    confirm "Press enter to begin installation or Ctrl-C to cancel."
  fi
}

# tries to detect presence of a program by running its "--help" function
# and using `which` (not available on all platforms) as fallback
have_program() {
  if ${1} --help >/dev/null 2>&1; then
    echo ${1}
  else
    which ${1} 2>/dev/null
  fi
}
# wrapper around have_program that declares a global variable named like the
# program in uppercase (e.g. CURL=... for curl)
have() {
  log_debug -n "Looking for ${1}..."
  local TOOL=${1^^}
  local TOOL=${TOOL//-/_}
  local TOOL=${TOOL//./_}
  if [ -z "${!TOOL}" ]; then
    declare -g ${TOOL}=`have_program ${1}`
  fi
  [ ! -z "${!TOOL}" ] && log_debug -q " found" || (log_debug -q " not found" && return 1)
}

# wrapper for apt-get update
apt_update() {
  log_debug "apt-get update"
  if [ -z "${APT_GET}" ] || ! ${APT_GET} update 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
  return 0
}
# wrapper for apt-get install
apt_install() {
  log_debug "apt-get install $@"
  if [ -z "${APT_GET}" ] || ! ${APT_GET} -y install --reinstall --allow-downgrades $@ 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
  return 0
}
# wrapper for pacman -Syu
pacman_update() {
  if [ -z "${PACMAN}" ] || ! ${PACMAN} -Syu --noconfirm 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
  return 0
}
# wrapper for pacman -S
pacman_install() {
  if [ -z "${PACMAN}" ] || ! ${PACMAN} -S --needed --noconfirm $@ 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
  return 0
}
# wrapper for yum update
yum_update() {
  if [ -z "${YUM}" ] || ! ${YUM} update --assumeno 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
  return 0
}
# wrapper for yum install
yum_install() {
  if [ -z "${YUM}" ] || ! ${YUM} install --assumeyes 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
  return 0
}

can_install_program() {
  if [ -z "${OS_LIKE}" ]; then
    if [ ! -z "${APT_GET}" ] || [ ! -z "${PACMAN}" ] || [ ! -z "${YUM}" ]; then
      return 0
    fi
  else
    case ${OS_LIKE} in
      debian|fedora|arch)
        return 0
        ;;
    esac
  fi
  return 1
}
install_program() {
  # Before OS detection, we need to guess how to install programs
  if [ -z "${OS_LIKE}" ]; then
    if apt_update && apt_install $@; then
      return 0;
    elif pacman_update && pacman_install $@; then
      return 0
    elif yum_update && yum_install $@; then
      return 0
    fi
  # Afterwards we know how to do it
  else
    case ${OS_LIKE} in
      debian)
        if apt_update && apt_install $@; then
          return 0
        fi
        ;;
      fedora)
        if yum_update && yum_install $@; then
          return 0
        fi
        ;;
      arch)
        if yum_update && yum_install $@; then
          return 0
        fi
        ;;
    esac
  fi
  return 1
}

# detect which tools are available on the system
detect_tools() {
  log_debug "Checking availability of required tools..."
  TOOLS=(apt-get chkconfig curl docker grep head ldconfig opkg pacman rpm sed service sort systemctl uname update-rc.d wget yum)
  for TOOL in ${TOOLS[@]}; do
    have ${TOOL}
  done
}
verify_tool_alternatives() {
  TOOL_ALTERNATIVES=("$@")
  for TOOL in "${TOOL_ALTERNATIVES[@]}"; do
    REQ=${TOOL^^}
    REQ=${REQ//-/_}
    if [ ! -z "${!REQ}" ]; then
      local FOUND="true"
      log_debug "Found alternative ${TOOL} for ${TOOL_ALTERNATIVES[@]}"
    fi
  done
  if [ -z "${FOUND}" ]; then
    return 1
  fi
  return 0
}
# quit if required tools are missing
verify_tools() {
  INSTALL_PACKAGES=""
  log_debug "Verifying presence of required basic tools..."
  REQUIRED_TOOLS=(head sort)
  for TOOL in ${REQUIRED_TOOLS[@]}; do
    REQ=${TOOL^^}
    REQ=${REQ//-/_}
    if [ -z "${!REQ}" ]; then
      INSTALL_PACKAGES="${INSTALL_PACKAGES} ${TOOL}"
    fi
  done
  local ALTERNATIVES=("apt-get;dpkg;ipkg;opkg;rpm" "sed;grep" "curl;wget" "uname;ldconfig")
  for ALTERNATIVE in "${ALTERNATIVES[@]}"; do
    IFS=";" read -r -a TOOL_ALTERNATIVE <<< "${ALTERNATIVE}"
    if ! verify_tool_alternatives "${TOOL_ALTERNATIVE[@]}"; then
      INSTALL_PACKAGES="${INSTALL_PACKAGES} ${TOOL_ALTERNATIVE[0]}"
    fi
  done
}

# check internet connection in multiple ways
check_connectivity() {
  log_info -n "Checking internet connectivity..."
  if [ ! -z "${CURL}" ]; then
    if ${CURL} ${BASE_PROTO}://${BASE_URL} 1>${STDOUT} 2>${STDERR}; then
      echo "OK"
      return 0
    fi
 elif [ ! -z "${WGET}" ]; then
    if ${WGET} -q ${BASE_PROTO}://${BASE_URL} 1>${STDOUT} 2>${STDERR}; then
      echo "OK"
      return 0
    fi
  fi
  log_info -q "failed"
  log_fatal "Please make sure your device is online before running ${ME}"
  return 1;
}

machine_to_arch() {
  case ${MACHINE} in
    amd64|x86_64|x86-64)
      ARCH="amd64"
      ;;
    arm64|aarch64)
      ARCH="arm64"
      ;;
    armhf|armv7l)
      ARCH="armhf"
      ;;
    *)
      ARCH="unknown"
      ;;
  esac
}
detect_arch() {
  log_debug -n "Detecting system architecture..."
  if [ ! -z "${DPKG}" ]; then
    MACHINE=`${DPKG} --print-architecture`
  elif [ ! -z "${UNAME}" ]; then
    MACHINE=`${UNAME} -m`
  elif [ ! -z "${LDCONFIG}" ] && [ ! -z "${GREP}" ]; then
    MACHINE=`${LDCONFIG} -p | ${GREP} -oP "(?<=\/ld-linux-)[^.]+"`
  fi
  machine_to_arch
  if [ "${ARCH}" = "unknown" ]; then
    log_debug -q " failed"
    internal_error "Architecture for ${MACHINE} is unsupported"
  fi
  log_debug -q " ${ARCH}"
}

parse_os_release() {
  if [ ! -z "${SED}" ]; then
    ${SED} -nE "s/^${1}=\"?([^\"]+)\"?$/\1/p" /etc/os-release 2>/dev/null
  elif [ ! -z "${GREP}" ]; then
    if ! grep -oP "(?<=^${1}=\").+(?=\")" /etc/os-release 2>/dev/null; then
      grep -oP "(?<=^${1}=).+$" /etc/os-release 2>/dev/null
    fi
  fi
}
detect_os() {
  log_debug "Detecting operating system..."
  OS=`parse_os_release "ID"`
  log_debug "Detected OS ${OS}"

  case ${OS} in
    debian|raspbian|ubuntu)
      OS_VERSION=`parse_os_release "VERSION_ID"`
      CODENAME=`parse_os_release "VERSION_CODENAME"`
      OS_LIKE="debian"
      ;;
    fedora|rhel)
      OS_VERSION=`parse_os_release "VERSION_ID"`
      OS_LIKE="fedora"
      log_warning "Fedora-based distributions that use podman are not yet supported. Please ensure"
      log_warning "you have Docker installed instead of podman, or follow the instructions found at"
      log_warning "https://docs.docker.com/engine/install/fedora/ to install Docker."
      log_warning "If you cannot use Docker for some reason, please contact us at info@flecs.tech"
      log_warning "for further information about podman support."
      confirm_yn "Continue"
      ;;
    arch)
      OS_LIKE=arch
      ;;
    *)
      OS_LIKE=other
      ;;
  esac
  NAME=`parse_os_release "NAME"`
  log_debug "Detected OS_VERSION ${OS_VERSION}"
  log_debug "Detected CODENAME ${CODENAME}"
  log_debug "Detected NAME ${NAME}"

  detect_arch
}

DEBIAN_VERSIONS=(11 12 13)
DEBIAN_CODENAMES=(bullseye bookworm trixie)

UBUNTU_VERSIONS=(20.04 22.04 23.04 24.04 25.04)
UBUNTU_CODENAMES=(focal jammy lunar noble plucky)

RHEL_VERSIONS=(8.8 9.2)
FEDORA_VERSIONS=(37 38)

verify_os_version() {
  if [ -z "${OS_VERSION}" ]; then
    internal_error "OS_VERSION not set in verify_os_version"
  fi

  for i in "${!VERIFY_VERSIONS[@]}"; do
    if [[ "${OS_VERSION}" == "${VERIFY_VERSIONS[$i]}" ]]; then
      local SUPPORTED="true"
      break
    fi
  done

  if [[ "${SUPPORTED}" != "true" ]]; then
    if cmp_less "${VERIFY_VERSIONS[-1]}" "${OS_VERSION}"; then
      local NEWER="true"
    fi
  fi

  if [[ "${SUPPORTED}" != "true" ]]; then
    if [[ "${NEWER}" != "true" ]]; then
      if [ ! -z "${CODENAME}" ]; then
        log_error "You are running an outdated version ${OS_VERSION} (${CODENAME}) of your OS. Supported versions are"
      else
        log_error "You are running an outdated version ${OS_VERSION} of your OS. Supported versions are"
      fi
      for i in "${!VERIFY_VERSIONS[@]}"; do
        if [ ! -z "${VERIFY_CODENAMES[$i]}" ]; then
          log_error "    ${VERIFY_VERSIONS[$i]} (${VERIFY_CODENAMES[$i]})"
        else
          log_error "    ${VERIFY_VERSIONS[$i]}"
        fi
      done
      log_fatal
    else
      log_warning "You are running an unsupported version of your OS. Supported versions are"
      for i in "${!VERIFY_VERSIONS[@]}"; do
        if [ ! -z "${VERIFY_CODENAMES[$i]}" ]; then
          log_warning "    ${VERIFY_VERSIONS[$i]} (${VERIFY_CODENAMES[$i]})"
        else
          log_warning "    ${VERIFY_VERSIONS[$i]}"
        fi
      done
      if [ ! -z "${CODENAME}" ]; then
        log_warning "Your version ${OS_VERSION} (${CODENAME}) seems more recent, so continuing anyway"
      else
        log_warning "Your version ${OS_VERSION} seems more recent, so continuing anyway"
      fi
    fi
  fi
}

verify_os() {
  case ${OS} in
    debian|raspbian)
      VERIFY_VERSIONS=("${DEBIAN_VERSIONS[@]}")
      VERIFY_CODENAMES=("${DEBIAN_CODENAMES[@]}")
      verify_os_version
      ;;
    ubuntu|pop)
      VERIFY_VERSIONS=("${UBUNTU_VERSIONS[@]}")
      VERIFY_CODENAMES=("${UBUNTU_CODENAMES[@]}")
      verify_os_version
      ;;
    fedora)
      VERIFY_VERSIONS=("${FEDORA_VERSIONS[@]}")
      VERIFY_CODENAMES=
      verify_os_version
      ;;
    rhel)
      VERIFY_VERSIONS=("${RHEL_VERSIONS[@]}")
      VERIFY_CODENAMES=
      verify_os_version
      ;;
    arch)
      # rolling release, so no version to check
      ;;
    *)
      EXPERIMENTAL=true
  esac
}

determine_docker_version() {
  log_info -n "Determining Docker version..."
  if [ -z "${DOCKER}" ]; then
    echo " none"
    log_fatal "Docker is not installed on your device"
  fi

  if ${DOCKER} -v 2>/dev/null | ${GREP} podman >/dev/null 2>&1; then
    DOCKER_NAME="podman"
  else
    DOCKER_NAME="Docker"
  fi

  TIMEOUT=5
  while ! ${DOCKER} version >/dev/null 2>&1 && [ ${TIMEOUT} -ge 1 ]; do
    sleep 1
    TIMEOUT=$((TIMEOUT-1))
  done
  if [ ! -z "${SED}" ]; then
    DOCKER_CLIENT_VERSION=`${DOCKER} -v 2>/dev/null | ${SED} -nE 's/^[^0-9]+([0-9\.]+).*$/\1/p'`
  elif [ ! -z "${GREP}" ]; then
    DOCKER_CLIENT_VERSION=`${DOCKER} -v 2>/dev/null | ${GREP} -oP "([0-9]+[\.]){2}[0-9]+" | ${HEAD} -n1`
  fi

  echo " found ${DOCKER_NAME}"

  DOCKER_API_VERSION="unknown"
  if ! ${DOCKER} version >/dev/null 2>&1; then
    log_warning "Could not determine Docker API version. Maybe you need to start it using"
    log_warning "    'systemctl enable --now docker.service' or"
    log_warning "    '/etc/init.d/docker start'"
  else
    DOCKER_API_VERSION=`${DOCKER} version --format '{{.Server.APIVersion}}' 2>/dev/null`
  fi

  if [ -z "${DOCKER_API_VERSION}" ] || [ -z "${DOCKER_CLIENT_VERSION}" ]; then
    internal_error "Could not determine Docker version."
    return 1
  fi
  log_info "    Client: ${DOCKER_CLIENT_VERSION}"
  log_info "    API: ${DOCKER_API_VERSION}"

  return 0
}

# verifies that a supported Docker version is installed and running. Podman is detected as such,
# and will currently be rejected as support is in development.
DOCKER_OK=0
DOCKER_OUTDATED=2
MIN_DOCKER_API_VERSION="1.41"
MIN_DOCKER_CLIENT_VERSION="20.10.5"
verify_docker_version() {
  if [ "${DOCKER_NAME}" = "podman" ]; then
    MIN_DOCKER_API_VERSION="4.5.0"
    MIN_DOCKER_CLIENT_VERSION="4.5.0"
    log_error "Podman is currently unsupported."
    log_fatal "Please contact us at info@flecs.tech if you require podman support"
  fi

  if cmp_less "${DOCKER_CLIENT_VERSION}" "${MIN_DOCKER_CLIENT_VERSION}"; then
    log_error "FLECS requires at least ${DOCKER_NAME} client version ${MIN_DOCKER_CLIENT_VERSION}"
    log_error "The available client version is ${DOCKER_CLIENT_VERSION}"
    return ${DOCKER_OUTDATED}
  fi

  if cmp_less "${DOCKER_API_VERSION}" "${MIN_DOCKER_API_VERSION}" && [ ! "${DOCKER_API_VERSION}" = "unknown" ]; then
    log_error "FLECS requires at least ${DOCKER_NAME} API version ${MIN_DOCKER_API_VERSION}."
    log_error "The available API version is ${DOCKER_API_VERSION}"
    return ${DOCKER_OUTDATED}
  fi

  return ${DOCKER_OK}
}

install_docker_debian() {
  echo "apt-get"
  if ! apt_update; then
    log_fatal "apt_update returned error in install_docker"
  fi
  if ! apt_install docker.io; then
    log_fatal "apt_install install returned error in install_docker"
  fi
}

install_docker_fedora() {
  echo " yum"
  if [ -z "${YUM}" ]; then
    internal_error "yum not present in install_docker_fedora"
  fi
  if ! yum_update; then
    log_fatal "yum_update returned error in install_docker"
  fi
  if ! yum_install podman-docker; then
    log_fatal "yum_install returned error in install_docker"
  fi
}

install_docker_arch() {
  echo " pacman"
  if [ -z "${PACMAN}" ]; then
    internal_error "pacman not present in install_docker_arch"
  fi
  if ! pacman_update; then
    log_fatal "pacman_update returned error in install_docker"
  fi
  if ! pacman_install docker; then
    log_fatal "pacman_install returned error in install_docker"
  fi
}

install_docker() {
  case ${OS_LIKE} in
    debian)
      log_info -n "Installing Docker using"
      install_docker_debian ${CODENAME}
      ;;
    fedora)
      log_warning "Automatic Docker installation on fedora is currently unsupported"
      #install_docker_fedora
      ;;
    arch)
      log_info -n "Installing Docker using"
      install_docker_arch
      ;;
    *)
      log_fatal "Docker not installed and cannot install automatically"
  esac
  log_info "Done installing Docker. Restarting..."
  exec "${SCRIPTNAME}" --no-banner --no-welcome ${ARGS}
}

start_and_enable_docker() {
  if ! docker version >/dev/null 2>&1; then
    log_info -n "Attempting to start Docker..."
    if [ ! -z "${SYSTEMCTL}" ] && ${SYSTEMCTL} enable --now docker >/dev/null 2>&1; then
      echo " OK (systemctl)"
      return 0
    elif [ ! -z "${SERVICE}" ]; then
      if [ ! -z "${CHKCONFIG}" ] && [ ! -z "${UPDATE_RC_D}" ]; then
        if ! ${CHKCONFIG} docker on; then
          ${UPDATE_RC_D} docker defaults
        fi
      fi
      service docker start >/dev/null 2>&1;
      echo " OK (init.d)"
      return 0
    fi
    echo " failed"
    return 1
  fi
  return 0
}

determine_latest_version() {
  if [ -z "${VERSION_CORE}" ]; then
    determine_latest_core_version
  else
    log_debug "Using user provided core version: ${VERSION_CORE}"
  fi
  if [ -z "${VERSION_WEBAPP}" ]; then
    determine_latest_webapp_version
  else
    log_debug "Using user provided webapp version: ${VERSION_WEBAPP}"
  fi
  if [ ! -z "${VERSION_CORE}" ] && [ ! -z "${VERSION_WEBAPP}" ]; then
    log_info "    Core: ${VERSION_CORE}"
    log_info "    WebApp: ${VERSION_WEBAPP}"
  else
    log_fatal "Could not determine version of FLECS to install"
  fi
}

determine_latest_webapp_version() {
  log_info -n "Determining latest FLECS webapp version..."
  # try through curl first, if available
  if [ ! -z "${CURL}" ]; then
    VERSION_WEBAPP=`${CURL} -fsSL ${BASE_PROTO}://${BASE_URL}/webapp/latest_flecs-webapp_${ARCH}`
  # use wget as fallback, if available
  elif [ ! -z "${WGET}" ]; then
    VERSION_WEBAPP=`${WGET} -q -O - ${BASE_PROTO}://${BASE_URL}/webapp/latest_flecs-webapp_${ARCH}`
  fi
  if [ ! -z "${VERSION_WEBAPP}" ]; then
    echo " OK"
  else
    echo " failed"
    log_fatal "Could not determine version of FLECS webapp to install"
  fi
}

determine_latest_core_version() {
  log_info -n "Determining latest FLECS core version..."
  # try through curl first, if available
  if [ ! -z "${CURL}" ]; then
    VERSION_CORE=`${CURL} -fsSL ${BASE_PROTO}://${BASE_URL}/flecs/latest_flecs_${ARCH}`
  # use wget as fallback, if available
  elif [ ! -z "${WGET}" ]; then
    VERSION_CORE=`${WGET} -q -O - ${BASE_PROTO}://${BASE_URL}/flecs/latest_flecs_${ARCH}`
  fi
  if [ ! -z "${VERSION_CORE}" ]; then
    echo " OK"
  else
    echo " failed"
    log_fatal "Could not determine version of FLECS core to install"
  fi
}

banner() {
  if [ -z "${NO_BANNER}" ]; then
    echo "                      ▒▒▒▒▒▒▒▒  ▒▒  ▒▒        ▒▒  ▒▒▒▒▒▒▒                       "
    echo "                      ▒▒        ▒▒  ▒▒            ▒▒    ▒▒                      "
    echo "                      ▒▒▒▒▒▒    ▒▒  ▒▒        ▒▒  ▒▒▒▒▒▒▒                       "
    echo "                      ▒▒        ▒▒  ▒▒        ▒▒  ▒▒                            "
    echo "                      ▒▒        ▒▒  ▒▒▒▒▒▒▒▒  ▒▒  ▒▒                            "
    echo "                      FLECS Installer for Linux Platforms                       "
    echo
    echo "                              https://flecs.tech/                               "
    echo
  fi
}

start_flecs() {
  local ENV="-e VERSION_CORE=${VERSION_CORE} -e VERSION_WEBAPP=${VERSION_WEBAPP}${WHITELABEL:+ -e WHITELABEL=${WHITELABEL}}"
  local FILIP_TAG="latest"
  if [ -n "$VERSION_FILIP" ]; then
    FILIP_TAG="$VERSION_FILIP"
  elif [ "$DEV_MODE" = "1" ]; then
    FILIP_TAG="dev"
  fi
  docker container rm -f flecs >/dev/null 2>&1
  docker container run --detach --name flecs ${ENV} --network host --restart always --volume /var/run/docker.sock:/var/run/docker.sock flecspublic.azurecr.io/flecs/filip:${FILIP_TAG} >/dev/null
  if [ $? -ne 0 ]; then
    log_fatal "Failed to start flecs"
  fi
}

apt_remove() {
  local out

  out="$(apt list --installed ${1} 2>/dev/null)"
  if [ $? -ne 0 ]; then
    log_fatal "Failed to check if ${1} is installed"
  elif grep -q "${1}/" <<<"$out"; then
    log_debug "Removing ${1}..."
    if apt remove -y ${1} >/dev/null 2>&1; then
      log_debug " OK"
    else
      log_fatal "Failed to remove ${1}"
    fi
  fi
}

remove_old_flecs() {
  if ! have apt; then
    return 0
  fi

  apt_remove flecs-webapp
  apt_remove flecs
}

if [ -z "${FLECS_TESTING}" ]; then
  parse_args $*
  banner

  # ensure running as root
  if [ ${EUID} -ne 0 ]; then
    log_error "${ME} needs to run as root"
    if ! have sudo; then
      log_fatal "Please login as root user and restart installation"
    else
      if confirm_yn "Restart using sudo"; then
        exec ${SUDO} "${SCRIPTNAME}" --no-banner ${ARGS}
      else
        log_fatal "Cannot continue installation without root privileges"
      fi
    fi
  fi

  detect_tools
  verify_tools
  if [ ! -z "${INSTALL_PACKAGES}" ]; then
    log_info "${ME} requires the following packages to continue"
    log_info "    ${INSTALL_PACKAGES}"
    if ! can_install_program; then
      log_error "${ME} does not support automatic package installation on your device"
      log_fatal "Please install missing packages manually before running ${ME}"
    fi
    if confirm_yn "Automatically install these packages"; then
      if ! install_program ${INSTALL_PACKAGES}; then
        log_fatal "Could not install required dependencies"
      fi
    else
      log_fatal "Cannot continue without required dependencies"
    fi
    log_info "Done installing dependencies. Restarting..."
    exec "${SCRIPTNAME}" --no-banner --no-welcome ${ARGS}
  fi
  detect_os
  verify_os

  welcome

  # print warning for unsupported systems and wait for confirmation, if not unattended
  if [ "${EXPERIMENTAL}" == "true" ]; then
    log_warning "Your operating system is not officially supported by the installer."
    if [ ! -z "${OS}" ]; then
      if [ ! -z "${NAME}" ]; then
        log_warning "    Name: ${NAME} (${OS})"
      else
        log_warning "    OS: ${OS}"
      fi
    else
      if [ ! -z "${NAME}" ]; then
        log_warning "    Name: ${NAME}"
      fi
    fi
    [ ! -z "${OS_VERSION}" ] && log_warning "    Version: ${OS_VERSION}" || log_warning "    Version: unknown"
    log_warning

    log_warning "Installation might still succeed, depending on your exact system configuration."
    log_warning "No changes will be made to your system on failure, so it is usually safe to"
    log_warning "attempt installation anyway."
    confirm "Press enter to continue installation, or Ctrl-C to cancel."
    log_warning
  fi

  echo

  # make sure device is online
  check_connectivity

  # check if Docker is installed,
  if [ -z "${DOCKER}" ]; then
    install_docker
  fi
  # check if Docker is running and auto start is enabled
  start_and_enable_docker
  determine_docker_version
  verify_docker_version
  if [ $? -eq ${DOCKER_OUTDATED} ]; then
    log_error "FLECS requires at least Docker version ${MIN_DOCKER_CLIENT_VERSION} (${DOCKER_CLIENT_VERSION} available)"
    log_fatal "Please upgrade your Docker installation before installing FLECS"
  fi

  # query latest FLECS version online
  if ! determine_latest_version; then
    log_fatal "Could not determine latest version of FLECS"
  fi

  if ! remove_old_flecs; then
    log_fatal "Could not remove old version of FLECS, please remove it manually"
  fi

  start_flecs
  log_info "FLECS was successfully started!"
fi
EOF

SCRIPTNAME=`readlink -f "${0}"`
if [ "${SCRIPTNAME}" != "/tmp/filip.sh" ]; then
  chmod +x /tmp/filip.sh
  if (exec >/dev/null 2>&1 3</dev/tty); then
    echo "Executing /tmp/filip.sh with stdin attached"
    exec /tmp/filip.sh "$@" </dev/tty
  else
    echo "Executing /tmp/filip.sh without stdin attached"
    exec /tmp/filip.sh "$@" 0<&-
  fi
fi
