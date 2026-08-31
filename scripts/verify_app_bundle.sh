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

# The generated accessors are the only place the resolution logic is visible, so
# their absence is a failure rather than something to warn about and skip: a
# check that quietly passes when it cannot run is worse than no check at all.
if [ ! -d "$derived" ]; then
  echo "No build directory at $derived — run ./scripts/build_app.sh first" >&2
  echo "(the generated resource accessors are needed to verify the bundle)" >&2
  exit 1
fi

echo "▸ checking $app"

# 0. The bundle under test must be the one this build directory produced.
#
#    Everything below reasons about the .app using accessors read out of
#    $derived. If the two come from different builds, the check reports on a
#    bundle it never actually inspected — and it passes: pointing it at the
#    released v0.1.0 bundle, the one that crashes on every machine but its
#    build host, was how this hole was found.
built="$(find "$derived/Build/Products" -maxdepth 2 -name "$(basename "$app")" -print -quit 2>/dev/null)"
if [ -z "$built" ]; then
  fail "$derived produced no $(basename "$app") to compare against"
elif ! cmp -s "$built/Contents/MacOS/AgentNotch" "$app/Contents/MacOS/AgentNotch"; then
  fail "$app was not produced by $derived — its accessors describe a different build"
fi

# 1. Nothing may sit at the bundle root. This is where SwiftPM's accessor looks
#    for its resource bundle, and it is exactly the placement codesign rejects
#    with "unsealed contents present in the bundle root". Anything here means
#    someone tried to satisfy the accessor and broke signing instead.
root_extras="$(find "$app" -mindepth 1 -maxdepth 1 ! -name Contents)"
if [ -n "$root_extras" ]; then
  fail "unsealed contents at the bundle root:"
  printf '      %s\n' $root_extras >&2
fi

# 2. Every resource bundle a compiled accessor asks for must be in
#    Contents/Resources, which is what Xcode's accessor searches through
#    Bundle.main.resourceURL.
#
#    The expected names are read out of the generated accessors rather than
#    listed here, so a newly added dependency is covered without anyone
#    remembering to update this script.
expected_bundles="$(
  find "$derived" -name resource_bundle_accessor.swift -exec \
    sed -n 's/.*let bundleName = "\([^"]*\)".*/\1/p' {} + | sort -u
)"
if [ -z "$expected_bundles" ]; then
  fail "no resource accessors found under $derived — was the app actually built?"
fi
for bundle in $expected_bundles; do
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
while IFS= read -r accessor; do
  if ! grep -q "Bundle.main.resourceURL" "$accessor"; then
    fail "accessor does not search Contents/Resources: ${accessor#"$derived"/}"
  fi
  # The build directory of whoever compiled it. Present in every SwiftPM
  # accessor, absent from every Xcode one, and the reason v0.1.0 passed every
  # check on the build machine and crashed on all the others.
  #
  # Matched as "any string literal starting at the filesystem root" rather than
  # by listing the directories a build might live under: /Users covers this
  # machine and GitHub's runners, but /Volumes, /opt and /workspace are just as
  # possible, and a check that has to enumerate them is one hosting change away
  # from silently passing. Nor is it tied to the `let x = "/..."` shape, so a
  # path reaching the accessor as URL(fileURLWithPath:) or through any other
  # spelling is caught too.
  if grep -qE '"/[A-Za-z]' "$accessor"; then
    fail "accessor hardcodes an absolute build path: ${accessor#"$derived"/}"
  fi
done < <(find "$derived" -name resource_bundle_accessor.swift)

if [ "$failures" -gt 0 ]; then
  echo "✘ $failures problem(s): this bundle would not run on another Mac" >&2
  exit 1
fi
echo "✓ resources resolve from Contents/Resources"
