#!/bin/sh
set -e

echo "=== ci_post_clone.sh ==="

# The committed .xcodeproj includes the widget extension target which
# isn't yet in project.yml, so we skip XcodeGen regeneration for now.
# If project.yml becomes the sole source of truth (with widget target
# defined), uncomment the lines below:
#
# echo "Installing XcodeGen..."
# brew install xcodegen
# echo "Generating Xcode project..."
# cd "$CI_PRIMARY_REPOSITORY_PATH/Cog"
# xcodegen generate

echo "Using committed .xcodeproj"
echo "=== ci_post_clone.sh complete ==="
