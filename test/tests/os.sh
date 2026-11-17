# Detection and verification of the operating system and architecture

test_os_supported_versions() {
  for VERSION in "11 bullseye" "12 bookworm" "13 trixie"; do
    os_release debian ${VERSION} "Debian GNU/Linux"
    run_installer --yes
    assert_exit 0
    assert_no_output stderr "unsupported version"
  done
  os_release ubuntu 24.04 noble Ubuntu
  run_installer --yes
  assert_exit 0
  assert_output stdout "Installing FLECS on Ubuntu 24.04 (noble) [amd64]"
}

test_os_newer_version_continues() {
  os_release debian 14 forky "Debian GNU/Linux"
  run_installer --yes
  assert_exit 0
  assert_file "${T}/stderr" <<'EOF'
⚠  You are running an unsupported version of your OS. Supported versions are
⚠      11 (bullseye)
⚠      12 (bookworm)
⚠      13 (trixie)
⚠  Your version 14 (forky) seems more recent, so continuing anyway
EOF
}

test_os_outdated_version_stops() {
  os_release debian 10 buster "Debian GNU/Linux"
  run_installer --yes
  assert_exit 1
  assert_file "${T}/stderr" <<'EOF'
❌ You are running an outdated version 10 (buster) of your OS. Supported versions are
❌     11 (bullseye)
❌     12 (bookworm)
❌     13 (trixie)
EOF
  assert_missing "${T}/log/docker"
}

test_os_versions_without_codenames() {
  os_release fedora 36 "" Fedora
  run_installer --yes
  assert_exit 1
  assert_file "${T}/stderr" <<'EOF'
⚠  Fedora-based distributions that use podman are not yet supported. Please ensure
⚠  you have Docker installed instead of podman, or follow the instructions found at
⚠  https://docs.docker.com/engine/install/fedora/ to install Docker.
⚠  If you cannot use Docker for some reason, please contact us at info@flecs.tech
⚠  for further information about podman support.
❌ You are running an outdated version 36 of your OS. Supported versions are
❌     37
❌     38
EOF
}

test_os_ubuntu_versions_compare_numerically() {
  os_release ubuntu 26.10 "" Ubuntu
  run_installer --yes
  assert_exit 0
  assert_output stderr "Your version 26.10 seems more recent, so continuing anyway"
  os_release ubuntu 18.04 bionic Ubuntu
  run_installer --yes
  assert_exit 1
  assert_output stderr "You are running an outdated version 18.04 (bionic) of your OS"
}

test_os_arch_rolling_release() {
  os_release arch "" "" "Arch Linux"
  run_installer --yes
  assert_exit 0
  assert_output stdout "Installing FLECS on Arch Linux [amd64]"
  assert_no_output stderr "not officially supported"
}

test_os_unknown_is_experimental() {
  os_release alpine 3.22.0 "" "Alpine Linux"
  run_installer --yes
  assert_exit 0
  assert_output stderr "Your operating system is not officially supported by the installer."
  assert_output stderr "    Name: Alpine Linux (alpine)"
  assert_output stderr "    Version: unknown"
}

test_os_missing_os_release() {
  rm "${T}/os-release"
  run_installer --yes
  assert_exit 0
  assert_output stdout "Installing FLECS on your device [amd64]"
  assert_output stderr "Your operating system is not officially supported by the installer."
}

test_os_parse_with_grep_only() {
  # without sed, the installer falls back to grep -P, which BusyBox lacks
  if ! echo x | grep -qP 'x' 2>/dev/null; then
    return 0
  fi
  hide_tool sed
  run_installer --yes
  assert_exit 0
  assert_output stdout "Installing FLECS on Debian GNU/Linux 13 (trixie) [amd64]"
}

test_os_without_sed_and_grep() {
  # neither os-release nor the Docker version can be parsed
  hide_tool sed grep
  run_installer --yes
  assert_exit 1
  assert_output stdout "Installing FLECS on your device [amd64]"
  assert_output stderr "Could not determine Docker version."
}

test_os_arch_from_uname() {
  remove_stub dpkg
  run_installer --yes
  assert_exit 0
  assert_output stdout "[$(case $(uname -m) in x86_64) echo amd64;; aarch64) echo arm64;; *) uname -m;; esac)]"
}

test_os_arch_arm64() {
  FAKE_ARCH=arm64
  run_installer --yes
  assert_exit 0
  assert_output stdout "[arm64]"
}

test_os_arch_unsupported() {
  FAKE_ARCH=armhf
  run_installer --yes
  assert_exit 1
  assert_output stderr "Unsupported machine type: armhf"
}
