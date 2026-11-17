# Helpers for the installer tests, sourced by run.sh. POSIX sh.
#
# Every test runs in its own subshell with a fresh sandbox directory ${T}:
#   ${T}/bin         stubs that shadow real tools, first in PATH
#   ${T}/log         what the stubs were called with (see test/stubs)
#   ${T}/os-release  the os-release file the installer reads
#   ${T}/selinux     the SELinux mode, missing by default (see selinux_mode)
# After run_installer, ${T}/stdout, ${T}/stderr and ${T}/exit hold its results.
#
# Variables set by run.sh:
#   TEST_DIR   the test directory
#   TEST_TMP   temporary directory of this test run
#   REAL_BIN   directory with links to the real tools, minus the stubbed ones
#   INSTALLER  the inner installer script, run with the shell under test
#   TEST_SHELL path of the shell under test

STUBBED_TOOLS="apt-get curl docker dpkg id podman sudo systemctl wget"

# create the sandbox and set defaults: root on Debian 13 (amd64), online,
# with Docker installed and running
setup() {
  T=$(mktemp -d "${TEST_TMP}/test.XXXXXX")
  mkdir "${T}/bin" "${T}/log"
  cp "${TEST_DIR}/stubs/"* "${T}/bin/"
  : > "${T}/log/docker-running"
  os_release debian 13 trixie "Debian GNU/Linux"

  FAKE_UID=0
  FAKE_ARCH=amd64
  FAKE_ONLINE=1
  FAKE_LATEST_CORE=v5.6.0-red-deer
  FAKE_LATEST_WEBAPP=v5.6.1
  FAKE_DOCKER_CLIENT="Docker version 27.3.1, build ce12230"
  FAKE_DOCKER_API=1.47
  FAKE_DOCKER_SECURITY_OPTIONS='["name=apparmor","name=seccomp,profile=builtin"]'
  FAKE_DOCKER_PULL_EXIT=0
  FAKE_DOCKER_RUN_EXIT=0
  FAKE_DOCKER_SERVICE=0
  FAKE_INSTALLED_PACKAGES=""
}

# os_release ID VERSION_ID CODENAME NAME: write the os-release file. Empty
# values are left out.
os_release() {
  {
    [ -n "${1}" ] && printf 'ID=%s\n' "${1}"
    [ -n "${2}" ] && printf 'VERSION_ID="%s"\n' "${2}"
    [ -n "${3}" ] && printf 'VERSION_CODENAME=%s\n' "${3}"
    [ -n "${4}" ] && printf 'NAME="%s"\n' "${4}"
  } > "${T}/os-release"
}

# selinux_mode 0|1: SELinux is permissive (0) or enforcing (1)
selinux_mode() {
  printf '%s\n' "${1}" > "${T}/selinux"
}

# remove_stub NAME...: make tools unavailable
remove_stub() {
  for STUB in "$@"; do
    rm -f "${T}/bin/${STUB}"
  done
}

# hide_tool NAME...: make real tools unavailable to the installer
hide_tool() {
  mkdir "${T}/real-bin"
  for TOOL in "${REAL_BIN}"/*; do
    case " $* " in
      *" ${TOOL##*/} "*)
        continue
        ;;
    esac
    ln -s "$(readlink "${TOOL}")" "${T}/real-bin/${TOOL##*/}"
  done
  REAL_BIN="${T}/real-bin"
}

# docker_stopped: docker is installed, but the daemon is not running
docker_stopped() {
  rm -f "${T}/log/docker-running"
}

# run_installer ARGS...: run the installer in a clean environment without a
# tty and record its results. stdout and stderr are pipes, as with --verbose
# the installer opens /dev/stdout and /dev/stderr, which truncates files.
run_installer() {
  { { _run_installer "$@" 3>&-; echo "$?" > "${T}/exit"; } 2>&1 1>&3 3>&- \
    | cat > "${T}/stderr"; } 3>&1 | cat > "${T}/stdout"
}
_run_installer() {
  env -i \
    PATH="${T}/bin:${REAL_BIN}" \
    LOG="${T}/log" \
    STUBS="${T}/bin" \
    STUB_SOURCE="${TEST_DIR}/stubs" \
    FILIP_TEST_OS_RELEASE="${T}/os-release" \
    FILIP_TEST_SELINUX_ENFORCE="${T}/selinux" \
    FAKE_UID="${FAKE_UID}" \
    FAKE_ARCH="${FAKE_ARCH}" \
    FAKE_ONLINE="${FAKE_ONLINE}" \
    FAKE_LATEST_CORE="${FAKE_LATEST_CORE}" \
    FAKE_LATEST_WEBAPP="${FAKE_LATEST_WEBAPP}" \
    FAKE_DOCKER_CLIENT="${FAKE_DOCKER_CLIENT}" \
    FAKE_DOCKER_API="${FAKE_DOCKER_API}" \
    FAKE_DOCKER_SECURITY_OPTIONS="${FAKE_DOCKER_SECURITY_OPTIONS}" \
    FAKE_DOCKER_PULL_EXIT="${FAKE_DOCKER_PULL_EXIT}" \
    FAKE_DOCKER_RUN_EXIT="${FAKE_DOCKER_RUN_EXIT}" \
    FAKE_DOCKER_SERVICE="${FAKE_DOCKER_SERVICE}" \
    FAKE_INSTALLED_PACKAGES="${FAKE_INSTALLED_PACKAGES}" \
    "${INSTALLER}" "$@" < /dev/null
}

# in_shell CODE: run CODE with the shell under test, after sourcing the
# installer's functions. Output goes to stdout.
in_shell() {
  env -i PATH="${REAL_BIN}" FLECS_TESTING=1 INSTALLER="${INSTALLER}" \
    "${TEST_SHELL}" -c '. "${INSTALLER}"; SORT=sort; HEAD=head; '"${1}" 2>&1
}

fail() {
  printf 'FAILED: %s\n' "$*"
  exit 1
}

# show the results of the last installer run, for failure messages
show_run() {
  for F in exit stdout stderr; do
    printf '%s\n' "--- ${F}:"
    cat "${T}/${F}" 2>/dev/null
  done
}

assert_exit() {
  if [ "$(cat "${T}/exit")" != "${1}" ]; then
    show_run
    fail "expected exit code ${1}, got $(cat "${T}/exit")"
  fi
}

# assert_output stdout|stderr TEXT: the output contains TEXT
assert_output() {
  if ! grep -qF -- "${2}" "${T}/${1}"; then
    show_run
    fail "${1} does not contain: ${2}"
  fi
}

# assert_no_output stdout|stderr TEXT: the output does not contain TEXT
assert_no_output() {
  if grep -qF -- "${2}" "${T}/${1}"; then
    show_run
    fail "${1} unexpectedly contains: ${2}"
  fi
}

# assert_file FILE: FILE has exactly the content given on stdin
assert_file() {
  cat > "${T}/expected"
  if [ ! -e "${1}" ]; then
    show_run
    fail "${1} does not exist"
  fi
  if ! diff -u "${T}/expected" "${1}"; then
    fail "unexpected content of ${1##*/}"
  fi
}

# assert_missing FILE: FILE does not exist, e.g. a stub was not called
assert_missing() {
  if [ -e "${1}" ]; then
    show_run
    fail "${1##*/} exists, but should not"
  fi
}

# assert_eq EXPECTED ACTUAL
assert_eq() {
  if [ "${1}" != "${2}" ]; then
    printf '%s\n' "--- expected:" "${1}" "--- actual:" "${2}"
    fail "values differ"
  fi
}
