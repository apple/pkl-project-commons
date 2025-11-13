#!/usr/bin/env bash

# Publishes the package provided by the argument.

set -euo pipefail

PACKAGE=$1

if [ -z "$PACKAGE" ]; then
  echo "Usage: publish_package.sh <package>"
  exit 1
fi

# Validate we're on the main branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Error: Must be on 'main' branch (currently on '$CURRENT_BRANCH')"
  exit 1
fi

# Fetch latest from upstream
echo "Fetching latest from upstream..."
git fetch upstream main

# Check if local main is up to date with upstream/main
LOCAL_COMMIT=$(git rev-parse main)
UPSTREAM_COMMIT=$(git rev-parse upstream/main)

if [ "$LOCAL_COMMIT" != "$UPSTREAM_COMMIT" ]; then
  echo "Error: Local 'main' branch is not up to date with 'upstream/main'"
  echo "Local:    $LOCAL_COMMIT"
  echo "Upstream: $UPSTREAM_COMMIT"
  echo ""
  echo "Please update your local main branch:"
  echo "  git pull upstream main"
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
