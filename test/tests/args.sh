# Command line arguments

test_args_help() {
  run_installer --help
  assert_exit 0
  assert_output stdout "Usage: ${INSTALLER} [options]"
  assert_output stdout "--otel-export-destination <url>"
  assert_missing "${T}/log/docker"
}

test_args_unknown_option() {
  run_installer --yes --bogus
  assert_exit 1
  assert_output stderr "Unknown option: --bogus"
  assert_output stdout "Usage:"
}

test_args_missing_values() {
  for OPTION in --core-version --webapp-version --filip-version \
      --floxy-version --fence-version --whitelabel --http-port --https-port \
      --core-env --floxy-env --webapp-env --fence-env \
      --otel-collector-version --otel-export-destination; do
    run_installer --yes "${OPTION}"
    assert_exit 1
    assert_output stderr "argument ${OPTION} requires a value"
  done
}

test_args_otel_needs_destination() {
  run_installer --yes --install-otel-collector
  assert_exit 1
  assert_output stderr "argument --otel-export-destination is required with --install-otel-collector"
}

test_args_offline_needs_versions() {
  run_installer --yes --offline --core-version 5.6.0
  assert_exit 1
  assert_output stderr "arguments --core-version and --webapp-version are required with --offline"
}

test_args_webapp_env_without_webapp() {
  run_installer --yes --webapp-version none --webapp-env A=1
  assert_exit 1
  assert_output stderr "argument --webapp-env cannot be used together with --webapp-version none"
}
