#!/usr/bin/env bash
# This script will, for each Pkl repo containing a gradlew file, bump the version of the gradle wrapper to the specified version.
# It assumes that every repo exists in a forked account.
#
# Usage: ./update_gradle_wrapper.sh <version>

set -eo pipefail

GRADLE_VERSION=$1

if [ -z "$GRADLE_VERSION" ]; then
  echo "Usage: update_gradle_wrapper.sh <version>"
  exit 1
fi

MY_GIT_USER="$(gh api user --jq '.login')"
BRANCH_NAME=bump-gradle-wrapper-$GRADLE_VERSION
GRADLE_DIST_SUM=$(curl -sSL "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip.sha256")

if [[ -z "$MY_GIT_USER" ]]; then
  echo "Could not determine the current user in gh. Try running \`gh auth login\`."
  exit 1
fi

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source "$SCRIPT_DIR/repos.sh"

declare -a CREATED_PRS
declare -a SKIPPED_REPOS

function update_repo() {
  cd "$(repo_dir "$1")"

  if ! [[ -f ./gradlew ]]; then
    SKIPPED_REPOS+=("$1 (no ./gradlew)")
    return 0
  fi

  if git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
    git checkout "$BRANCH_NAME" &> /dev/null || true
    if git show upstream/main:gradle/wrapper/gradle-wrapper.properties | grep -q "gradle-$GRADLE_VERSION-bin.zip"; then
      echo "✅ $1 already has the correct version $GRADLE_VERSION"
      SKIPPED_REPOS+=("$1 (already up to date)")
      return 0
    fi
    # wrong version, reset to upstream/main and continue
    git checkout main &> /dev/null || true
    git branch -D "$BRANCH_NAME" &> /dev/null || true
    git reset --hard upstream/main &> /dev/null || true
  fi

  echo "🔧 Updating $1..."
  ./gradlew wrapper --gradle-version "$GRADLE_VERSION" --gradle-distribution-sha256-sum "$GRADLE_DIST_SUM" && ./gradlew wrapper

  echo "  Creating branch and commit..."
  git checkout -b "$BRANCH_NAME" &> /dev/null
  git add . &> /dev/null
  git commit -m "Bump Gradle to version $GRADLE_VERSION" &> /dev/null

  echo "  Pushing to origin..."
  git push --force -u origin "$BRANCH_NAME" 2>&1 | grep -v "branch '$BRANCH_NAME' set up" || true

  echo "  Checking for existing pull request..."
  set +e
  PR_DATA=$(GH_PAGER='' gh pr view --repo "apple/$1" "$MY_GIT_USER:$BRANCH_NAME" --json url,state)
  PR_DATA_STATUS=$?
  set -e
  # if this is zero and the state is OPEN, the PR already exists
  if [ $PR_DATA_STATUS = 0 ] && [ "$(jq -r .state <<< "$PR_DATA")" = "OPEN" ]; then
    SKIPPED_REPOS+=("$1 (pr already exists)")
    echo "✅ Existing PR found for $1"
  else
    echo "  Creating pull request..."
    PR_URL=$(gh pr create --repo "apple/$1" --base main --head "$MY_GIT_USER:$BRANCH_NAME" \
      --title "Bump Gradle to version $GRADLE_VERSION" --body '' 2>&1 | grep "https://")
    echo "$PR_URL"
    CREATED_PRS+=("$1|$PR_URL")
    echo "✅ Successfully created PR for $1"
  fi
}

for repo in "${REPOS[@]}"; do
  fetch_repo "$repo"
  update_repo "$repo"
  echo ""
done

echo "═══════════════════════════════════════════════════════════════"
echo "Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ ${#CREATED_PRS[@]} -gt 0 ]]; then
  echo "Pull Requests Created (${#CREATED_PRS[@]}):"
  for pr_info in "${CREATED_PRS[@]}"; do
    IFS='|' read -r repo url <<< "$pr_info"
    echo "  • $repo"
    echo "    $url"
  done
  echo ""
fi

if [[ ${#UPDATED_PRS[@]} -gt 0 ]]; then
  echo "Pull Requests Updated (${#UPDATED_PRS[@]}):"
  for pr_info in "${UPDATED_PRS[@]}"; do
    IFS='|' read -r repo url <<< "$pr_info"
    echo "  • $repo"
    echo "    $url"
  done
  echo ""
fi

if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then
  echo "Skipped (${#SKIPPED_REPOS[@]}):"
  for skip_info in "${SKIPPED_REPOS[@]}"; do
    echo "  • $skip_info"
  done
  echo ""
fi
