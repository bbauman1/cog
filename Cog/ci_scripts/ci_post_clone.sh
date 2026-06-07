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

# Set build number from Xcode Cloud's auto-incrementing CI_BUILD_NUMBER.
# This ensures each build has a unique, increasing build number without
# manual bumps to CURRENT_PROJECT_VERSION in project.yml.
if [ -n "$CI_BUILD_NUMBER" ]; then
  echo "Setting build number to $CI_BUILD_NUMBER..."
  agvtool new-version -all "$CI_BUILD_NUMBER"
fi

echo "=== ci_post_clone.sh complete ==="
