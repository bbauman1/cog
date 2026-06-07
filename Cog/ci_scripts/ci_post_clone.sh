#!/bin/sh
set -e

echo "=== ci_post_clone.sh ==="

# Install XcodeGen to regenerate .xcodeproj from project.yml
echo "Installing XcodeGen..."
brew install xcodegen

# Regenerate Xcode project from project.yml (source of truth)
echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH/Cog"
xcodegen generate

# Set build number using UTC timestamp (YYYYMMDDHHmm).
# CI_BUILD_NUMBER starts at 1 for new workflows which conflicts with
# previously uploaded builds. Timestamp is always increasing.
if [ -n "$CI" ]; then
  BUILD_NUMBER=$(date -u +%Y%m%d%H%M)
  echo "Setting build number to $BUILD_NUMBER..."
  agvtool new-version -all "$BUILD_NUMBER"
fi

echo "=== ci_post_clone.sh complete ==="
