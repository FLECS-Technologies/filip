# Successful installations and the arguments passed to docker container run

test_install_latest() {
  run_installer --yes
  assert_exit 0
  # also catches errors like "[[: not found" in shells other than bash
  assert_file "${T}/stderr" < /dev/null
  assert_output stdout "Installing FLECS on Debian GNU/Linux 13 (trixie) [amd64]"
  assert_output stdout "FLECS core... ✅ v5.6.0-red-deer"
  assert_output stdout "FLECS webapp... ✅ v5.6.1"
  assert_output stdout "Starting FLECS... ✅"
  assert_file "${T}/log/docker-run" <<'EOF'
--detach
--name
flecs
-e
VERSION_CORE=v5.6.0-red-deer
-e
VERSION_WEBAPP=v5.6.1
-e
INSTALL_FENCE=1
--network
host
--restart
always
--volume
/run/docker.sock:/run/docker.sock
cr.flecs.tech/flecs/filip:latest
EOF
}

test_install_all_options() {
  run_installer --yes --no-banner --no-welcome \
    --core-version v5.6.0 --webapp-version 5.6.1 --fence-version 1.2.3 \
    --floxy-version 2.0 --filip-version 9.9 --whitelabel acme \
    --http-port 8080 --https-port 8443 \
    --install-otel-collector --otel-collector-version 0.1 \
    --otel-export-destination 'https://otel.example.com:4317/x y'
  assert_exit 0
  assert_no_output stdout "FLECS Installer for Linux Platforms"
  assert_no_output stdout "Installing FLECS on"
  # versions given on the command line are not looked up
  assert_file "${T}/log/curl" <<'EOF'
https://flecs.tech
EOF
  assert_file "${T}/log/docker-run" <<'EOF'
--detach
--name
flecs
-e
VERSION_CORE=v5.6.0
-e
VERSION_WEBAPP=5.6.1
-e
WHITELABEL=acme
-e
FLOXY_HTTP_PORT=8080
-e
FLOXY_HTTPS_PORT=8443
-e
VERSION_FENCE=1.2.3
-e
VERSION_FLOXY=2.0
-e
INSTALL_FENCE=1
-e
INSTALL_OTEL_COLLECTOR=1
-e
VERSION_OTEL_COLLECTOR=0.1
-e
OTEL_EXPORT_DESTINATION=https://otel.example.com:4317/x y
--network
host
--restart
always
--volume
/run/docker.sock:/run/docker.sock
cr.flecs.tech/flecs/filip:9.9
EOF
}

test_install_env_values_are_escaped() {
  run_installer --yes \
    --core-env 'A=x y' --core-env 'B=back\slash' --core-env "C=it's \"quoted\"" \
    --core-env 'D=$HOME *' --core-env 'E=-e' \
    --floxy-env 'F=1' --webapp-env 'W=a  b' --fence-env 'X=\ y'
  assert_exit 0
  assert_file "${T}/log/docker-run" <<'EOF'
--detach
--name
flecs
-e
VERSION_CORE=v5.6.0-red-deer
-e
VERSION_WEBAPP=v5.6.1
-e
INSTALL_FENCE=1
-e
FILIP_CORE_ENV=A=x\ y B=back\\slash C=it's\ "quoted" D=$HOME\ * E=-e
-e
FILIP_FLOXY_ENV=F=1
-e
FILIP_WEBAPP_ENV=W=a\ \ b
-e
FILIP_FENCE_ENV=X=\\\ y
--network
host
--restart
always
--volume
/run/docker.sock:/run/docker.sock
cr.flecs.tech/flecs/filip:latest
EOF
}

test_install_without_webapp() {
  run_installer --yes --webapp-version none
  assert_exit 0
  assert_no_output stdout "FLECS webapp..."
  assert_file "${T}/log/docker-run" <<'EOF'
--detach
--name
flecs
-e
VERSION_CORE=v5.6.0-red-deer
-e
INSTALL_WEBAPP=0
-e
INSTALL_FENCE=1
--network
host
--restart
always
--volume
/run/docker.sock:/run/docker.sock
cr.flecs.tech/flecs/filip:latest
EOF
}

test_install_dev_image() {
  run_installer --yes --dev
  assert_exit 0
  assert_output "log/docker" "image pull cr.flecs.tech/flecs/filip:dev"
}

test_install_core_without_fence() {
  run_installer --yes --core-version 5.5.0
  assert_exit 0
  assert_output "log/docker-run" "INSTALL_FENCE=0"
}

test_install_unparsable_core_version() {
  run_installer --yes --core-version nightly
  assert_exit 0
  assert_output stderr "Could not parse FLECS core version nightly"
  assert_output stderr "fence will be installed as system container"
  assert_output "log/docker-run" "INSTALL_FENCE=1"
}

test_install_too_old_core_version() {
  run_installer --yes --core-version 5.1.9
  assert_exit 1
  assert_output stderr "FILiP cannot install FLECS core 5.1.9"
  assert_output stderr "curl -fsSL install-old.flecs.tech | bash"
  assert_missing "${T}/log/docker-run"
}

test_install_otel_needs_core_5_5() {
  run_installer --yes --core-version 5.4.0 --install-otel-collector \
    --otel-export-destination https://otel.example.com
  assert_exit 1
  assert_output stderr "The otel-collector requires FLECS core 5.5.0 or later"
}

test_install_removes_old_packages() {
  FAKE_INSTALLED_PACKAGES="flecs flecs-webapp"
  run_installer --yes
  assert_exit 0
  assert_file "${T}/log/apt-get" <<'EOF'
purge -y flecs-webapp
purge -y flecs
EOF
}

test_install_failed_pull_continues() {
  FAKE_DOCKER_PULL_EXIT=1
  run_installer --yes
  assert_exit 0
  assert_output stdout "Pulling latest image... ⚠"
  assert_output stdout "Starting FLECS... ✅"
}

test_install_failed_start() {
  FAKE_DOCKER_RUN_EXIT=1
  run_installer --yes
  assert_exit 1
  assert_output stdout "Starting FLECS... ❌"
  assert_output stderr "Failed to start FLECS"
}

test_install_offline() {
  run_installer --yes --offline --core-version 5.6.0 --webapp-version 5.6.1
  assert_exit 0
  assert_output stdout "Internet connectivity... skipped (--offline)"
  assert_missing "${T}/log/curl"
}

test_install_offline_without_curl() {
  remove_stub curl wget
  run_installer --yes --offline --core-version 5.6.0 --webapp-version 5.6.1
  assert_exit 0
}

test_install_debug_output() {
  run_installer --yes --debug
  assert_exit 0
  assert_output stdout "*** Debug: Running with debug output"
  assert_output stdout "*** Debug: Looking for docker... found"
  assert_output stdout "*** Debug: Looking for systemctl... found"
}

test_install_without_tty_needs_yes() {
  run_installer
  assert_exit 1
  assert_output stderr "User input required but no tty allocated."
  assert_missing "${T}/log/docker-run"
}

test_install_syntax() {
  if ! OUTPUT=$("${TEST_SHELL}" -n "${INSTALLER}" 2>&1); then
    printf '%s\n' "${OUTPUT}"
    fail "syntax check with ${TEST_SHELL} -n failed"
  fi
}
