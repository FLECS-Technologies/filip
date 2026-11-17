# Installing, starting and verifying Docker

test_docker_install_debian_13() {
  remove_stub docker
  run_installer --yes --core-env 'A=x y' --https-port 8443
  assert_exit 0
  assert_file "${T}/log/apt-get" <<'EOF'
update
-y install --reinstall --no-install-recommends docker.io docker-cli
EOF
  assert_output stdout "Installing Docker... ✅"
  assert_output stdout "Restarting installer..."
  # the restarted installer keeps the original arguments
  assert_output "log/docker-run" "FLOXY_HTTPS_PORT=8443"
  assert_output "log/docker-run" 'FILIP_CORE_ENV=A=x\ y'
}

test_docker_install_debian_12() {
  os_release debian 12 bookworm "Debian GNU/Linux"
  remove_stub docker
  run_installer --yes
  assert_exit 0
  assert_output "log/apt-get" "-y install --reinstall --no-install-recommends docker.io"
  assert_no_output "log/apt-get" "docker-cli"
}

test_docker_install_ubuntu() {
  os_release ubuntu 24.04 noble Ubuntu
  remove_stub docker
  run_installer --yes
  assert_exit 0
  assert_no_output "log/apt-get" "docker-cli"

  setup
  os_release ubuntu 25.04 plucky Ubuntu
  remove_stub docker
  run_installer --yes
  assert_exit 0
  assert_output "log/apt-get" "docker.io docker-cli"
}

test_docker_install_restart_without_banner() {
  remove_stub docker
  run_installer --yes
  assert_exit 0
  if [ "$(grep -c "FLECS Installer for Linux Platforms" "${T}/stdout")" != "1" ]; then
    show_run
    fail "banner printed more than once"
  fi
}

test_docker_install_only_on_debian() {
  os_release alpine 3.22.0 "" "Alpine Linux"
  remove_stub docker
  run_installer --yes
  assert_exit 1
  assert_output stderr "Automatic Docker installation is only supported on Debian/Ubuntu-based systems"
  assert_missing "${T}/log/apt-get"
}

test_docker_install_not_offline() {
  remove_stub docker
  run_installer --yes --offline --core-version 5.6.0 --webapp-version 5.6.1
  assert_exit 1
  assert_output stderr "Please install and start Docker before running FILiP with --offline"
  assert_missing "${T}/log/apt-get"
}

test_docker_start_service() {
  docker_stopped
  FAKE_DOCKER_SERVICE=1
  run_installer --yes
  assert_exit 0
  assert_output stdout "Starting Docker service... ✅"
  assert_output "log/systemctl" "enable --now docker"
  assert_missing "${T}/log/apt-get"
}

test_docker_install_without_service() {
  docker_stopped
  run_installer --yes
  assert_exit 0
  assert_no_output stdout "Starting Docker service"
  assert_output stdout "Installing Docker... ✅"
}

test_docker_too_old_client() {
  FAKE_DOCKER_CLIENT="Docker version 20.10.9, build c2ea9bc"
  run_installer --yes
  assert_exit 1
  assert_output stderr "FLECS requires at least Docker client version 20.10.10"
  assert_output stderr "The available client version is 20.10.9"
}

test_docker_too_old_api() {
  FAKE_DOCKER_API=1.40
  run_installer --yes
  assert_exit 1
  assert_output stderr "FLECS requires at least Docker API version 1.41"
}

test_docker_otel_needs_api_1_44() {
  FAKE_DOCKER_API=1.43
  run_installer --yes --install-otel-collector --otel-export-destination https://otel.example.com
  assert_exit 1
  assert_output stderr "The otel-collector requires at least Docker API version 1.44 (Docker 25)"
  run_installer --yes
  assert_exit 0
}

test_docker_podman_unsupported() {
  FAKE_DOCKER_CLIENT="podman version 4.9.3"
  run_installer --yes
  assert_exit 1
  assert_output stderr "Podman is currently unsupported."
}

test_docker_version_without_sed() {
  hide_tool sed
  run_installer --yes --core-version 5.6.0 --webapp-version 5.6.1
  if echo x | grep -qP 'x' 2>/dev/null; then
    assert_exit 0
    assert_output stdout "Docker... ✅ 27.3.1 (API 1.47)"
  else
    # BusyBox grep has no -P
    assert_exit 1
    assert_output stderr "Could not determine Docker version."
  fi
}

test_docker_selinux_enforcing_with_docker_selinux() {
  selinux_mode 1
  FAKE_DOCKER_SECURITY_OPTIONS='["name=seccomp,profile=builtin","name=selinux"]'
  run_installer --yes
  assert_exit 1
  assert_file "${T}/stderr" <<'EOT'
❌ SELinux is enforcing and enabled in the Docker daemon, which prevents FLECS from accessing Docker
❌ This is the case with Fedora's moby-engine package
❌ Please install Docker CE instead: https://docs.docker.com/engine/install/
EOT
  assert_missing "${T}/log/docker-run"
}

test_docker_selinux_enforcing_without_docker_selinux() {
  selinux_mode 1
  run_installer --yes
  assert_exit 0
  assert_file "${T}/stderr" < /dev/null
  assert_output "log/docker" "info --format {{json .SecurityOptions}}"
}

test_docker_selinux_permissive() {
  selinux_mode 0
  FAKE_DOCKER_SECURITY_OPTIONS='["name=selinux"]'
  run_installer --yes
  assert_exit 0
  assert_no_output "log/docker" "info"
}
