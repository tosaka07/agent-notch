#!/usr/bin/env bash
# Build the distributable ZIP and the matching Homebrew Cask.
#
# The app is signed with a Developer ID Application certificate under the
# hardened runtime, notarized by Apple, and stapled, so Gatekeeper accepts it
# on a machine that has never seen it and without a network round trip.
#
# Required environment:
#   CODESIGN_IDENTITY   Developer ID Application identity (name or SHA-1 hash)
#   NOTARY_KEY          path to the App Store Connect .p8 private key
#   NOTARY_KEY_ID       App Store Connect key id
#   NOTARY_ISSUER_ID    App Store Connect issuer id
#
# --skip-notarize signs but does not submit to Apple. It exists to check the
# signing path locally; the resulting ZIP must never be published, because
# without a stapled ticket Gatekeeper blocks the app on every other machine.
set -euo pipefail

cd "$(dirname "$0")/.."

build_version=""
build_number="1"
skip_notarize=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-version)
      build_version="${2:-}"
      shift 2
      ;;
    --build-number)
      build_number="${2:-}"
      shift 2
      ;;
    --skip-notarize)
      skip_notarize="1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$build_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "--build-version must use the form 1.2.3" >&2
  exit 1
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "--build-number must be a positive integer" >&2
  exit 1
fi

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  echo "CODESIGN_IDENTITY must name a Developer ID Application identity" >&2
  exit 1
fi
if [ -z "$skip_notarize" ]; then
  for required in NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER_ID; do
    if [ -z "${!required:-}" ]; then
      echo "$required must be set to notarize (or pass --skip-notarize)" >&2
      exit 1
    fi
  done
  if [ ! -f "$NOTARY_KEY" ]; then
    echo "NOTARY_KEY does not point at a file: $NOTARY_KEY" >&2
    exit 1
  fi
fi

release_name="AgentNotch-v$build_version"
artifact_name="$release_name-macos-arm64.zip"
release_root="dist/$release_name"
app="build/AgentNotch.app"
entitlements="AgentNotch/AgentNotch.entitlements"

echo "▸ building Agent Notch $build_version ($build_number)"
./scripts/build_app.sh release \
  --build-version "$build_version" \
  --build-number "$build_number"

# Refuses to go any further with a bundle whose resources would not resolve on
# another Mac — the failure mode that shipped as v0.1.0.
./scripts/verify_app_bundle.sh "$app"

plist="$app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")" = "$build_version"
test "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")" = "$build_number"
test "$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist")" = "26.0"
test "$(lipo -archs "$app/Contents/MacOS/AgentNotch")" = "arm64"
test "$(lipo -archs "$app/Contents/MacOS/agent-notch")" = "arm64"

echo "▸ signing with $CODESIGN_IDENTITY"
plutil -lint "$entitlements"

# Sign inside-out: the nested CLI first, then the bundle that contains it.
# Signing the bundle first would invalidate its seal the moment the CLI inside
# it is re-signed. --timestamp is not optional here; notarization rejects a
# signature without a secure timestamp.
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$CODESIGN_IDENTITY" \
  "$app/Contents/MacOS/agent-notch"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$entitlements" \
  --sign "$CODESIGN_IDENTITY" \
  "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements - "$app"

# Catch a signature that would fail notarization for an obvious reason, before
# spending a round trip to Apple on it. The output is captured once and matched
# with `case`, because piping into `grep -q` under `set -o pipefail` reports the
# SIGPIPE that kills codesign rather than what grep found.
signature_info="$(codesign -dvv "$app" 2>&1)"
printf '%s\n' "$signature_info"
case "$signature_info" in
  *"Signature=adhoc"*)
    echo "$app carries an ad-hoc signature" >&2
    exit 1
    ;;
esac
case "$signature_info" in
  *"Authority=Developer ID Application"*) ;;
  *)
    echo "$app is not signed by a Developer ID Application certificate" >&2
    exit 1
    ;;
esac

if [ -n "$skip_notarize" ]; then
  echo "▸ skipping notarization — the result is not distributable"
else
  echo "▸ submitting to Apple for notarization"
  # notarytool takes an archive, never a bare bundle, so the app travels inside
  # a throwaway ZIP. The ticket it returns is attached to the app itself, which
  # is why the distributable ZIP is only assembled after stapling.
  notary_dir="$(mktemp -d -t agentnotch-notary)"
  notary_zip="$notary_dir/AgentNotch.zip"
  submission="$notary_dir/submission.json"
  ditto -c -k --keepParent "$app" "$notary_zip"
  xcrun notarytool submit "$notary_zip" \
    --key "$NOTARY_KEY" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait \
    --timeout 30m \
    --output-format json \
    | tee "$submission"

  submission_id="$(plutil -extract id raw -o - -- "$submission")"
  submission_status="$(plutil -extract status raw -o - -- "$submission")"
  if [ "$submission_status" != "Accepted" ]; then
    # The submission log is the only place that says which binary or
    # entitlement Apple objected to, so surface it before failing.
    echo "notarization returned $submission_status for $submission_id" >&2
    xcrun notarytool log "$submission_id" \
      --key "$NOTARY_KEY" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" \
      >&2 || true
    exit 1
  fi

  echo "▸ stapling the notarization ticket"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type exec --verbose=4 "$app"
  rm -rf "$notary_dir"
fi

echo "▸ assembling $artifact_name"
rm -rf "$release_root"
rm -f "dist/$artifact_name" dist/agent-notch.rb dist/checksums.txt
mkdir -p "$release_root/bin"
ditto "$app" "$release_root/AgentNotch.app"
ditto "$app/Contents/MacOS/agent-notch" "$release_root/bin/agent-notch"
cp LICENSE "$release_root/LICENSE"

codesign --verify --deep --strict --verbose=2 "$release_root/AgentNotch.app"
codesign --verify --strict --verbose=2 "$release_root/bin/agent-notch"
# Confirm the copy that actually ships kept its ticket. ditto preserves it, but
# a shipped app that lost the ticket is exactly the failure worth catching here.
if [ -z "$skip_notarize" ]; then
  xcrun stapler validate "$release_root/AgentNotch.app"
  spctl --assess --type exec --verbose=4 "$release_root/AgentNotch.app"
fi
ditto -c -k --keepParent "$release_root" "dist/$artifact_name"

artifact_sha="$(shasum -a 256 "dist/$artifact_name" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha" "$artifact_name" >dist/checksums.txt

cat >dist/agent-notch.rb <<EOF
cask "agent-notch" do # THE FILE IS GENERATED BY scripts/build_release.sh
  version "$build_version"
  sha256 "$artifact_sha"

  url "https://github.com/tosaka07/agent-notch/releases/download/v#{version}/AgentNotch-v#{version}-macos-arm64.zip"
  name "Agent Notch"
  desc "Notch-based command center for AI coding agents"
  homepage "https://github.com/tosaka07/agent-notch"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "AgentNotch-v#{version}/AgentNotch.app"

  # Link the CLI inside the installed app rather than the copy under bin/.
  # A bare executable cannot carry a stapled notarization ticket, but the one
  # inside AgentNotch.app is covered by the ticket stapled to the bundle.
  binary "#{appdir}/AgentNotch.app/Contents/MacOS/agent-notch"
end
EOF

ruby -c dist/agent-notch.rb

echo "✓ dist/$artifact_name"
echo "✓ dist/checksums.txt"
echo "✓ dist/agent-notch.rb"
