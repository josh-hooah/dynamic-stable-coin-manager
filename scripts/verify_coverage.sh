#!/usr/bin/env bash
set -euo pipefail

NO_MATCH_COVERAGE_REGEX="${NO_MATCH_COVERAGE_REGEX:-script/|lib/|helpers/}"
REPORT_FILE="${COVERAGE_REPORT_FILE:-lcov.info}"

forge coverage --report lcov --no-match-coverage "$NO_MATCH_COVERAGE_REGEX" --report-file "$REPORT_FILE" >/tmp/dsm-coverage.log 2>&1 || {
  cat /tmp/dsm-coverage.log >&2
  exit 1
}

violations="$(awk '
BEGIN { file = ""; failed = 0 }
/^SF:/ { file = substr($0, 4); next }
/^DA:/ {
  split($0, parts, ":");
  split(parts[2], data, ",");
  line = data[1]; hits = data[2];
  if (hits == 0) {
    printf "uncovered line: %s:%s\n", file, line;
    failed = 1;
  }
}
/^BRDA:/ {
  split($0, parts, ":");
  split(parts[2], data, ",");
  line = data[1]; hits = data[4];
  if (hits == 0 || hits == "-") {
    printf "uncovered branch: %s:%s\n", file, line;
    failed = 1;
  }
}
END {
  if (failed == 0) {
    print "ok";
  }
}
' "$REPORT_FILE")"

if [[ "$violations" != "ok" ]]; then
  echo "Coverage verification failed (expecting 100% for tracked contracts)." >&2
  echo "$violations" >&2
  exit 1
fi

echo "Coverage verification passed: 100% line + branch coverage on tracked contracts."
