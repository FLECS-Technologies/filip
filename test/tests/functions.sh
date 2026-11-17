# Helper functions of the installer, run in the shell under test

test_functions_cmp_less() {
  assert_eq "yes,no,no,yes,no,yes,no," "$(in_shell '
    for PAIR in 1.2.3:1.10.0 1.10.0:1.2.3 2:2 12:13 25.04:24.04 1.41:1.44 20.10.10:20.10.9; do
      if cmp_less "${PAIR%%:*}" "${PAIR#*:}"; then printf "yes,"; else printf "no,"; fi
    done')"
}

test_functions_strip_version() {
  assert_eq "5.2.0,5.2.0,5.2.0,5.2.0," "$(in_shell '
    printf "%s," "$(strip_version v5.2.0-red-deer)" "$(strip_version 5.2.0)" \
      "$(strip_version v5.2.0)" "$(strip_version 5.2.0-red-deer)"')"
}

test_functions_is_plain_version() {
  assert_eq "1.2.3:yes,10.20.30:yes,01.2.3:yes,1.2:no,1.2.3.4:no,a.b.c:no,1..3:no,.1.2:no,1.2.:no,1.2.3-:no,:no," "$(in_shell '
    for V in 1.2.3 10.20.30 01.2.3 1.2 1.2.3.4 a.b.c 1..3 .1.2 1.2. 1.2.3- ""; do
      if is_plain_version "${V}"; then printf "%s:yes," "${V}"; else printf "%s:no," "${V}"; fi
    done
    is_plain_version "1.2.3 " && printf "space"')"
}

test_functions_add_env_pair() {
  # each pair on its own line: [value] -> [escaped]
  OUTPUT=$(in_shell '
    for VALUE in "A=x y" "B=back\\slash" "C=\\" "D= " "E=\\\\  \\\\" "F=*?[a]" "G=%s%d\\n" "H=-e" "I=ä ö"; do
      PAIRS=""
      add_env_pair PAIRS "${VALUE}"
      printf "[%s] -> [%s]\n" "${VALUE}" "${PAIRS}"
    done
    PAIRS=""
    add_env_pair PAIRS "A=1"
    add_env_pair PAIRS "B=2 3"
    printf "joined: [%s]\n" "${PAIRS}"
    PAIRS=""
    add_env_pair PAIRS "$(printf "N=1\n2 3")"
    printf "newline: [%s]\n" "${PAIRS}"')
  assert_eq '[A=x y] -> [A=x\ y]
[B=back\slash] -> [B=back\\slash]
[C=\] -> [C=\\]
[D= ] -> [D=\ ]
[E=\\  \\] -> [E=\\\\\ \ \\\\]
[F=*?[a]] -> [F=*?[a]]
[G=%s%d\n] -> [G=%s%d\\n]
[H=-e] -> [H=-e]
[I=ä ö] -> [I=ä\ ö]
joined: [A=1 B=2\ 3]
newline: [N=1
2\ 3]' "${OUTPUT}"
}

test_functions_have() {
  OUTPUT=$(in_shell '
    have sort && printf "SORT=%s\n" "${SORT##*/}"
    have no-such.tool-x || printf "NO_SUCH_TOOL_X=[%s]\n" "${NO_SUCH_TOOL_X}"
    CAT=preset; have cat; printf "CAT=%s\n" "${CAT}"
    f() { local TOOL=other; have tr; }; f; printf "TR=%s\n" "${TR##*/}"')
  assert_eq 'SORT=sort
NO_SUCH_TOOL_X=[]
CAT=preset
TR=tr' "${OUTPUT}"
}

test_functions_log_prints_literally() {
  OUTPUT=$(in_shell '
    log_info -n "a\tb"; log_info " c\nd"
    log_info "-e"
    log_info -- "-n"
    log_warning "w\c" 2>&1
    log_error -n "e" 2>&1; log_error "%s" 2>&1
    (LOG_DEBUG=1 log_debug "dbg")
    (LOG_DEBUG=1 log_debug -q -n "quiet"); echo
    log_debug "hidden"')
  assert_eq 'a\tb c\nd
-e
-- -n
⚠  w\c
❌ e❌ %s
*** Debug: dbg
quiet' "${OUTPUT}"
}

test_functions_print_os_versions() {
  OUTPUT=$(in_shell 'print_os_versions log_info 11:bullseye 37 20.04:focal')
  assert_eq '    11 (bullseye)
    37
    20.04 (focal)' "${OUTPUT}"
}
