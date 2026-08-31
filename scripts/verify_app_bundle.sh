#!/usr/bin/env bash
# Check that the built .app can actually find its resources on someone else's Mac.
#
# This is the check that would have caught the v0.1.0 release, which crashed
# 0.2s after launch on every machine except the one that built it. Nothing about
# that failure is visible locally: SwiftPM's resource accessor falls back to the
# absolute build directory baked into the binary, which exists for whoever
# compiled it and nowhere else. Run against a bundle built by scripts/build_app.sh.
#
#   ./scripts/verify_app_bundle.sh [path/to/AgentNotch.app]
set -euo pipefail

cd "$(dirname "$0")/.."

app="${1:-build/AgentNotch.app}"
derived="xcode/.xcode-build"
failures=0

fail() {
  echo "  ✘ $1" >&2
  failures=$((failures + 1))
}

if [ ! -d "$app" ]; then
  echo "No bundle at $app — run ./scripts/build_app.sh first" >&2
  exit 1
fi

echo "▸ checking $app"

# 1. Nothing may sit at the bundle root. This is where SwiftPM's accessor looks
#    for its resource bundle, and it is exactly the placement codesign rejects
#    with "unsealed contents present in the bundle root". Anything here means
#    someone tried to satisfy the accessor and broke signing instead.
root_extras="$(find "$app" -mindepth 1 -maxdepth 1 ! -name Contents)"
if [ -n "$root_extras" ]; then
  fail "unsealed contents at the bundle root:"
  printf '      %s\n' $root_extras >&2
fi

# 2. Every resource bundle belongs in Contents/Resources, which is what Xcode's
#    accessor searches through Bundle.main.resourceURL.
for bundle in AgentNotch_AgentNotch AgentNotch_AgentNotchCore Highlighter_Highlighter \
  KeyboardShortcuts_KeyboardShortcuts; do
  if [ ! -d "$app/Contents/Resources/$bundle.bundle" ]; then
    fail "missing Contents/Resources/$bundle.bundle"
  fi
done

# 3. The files the code actually reads out of those bundles. A bundle that is
#    present but empty resolves and then fails at the point of use. Searched
#    rather than addressed by path: Xcode nests them under Contents/Resources
#    while `swift build` leaves them flat, and either layout is fine here.
check_inside() {
  local bundle="$1" file="$2"
  if [ -z "$(find "$app/Contents/Resources/$bundle.bundle" -name "$file" -print -quit 2>/dev/null)" ]; then
    fail "$bundle.bundle does not contain $file"
  fi
}

# Read by Highlighter.init?() and setTheme, i.e. every rendered code block.
check_inside Highlighter_Highlighter "highlight.min.js"
check_inside Highlighter_Highlighter "github-dark.css"
# Every user-visible string in the app and in Core.
for language in en ja; do
  check_inside AgentNotch_AgentNotch "$language.lproj"
  check_inside AgentNotch_AgentNotchCore "$language.lproj"
done

# 4. The CLI ships inside the bundle, because that is where the installed hooks
#    point, and it links AgentNotchCore's resources the same way the app does.
if [ ! -x "$app/Contents/MacOS/agent-notch" ]; then
  fail "missing Contents/MacOS/agent-notch"
fi

# 5. No accessor may resolve resources through Bundle.main.bundleURL alone.
#
#    Xcode generates a candidate list that starts at Bundle.main.resourceURL;
#    `swift build` generates two hardcoded paths, one of which is this machine's
#    build directory. If a SwiftPM-generated accessor ever ends up compiled into
#    the app, the binary works here and traps everywhere else — so check the
#    generated sources rather than trusting which tool was invoked.
if [ -d "$derived" ]; then
  while IFS= read -r accessor; do
    if ! grep -q "Bundle.main.resourceURL" "$accessor"; then
      fail "accessor does not search Contents/Resources: ${accessor#"$derived"/}"
    fi
  done < <(find "$derived" -name resource_bundle_accessor.swift)
else
  echo "  ! $derived is absent, skipping the generated-accessor check" >&2
fi

if [ "$failures" -gt 0 ]; then
  echo "✘ $failures problem(s): this bundle would not run on another Mac" >&2
  exit 1
fi
echo "✓ resources resolve from Contents/Resources"
