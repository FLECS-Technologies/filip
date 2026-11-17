#!/bin/sh
# Run the installer tests.
#
# Usage: test/run.sh [SHELL...]
#
# Runs all tests once for every given shell (default: sh), which runs the
# installer. The tests replace docker, curl, apt-get and other tools with
# stubs from test/stubs, so they neither need root nor change the system.
#
# Set TEST_FILTER to a pattern to only run matching tests, e.g.
# TEST_FILTER='test_args_*' test/run.sh dash. Set TEST_KEEP=1 to keep the
# temporary files of the test run.
#
# Examples:
#   test/run.sh bash dash
#   docker run --rm -v "$PWD:/src" -w /src alpine test/run.sh   # BusyBox ash

TEST_DIR=$(cd "$(dirname "${0}")" && pwd)
REPO_DIR=$(dirname "${TEST_DIR}")

. "${TEST_DIR}/lib.sh"

TEST_TMP=$(mktemp -d)
if [ "${TEST_KEEP}" != "1" ]; then
  trap 'rm -rf "${TEST_TMP}"' EXIT
fi

# links to the real tools, without the ones the tests replace with stubs
REAL_BIN="${TEST_TMP}/real-bin"
mkdir "${REAL_BIN}"
OLD_IFS=${IFS}
IFS=:
for DIR in ${PATH}; do
  IFS=${OLD_IFS}
  for TOOL in "${DIR}"/*; do
    NAME=${TOOL##*/}
    case " ${STUBBED_TOOLS} " in
      *" ${NAME} "*)
        continue
        ;;
    esac
    if [ -f "${TOOL}" ] && [ -x "${TOOL}" ] && [ ! -e "${REAL_BIN}/${NAME}" ]; then
      ln -s "${TOOL}" "${REAL_BIN}/${NAME}"
    fi
  done
done
IFS=${OLD_IFS}

[ $# -gt 0 ] || set -- sh

PASSED=0
FAILED=0
FAILED_TESTS=""
for SHELL_NAME in "$@"; do
  TEST_SHELL=$(command -v "${SHELL_NAME}")
  if [ -z "${TEST_SHELL}" ]; then
    echo "Shell not found: ${SHELL_NAME}" >&2
    exit 2
  fi

  # extract the inner installer from filip.sh and run it with the shell
  # under test
  INSTALLER="${TEST_TMP}/installer-${SHELL_NAME##*/}.sh"
  {
    printf '#!%s\n' "${TEST_SHELL}"
    sed -n "/^cat <<'EOF' > \/tmp\/filip.sh\$/,/^EOF\$/p" "${REPO_DIR}/filip.sh" | sed '1,2d;$d'
  } > "${INSTALLER}"
  chmod +x "${INSTALLER}"

  echo "# ${SHELL_NAME} (${TEST_SHELL})"
  for FILE in "${TEST_DIR}"/tests/*.sh; do
    for TEST in $(sed -n 's/^\(test_[A-Za-z0-9_]*\)() {$/\1/p' "${FILE}"); do
      # shellcheck disable=SC2254
      case ${TEST} in
        ${TEST_FILTER:-*})
          ;;
        *)
          continue
          ;;
      esac
      if OUTPUT=$(. "${FILE}" && setup && "${TEST}" 2>&1); then
        PASSED=$((PASSED + 1))
        echo "ok   ${TEST}"
      else
        FAILED=$((FAILED + 1))
        FAILED_TESTS="${FAILED_TESTS} ${SHELL_NAME}:${TEST}"
        echo "FAIL ${TEST}"
        printf '%s\n' "${OUTPUT}" | sed 's/^/     /'
      fi
    done
  done
done

echo
echo "${PASSED} passed, ${FAILED} failed"
if [ "${FAILED}" -gt 0 ]; then
  for TEST in ${FAILED_TESTS}; do
    echo "  ${TEST}"
  done
  exit 1
fi
