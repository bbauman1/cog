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

echo "=== ci_post_clone.sh complete ==="
