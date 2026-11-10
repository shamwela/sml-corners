#!/bin/bash
# Usage: scripts/release.sh VERSION ZIP
# Creates GitHub release vVERSION with ZIP attached, then points the Homebrew
# cask in shamwela/homebrew-tap at it.
set -euo pipefail

VERSION="$1"
ZIP="$2"
REPO="shamwela/sml-corners"
TAP="shamwela/homebrew-tap"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "SML Corners $VERSION" \
    --notes "Download **$(basename "$ZIP")** below, or install with Homebrew:

\`\`\`
brew install --cask shamwela/tap/sml-corners
\`\`\`

See the [README](https://github.com/$REPO#install) for step-by-step install instructions."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$TAP" "$WORK/tap" -- --quiet
CASK="$WORK/tap/Casks/sml-corners.rb"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
if ! git -C "$WORK/tap" diff --quiet; then
    git -C "$WORK/tap" commit -qam "sml-corners $VERSION"
    git -C "$WORK/tap" push -q
fi
echo "Released $VERSION ($SHA)"
