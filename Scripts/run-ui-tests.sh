#!/bin/bash
# Runs the iPhone and Mac UI suites on this Mac, for a pull request's checks: CI runs them only
# nightly and on demand (ui-tests.yml), since a free runner is too slow for them on every push.
#
#   Scripts/run-ui-tests.sh          both suites
#   Scripts/run-ui-tests.sh ios      the iPhone suite on the QA simulator (SIM_NAME overrides it)
#   Scripts/run-ui-tests.sh mac      the Mac suite, which drives this Mac's pointer while it runs
#
# The Mac suite needs UI automation allowed once:
#   sudo automationmodetool enable-automationmode-without-authentication
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17 Pro (QA 27.2)}"
RESULTS="$(mktemp -d)"

# Local walkthroughs in NextExplorerUITests/QA are untracked screenshot tools, not checks.
SKIP=()
while read -r name; do
    SKIP+=("-skip-testing:NextExplorerUITests/${name}")
done < <(grep -hoE "^\s*(final )?class [A-Za-z]+" NextExplorerUITests/QA/*.swift 2>/dev/null | awk '{ print $NF }')

run() {
    local name="$1"
    shift
    echo "== ${name} UI tests, results in ${RESULTS}/${name}.xcresult"
    xcodebuild test \
        -workspace PackageTests.xcworkspace \
        -scheme NextExplorer \
        -only-testing:NextExplorerUITests \
        ${SKIP[@]+"${SKIP[@]}"} \
        -enableCodeCoverage NO \
        -resultBundlePath "${RESULTS}/${name}.xcresult" \
        "$@" | xcbeautify
}

run_ios() {
    run iPhone -destination "platform=iOS Simulator,name=${SIM_NAME}"
}

# Ad hoc signed without entitlements, as in CI: the App Group and keychain groups need a profile.
run_mac() {
    run Mac \
        -destination 'platform=macOS' \
        -parallel-testing-enabled NO \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
        CODE_SIGN_ENTITLEMENTS=
}

case "${1:-all}" in
    ios) run_ios ;;
    mac) run_mac ;;
    all) run_ios && run_mac ;;
    *) echo "Usage: $0 [ios|mac]" >&2; exit 2 ;;
esac
