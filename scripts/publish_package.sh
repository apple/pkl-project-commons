#!/usr/bin/env bash

# Publishes the package provided by the argument.

set -euo pipefail

PACKAGE=$1

if [ -z "$PACKAGE" ]; then
  echo "Usage: publish_package.sh <package>"
  exit 1
fi

# Validate package directory exists
if [ ! -d "packages/$PACKAGE" ]; then
  echo "Error: Package directory 'packages/$PACKAGE' does not exist"
  exit 1
fi

# Validate PklProject exists
if [ ! -f "packages/$PACKAGE/PklProject" ]; then
  echo "Error: PklProject not found at 'packages/$PACKAGE/PklProject'"
  exit 1
fi

# Extract version
VERSION=$(pkl eval "packages/$PACKAGE/PklProject" -x package.version)

if [ -z "$VERSION" ]; then
  echo "Error: Failed to extract version from PklProject"
  exit 1
fi

echo "Packaging $PACKAGE version $VERSION..."

# Package the project
pkl project package packages/"$PACKAGE"

# Validate artifacts were created
if [ ! -d ".out/$PACKAGE@$VERSION" ]; then
  echo "Error: Package artifacts not found at '.out/$PACKAGE@$VERSION'"
  exit 1
fi

# Count artifacts
ARTIFACT_COUNT=$(find ".out/$PACKAGE@$VERSION" -type f | wc -l | tr -d '[:space:]')
if [ "$ARTIFACT_COUNT" -eq 0 ]; then
  echo "Error: No artifacts found in '.out/$PACKAGE@$VERSION'"
  exit 1
fi

echo "Found $ARTIFACT_COUNT artifact(s) to publish"

# Check if release already exists
TAG="$PACKAGE@$VERSION"
if gh release view "$TAG" &>/dev/null; then
  echo "Error: Release '$TAG' already exists"
  echo "To republish, delete the existing release first:"
  echo "  gh release delete '$TAG'"
  exit 1
fi

echo "Creating GitHub release $TAG..."

gh release create "$TAG" \
  --title "$TAG" \
  --notes "Release of $TAG" \
  --target "$(git rev-parse HEAD)" \
  .out/"$PACKAGE@$VERSION"/*

echo "Successfully published $TAG"
