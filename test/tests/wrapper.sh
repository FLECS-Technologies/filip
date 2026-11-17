# The outer script, as run by curl -fsSL install.flecs.tech | sh -s -- ...
# It writes /tmp/filip.sh like a real installation and runs it with /bin/sh.

test_wrapper_piped_into_shell() {
  if [ -e /tmp/filip.sh ] && [ ! -w /tmp/filip.sh ]; then
    echo "skipped: /tmp/filip.sh is not writable"
    return 0
  fi
  printf '#!/bin/sh\nexec "%s" -s -- "$@" < "%s/filip.sh"\n' \
    "${TEST_SHELL}" "${REPO_DIR}" > "${T}/piped"
  chmod +x "${T}/piped"
  INSTALLER="${T}/piped"
  run_installer --yes --no-banner --core-env 'A=x y'
  assert_exit 0
  assert_output stdout "Starting FLECS... ✅"
  assert_output "log/docker-run" 'FILIP_CORE_ENV=A=x\ y'
  assert_eq "#!/bin/sh" "$(head -n 1 /tmp/filip.sh)"
}
