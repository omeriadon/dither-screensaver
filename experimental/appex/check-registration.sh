#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/build/DitherHost.app"
APPEX="$APP/Contents/PlugIns/DitherExtension.appex"
# Compatibility: this is the installed extension bundle identifier.
IDENTIFIER="local.geometry-clock.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if pluginkit -m -A -D -i "$IDENTIFIER" | grep -Fq "$IDENTIFIER("; then
    print -u2 "A registration already exists for $IDENTIFIER; leaving it unchanged."
    exit 1
fi

cleanup() {
    pluginkit -r "$APPEX"
    "$LSREGISTER" -u "$APP"
}
trap cleanup EXIT

"$LSREGISTER" -f "$APP"
pluginkit -a "$APPEX"
RESULT="$(pluginkit -m -v -A -D -i "$IDENTIFIER")"
if [[ "$RESULT" != *"$APPEX"* ]]; then
    print -u2 "The extension was not registered at the expected path."
    exit 1
fi
print "Registration check passed: $APPEX"
