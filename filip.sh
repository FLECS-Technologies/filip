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
SCRIPTNAME=$(readlink -f "${0}")
ARGS=("$@")
STDOUT=/dev/null
STDERR=/dev/null

LATEST_URL=https://latest.flecs.tech
CONTAINER_REGISTRY=cr.flecs.tech
FILIP_IMAGE=${CONTAINER_REGISTRY}/flecs/filip

print_usage() {
  echo "Usage: ${SCRIPTNAME} [options]"
  echo
  echo "  -v --verbose               print command output (apt, docker, ...)"
  echo "  -d --debug                 print verbose output plus internal debug messages"
  echo "  -y --yes                   assume yes as answer to all prompts (unattended mode)"
  echo "     --no-banner             do not print ${ME} banner"
  echo "     --no-welcome            do not print welcome message"
  echo "     --core-version <ver>    Install version <ver> of flecs-core instead of the latest version"
  echo "     --webapp-version <ver>  Install version <ver> of flecs-webapp instead of the latest version"
  echo "     --http-port <port>      use <port> for accessing the reverse proxy via http"
  echo "     --https-port <port>     use <port> for accessing the reverse proxy via https"
  echo "     --help                  print this help and exit"
}

# some log functions...
log_debug() {
  if [ -n "${LOG_DEBUG}" ]; then
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
      *)
        break;;
    esac
  done
  echo ${ECHO_ARGS} "$@"
}
log_warning() {
  echo "⚠  $@" 1>&2
}
log_error() {
  while true; do
    case ${1} in
      -n)
        local ECHO_ARGS="-n"
        shift
        ;;
      *)
        break;;
    esac
  done
  echo ${ECHO_ARGS} "❌ $@" 1>&2
}
# log_fatal will terminate with exit code 1 after logging
log_fatal() {
  echo "❌ $@" 1>&2
  exit 1
}
# internal_error should *only* be called if guaranteed preconditions are not met
internal_error() {
  log_error "Internal error: $@"
  exit 1
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
    echo >&2
  fi
}
confirm_yn() {
  if [ -z "${ASSUME_YES}" ]; then
    require_stdin
    while true; do
      read -p "$@? [y/n]: " input
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
  local RES=$(${SORT} -t . -k 1,1n -k 2,2n -k 3,3n <(echo "${1}") <(echo "${2}") | ${HEAD} -n1)
  if [ "${RES}" = "${1}" ]; then
    return 0
  fi
  return 1
}

parse_args() {
  while [ -n "${1}" ]; do
    case ${1} in
      -v|--verbose)
        STDOUT=/dev/stdout
        STDERR=/dev/stderr
        ;;
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
        DEV_MODE=1
        ;;
      --core-version)
        VERSION_CORE=${2}
        if [ -z "${VERSION_CORE}" ]; then
          log_error "argument --core-version requires a value"
          print_usage
          exit 1
        fi
        shift
        ;;
      --webapp-version)
        VERSION_WEBAPP=${2}
        if [ -z "${VERSION_WEBAPP}" ]; then
          log_error "argument --webapp-version requires a value"
          print_usage
          exit 1
        fi
        shift
        ;;
      --filip-version)
        VERSION_FILIP=${2}
        if [ -z "${VERSION_FILIP}" ]; then
          log_error "argument --filip-version requires a value"
          print_usage
          exit 1
        fi
        shift
        ;;
      --whitelabel)
        WHITELABEL=${2}
        if [ -z "${WHITELABEL}" ]; then
          log_error "argument --whitelabel requires a value"
          print_usage
          exit 1
        fi
        shift
        ;;
      --http-port)
        HTTP_PORT=${2}
        if [ -z "${HTTP_PORT}" ]; then
          log_error "argument --http-port requires a value"
          print_usage
          exit 1
        fi
        shift
        ;;
      --https-port)
        HTTPS_PORT=${2}
        if [ -z "${HTTPS_PORT}" ]; then
          log_error "argument --https-port requires a value"
          print_usage
          exit 1
        fi
        shift
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        log_error "Unknown option: ${1}"
        print_usage
        exit 1
        ;;
    esac
    shift
  done
}

welcome() {
  if [ -z "${NO_WELCOME}" ]; then
    # print welcome message and wait for confirmation, if not unattended
    log_info -n "Installing FLECS on"
    if [ -n "${NAME}" ]; then
      log_info -n " ${NAME}"
      [ -n "${OS_VERSION}" ] && log_info -n " ${OS_VERSION}"
      [ -n "${CODENAME}" ] && log_info -n " (${CODENAME})"
    else
      log_info -n " your device"
    fi
    log_info " [${ARCH}]"
    confirm "Press ↵ to install or Ctrl-C to cancel."
  fi
}

have_program() {
  command -v "${1}" 2>/dev/null
}
# wrapper around have_program that declares a global variable named like the
# program in uppercase (e.g. CURL=... for curl)
have() {
  log_debug -n "Looking for ${1}..."
  local TOOL=${1^^}
  local TOOL=${TOOL//-/_}
  local TOOL=${TOOL//./_}
  if [ -z "${!TOOL}" ]; then
    declare -g ${TOOL}=$(have_program "${1}")
  fi
  if [ -z "${!TOOL}" ]; then
    log_debug -q " not found"
    return 1
  fi
  log_debug -q " found"
}

# wrapper for apt-get update
apt_update() {
  log_debug "apt-get update"
  if [ -z "${APT_GET}" ] || ! ${APT_GET} update 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
}
# wrapper for apt-get install
apt_install() {
  log_debug "apt-get install $@"
  if [ -z "${APT_GET}" ] || ! ${APT_GET} -y install --reinstall --no-install-recommends "$@" 1>${STDOUT} 2>${STDERR}; then
    return 1
  fi
}

# detect which tools are available on the system
detect_tools() {
  log_debug "Checking availability of required tools..."
  TOOLS=(apt-get curl wget docker grep head sed sort systemctl uname dpkg)
  for TOOL in "${TOOLS[@]}"; do
    have "${TOOL}"
  done
}
# quit if required tools are missing
verify_tools() {
  log_debug "Verifying presence of required basic tools..."
  if [ -z "${CURL}" ] && [ -z "${WGET}" ]; then
    log_fatal "Neither curl nor wget found. Please install one before running ${ME}"
  fi
  if [ -z "${SORT}" ]; then
    log_fatal "sort not found. Please install coreutils before running ${ME}"
  fi
  if [ -z "${HEAD}" ]; then
    log_fatal "head not found. Please install coreutils before running ${ME}"
  fi
}

# check internet connection in multiple ways
check_connectivity() {
  log_info -n "  Internet connectivity..."
  if [ -n "${CURL}" ]; then
    if ${CURL} https://flecs.tech 1>/dev/null 2>${STDERR}; then
      log_info " ✅"
      return 0
    fi
  elif [ -n "${WGET}" ]; then
    if ${WGET} -q https://flecs.tech 1>/dev/null 2>${STDERR}; then
      log_info " ✅"
      return 0
    fi
  fi
  log_info " ❌"
  log_fatal "Please make sure your device is online before running ${ME}"
}

machine_to_arch() {
  case ${MACHINE} in
    amd64|x86_64|x86-64)
      ARCH="amd64"
      ;;
    arm64|aarch64)
      ARCH="arm64"
      ;;
    *)
      ARCH="unknown"
      ;;
  esac
}
detect_arch() {
  log_debug -n "Detecting system architecture..."
  if [ -n "${DPKG}" ]; then
    MACHINE=$(${DPKG} --print-architecture)
  elif [ -n "${UNAME}" ]; then
    MACHINE=$(${UNAME} -m)
  fi
  if [ -z "${MACHINE}" ]; then
    log_debug -q " failed"
    log_fatal "Could not detect architecture: neither dpkg nor uname available"
  fi
  machine_to_arch
  if [ "${ARCH}" = "unknown" ]; then
    log_debug -q " failed"
    log_fatal "Unsupported machine type: ${MACHINE}"
  fi
  log_debug -q " ${ARCH}"
}

parse_os_release() {
  if [ -n "${SED}" ]; then
    ${SED} -nE "s/^${1}=\"?([^\"]+)\"?$/\1/p" /etc/os-release 2>/dev/null
  elif [ -n "${GREP}" ]; then
    if ! ${GREP} -oP "(?<=^${1}=\").+(?=\")" /etc/os-release 2>/dev/null; then
      ${GREP} -oP "(?<=^${1}=).+$" /etc/os-release 2>/dev/null
    fi
  fi
}
detect_os() {
  log_debug "Detecting operating system..."
  OS=$(parse_os_release "ID")
  log_debug "Detected OS ${OS}"

  case ${OS} in
    debian|raspbian|ubuntu)
      OS_VERSION=$(parse_os_release "VERSION_ID")
      CODENAME=$(parse_os_release "VERSION_CODENAME")
      OS_LIKE="debian"
      ;;
    fedora|rhel)
      OS_VERSION=$(parse_os_release "VERSION_ID")
      OS_LIKE="fedora"
      log_warning "Fedora-based distributions that use podman are not yet supported. Please ensure"
      log_warning "you have Docker installed instead of podman, or follow the instructions found at"
      log_warning "https://docs.docker.com/engine/install/fedora/ to install Docker."
      log_warning "If you cannot use Docker for some reason, please contact us at info@flecs.tech"
      log_warning "for further information about podman support."
      if ! confirm_yn "Continue"; then
        log_fatal "Installation cancelled"
      fi
      ;;
    arch)
      OS_LIKE=arch
      ;;
    *)
      OS_LIKE=other
      ;;
  esac
  NAME=$(parse_os_release "NAME")
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
    if [ "${OS_VERSION}" = "${VERIFY_VERSIONS[$i]}" ]; then
      return 0
    fi
  done

  if cmp_less "${VERIFY_VERSIONS[-1]}" "${OS_VERSION}"; then
    log_warning "You are running an unsupported version of your OS. Supported versions are"
    for i in "${!VERIFY_VERSIONS[@]}"; do
      if [ -n "${VERIFY_CODENAMES[$i]}" ]; then
        log_warning "    ${VERIFY_VERSIONS[$i]} (${VERIFY_CODENAMES[$i]})"
      else
        log_warning "    ${VERIFY_VERSIONS[$i]}"
      fi
    done
    if [ -n "${CODENAME}" ]; then
      log_warning "Your version ${OS_VERSION} (${CODENAME}) seems more recent, so continuing anyway"
    else
      log_warning "Your version ${OS_VERSION} seems more recent, so continuing anyway"
    fi
    return 0
  fi

  if [ -n "${CODENAME}" ]; then
    log_error "You are running an outdated version ${OS_VERSION} (${CODENAME}) of your OS. Supported versions are"
  else
    log_error "You are running an outdated version ${OS_VERSION} of your OS. Supported versions are"
  fi
  for i in "${!VERIFY_VERSIONS[@]}"; do
    if [ -n "${VERIFY_CODENAMES[$i]}" ]; then
      log_error "    ${VERIFY_VERSIONS[$i]} (${VERIFY_CODENAMES[$i]})"
    else
      log_error "    ${VERIFY_VERSIONS[$i]}"
    fi
  done
  exit 1
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
      VERIFY_CODENAMES=()
      verify_os_version
      ;;
    rhel)
      VERIFY_VERSIONS=("${RHEL_VERSIONS[@]}")
      VERIFY_CODENAMES=()
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
  log_info -n "  Docker..."

  if ${DOCKER} -v 2>/dev/null | ${GREP} podman >/dev/null 2>&1; then
    DOCKER_NAME="podman"
  else
    DOCKER_NAME="Docker"
  fi

  if [ -n "${SED}" ]; then
    DOCKER_CLIENT_VERSION=$(${DOCKER} -v 2>/dev/null | ${SED} -nE 's/^[^0-9]+([0-9\.]+).*$/\1/p')
  elif [ -n "${GREP}" ]; then
    DOCKER_CLIENT_VERSION=$(${DOCKER} -v 2>/dev/null | ${GREP} -oP "([0-9]+[\.]){2}[0-9]+" | ${HEAD} -n1)
  fi

  DOCKER_API_VERSION="unknown"
  if ${DOCKER} version >/dev/null 2>&1; then
    DOCKER_API_VERSION=$(${DOCKER} version --format '{{.Server.APIVersion}}' 2>/dev/null)
  fi

  if [ -z "${DOCKER_CLIENT_VERSION}" ]; then
    log_info " ❌"
    log_fatal "Could not determine Docker version."
  fi

  log_info " ✅ ${DOCKER_CLIENT_VERSION} (API ${DOCKER_API_VERSION})"
}

MIN_DOCKER_API_VERSION="1.41"
MIN_DOCKER_CLIENT_VERSION="20.10.5"
verify_docker_version() {
  if [ "${DOCKER_NAME}" = "podman" ]; then
    log_error "Podman is currently unsupported."
    log_fatal "Please contact us at info@flecs.tech if you require podman support"
  fi

  if cmp_less "${DOCKER_CLIENT_VERSION}" "${MIN_DOCKER_CLIENT_VERSION}"; then
    log_error "FLECS requires at least ${DOCKER_NAME} client version ${MIN_DOCKER_CLIENT_VERSION}"
    log_error "The available client version is ${DOCKER_CLIENT_VERSION}"
    log_fatal "Please upgrade your Docker installation before installing FLECS"
  fi

  if [ "${DOCKER_API_VERSION}" != "unknown" ] && cmp_less "${DOCKER_API_VERSION}" "${MIN_DOCKER_API_VERSION}"; then
    log_error "FLECS requires at least ${DOCKER_NAME} API version ${MIN_DOCKER_API_VERSION}"
    log_error "The available API version is ${DOCKER_API_VERSION}"
    log_fatal "Please upgrade your Docker installation before installing FLECS"
  fi
}

install_docker_debian() {
  if ! apt_update; then
    log_fatal "apt_update failed in install_docker"
  fi

  # Docker is split into docker.io and docker-cli for Debian 13+ and Ubuntu
  # 25.04+. Add to PACKAGE list for these OSes.
  local PACKAGES="docker.io"
  case ${OS} in
    debian|raspbian)
      ! cmp_less "${OS_VERSION}" "13" && PACKAGES="${PACKAGES} docker-cli" ;;
    ubuntu)
      ! cmp_less "${OS_VERSION}" "25.04" && PACKAGES="${PACKAGES} docker-cli" ;;
  esac

  if ! apt_install ${PACKAGES}; then
    log_fatal "apt_install failed in install_docker"
  fi
}

install_docker() {
  if [ "${OS_LIKE}" != "debian" ]; then
    log_fatal "Automatic Docker installation is only supported on Debian/Ubuntu-based systems"
  fi
  log_info -n "  Installing Docker..."
  install_docker_debian
  log_info " ✅"
  log_info "  Restarting installer..."
  exec "${SCRIPTNAME}" --no-banner --no-welcome "${ARGS[@]}"
}

ensure_docker() {
  # `docker` executable is required
  if [ -z "${DOCKER}" ]; then
    install_docker
  fi

  # `docker version` needs to succeed
  if ${DOCKER} version >/dev/null 2>&1; then
    return 0
  fi

  # if `docker version` failed -> try to start and enable docker.service
  if [ -n "${SYSTEMCTL}" ] && ${SYSTEMCTL} cat docker.service >/dev/null 2>&1; then
    log_info -n "  Starting Docker service..."
    if ${SYSTEMCTL} enable --now docker >/dev/null 2>&1 && ${DOCKER} version >/dev/null 2>&1; then
      log_info " ✅"
      return 0
    fi
    log_info " ❌"
  fi

  # if starting service failed, or service is not present -> install
  install_docker
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
}

determine_latest_webapp_version() {
  log_info -n "  FLECS webapp..."
  if [ -n "${CURL}" ]; then
    VERSION_WEBAPP=$(${CURL} -s "${LATEST_URL}/webapp")
  elif [ -n "${WGET}" ]; then
    VERSION_WEBAPP=$(${WGET} -q -O - "${LATEST_URL}/webapp")
  fi
  if [ -n "${VERSION_WEBAPP}" ]; then
    log_info " ✅ ${VERSION_WEBAPP}"
  else
    log_info " ❌"
    log_fatal "Could not determine version of FLECS webapp to install"
  fi
}

determine_latest_core_version() {
  log_info -n "  FLECS core..."
  if [ -n "${CURL}" ]; then
    VERSION_CORE=$(${CURL} -s "${LATEST_URL}/core")
  elif [ -n "${WGET}" ]; then
    VERSION_CORE=$(${WGET} -q -O - "${LATEST_URL}/core")
  fi
  if [ -n "${VERSION_CORE}" ]; then
    log_info " ✅ ${VERSION_CORE}"
  else
    log_info " ❌"
    log_fatal "Could not determine version of FLECS core to install"
  fi
}

banner() {
  if [ -z "${NO_BANNER}" ]; then
    echo "  ▒▒▒▒▒▒▒▒  ▒▒  ▒▒        ▒▒  ▒▒▒▒▒▒▒ "
    echo "  ▒▒        ▒▒  ▒▒            ▒▒    ▒▒"
    echo "  ▒▒▒▒▒▒    ▒▒  ▒▒        ▒▒  ▒▒▒▒▒▒▒ "
    echo "  ▒▒        ▒▒  ▒▒        ▒▒  ▒▒      "
    echo "  ▒▒        ▒▒  ▒▒▒▒▒▒▒▒  ▒▒  ▒▒      "
    echo "  FLECS Installer for Linux Platforms "
    echo
    echo "          https://flecs.tech/         "
    echo
  fi
}

start_flecs() {
  local ENV="-e VERSION_CORE=${VERSION_CORE} -e VERSION_WEBAPP=${VERSION_WEBAPP}${WHITELABEL:+ -e WHITELABEL=${WHITELABEL}}"
  ENV+="${HTTP_PORT:+ -e FLOXY_HTTP_PORT=${HTTP_PORT}}${HTTPS_PORT:+ -e FLOXY_HTTPS_PORT=${HTTPS_PORT}}"
  local FILIP_TAG="latest"
  if [ -n "$VERSION_FILIP" ]; then
    FILIP_TAG="$VERSION_FILIP"
  elif [ "$DEV_MODE" = "1" ]; then
    FILIP_TAG="dev"
  fi
  log_info -n "  Pulling latest image..."
  ${DOCKER} image pull ${FILIP_IMAGE}:${FILIP_TAG} 1>${STDOUT} 2>${STDERR} && log_info " ✅" || log_info " ⚠"
  log_info -n "  Starting FLECS..."
  ${DOCKER} container rm -f flecs >/dev/null 2>&1 || true
  if ! ${DOCKER} container run --detach --name flecs ${ENV} --network host --restart always --volume /var/run/docker.sock:/var/run/docker.sock ${FILIP_IMAGE}:${FILIP_TAG} 1>${STDOUT} 2>${STDERR}; then
    log_info " ❌"
    log_fatal "Failed to start FLECS"
  fi
  log_info " ✅"
}

apt_remove() {
  if ${DPKG} -l "${1}" 2>/dev/null | ${GREP} -q "^ii"; then
    log_debug "Removing ${1}..."
    if ${APT_GET} purge -y "${1}" >/dev/null 2>&1; then
      log_debug " OK"
    else
      log_fatal "Failed to remove ${1}"
    fi
  fi
}

remove_old_flecs() {
  if [ -z "${APT_GET}" ]; then
    return 0
  fi

  apt_remove flecs-webapp
  apt_remove flecs
}

if [ -z "${FLECS_TESTING}" ]; then
  parse_args "$@"
  banner

  # ensure running as root
  if [ ${EUID} -ne 0 ]; then
    log_error "${ME} needs to run as root"
    if ! have sudo; then
      log_fatal "Please login as root user and restart installation"
    else
      if confirm_yn "Restart using sudo"; then
        exec ${SUDO} "${SCRIPTNAME}" --no-banner "${ARGS[@]}"
      else
        log_fatal "Cannot continue installation without root privileges"
      fi
    fi
  fi

  detect_tools
  verify_tools
  detect_os
  verify_os

  welcome

  # print warning for unsupported systems and wait for confirmation, if not unattended
  if [ "${EXPERIMENTAL}" = "true" ]; then
    log_warning "Your operating system is not officially supported by the installer."
    if [ -n "${OS}" ]; then
      if [ -n "${NAME}" ]; then
        log_warning "    Name: ${NAME} (${OS})"
      else
        log_warning "    OS: ${OS}"
      fi
    else
      if [ -n "${NAME}" ]; then
        log_warning "    Name: ${NAME}"
      fi
    fi
    [ -n "${OS_VERSION}" ] && log_warning "    Version: ${OS_VERSION}" || log_warning "    Version: unknown"
    echo >&2

    log_warning "Installation might still succeed, depending on your exact system configuration."
    log_warning "No changes will be made to your system on failure, so it is usually safe to"
    log_warning "attempt installation anyway."
    confirm "Press ↵ to install or Ctrl-C to cancel."
  fi

  echo

  # make sure device is online
  check_connectivity

  ensure_docker
  determine_docker_version
  verify_docker_version

  # query latest FLECS version online
  determine_latest_version

  remove_old_flecs

  start_flecs
fi
EOF

SCRIPTNAME=$(readlink -f "${0}")
if [ "${SCRIPTNAME}" != "/tmp/filip.sh" ]; then
  chmod +x /tmp/filip.sh
  if (exec >/dev/null 2>&1 3</dev/tty); then
    exec /tmp/filip.sh "$@" </dev/tty
  else
    exec /tmp/filip.sh "$@" 0<&-
  fi
fi
