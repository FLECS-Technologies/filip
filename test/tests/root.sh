# Running as a regular user

test_root_restart_with_sudo() {
  FAKE_UID=1000
  run_installer --yes --core-env 'A=x y' --core-env "B=it's" --fence-env 'C=$HOME *'
  assert_exit 0
  assert_output stderr "FILiP needs to run as root"
  assert_file "${T}/log/sudo" <<EOF
${INSTALLER}
--no-banner
--yes
--core-env
A=x y
--core-env
B=it's
--fence-env
C=\$HOME *
EOF
  assert_missing "${T}/log/docker"
}

test_root_sudo_needs_confirmation() {
  FAKE_UID=1000
  run_installer
  assert_exit 1
  assert_output stderr "User input required but no tty allocated."
  assert_missing "${T}/log/sudo"
}

test_root_without_sudo() {
  FAKE_UID=1000
  remove_stub sudo
  run_installer --yes
  assert_exit 1
  assert_output stderr "Please login as root user and restart installation"
}
