#!/usr/bin/env bash
# This script will, for each Pkl repo, bump the version of `pkl.impl.ghactions` to the latest version, and
# create a GitHub pull request.
# It assumes that every repo exists in a forked account.
#
# Usage: ./update_downstream_ci.sh

set -eo pipefail

MY_GIT_USER="$(gh api user --jq '.login')"
BRANCH_NAME=bump-github-actions

if [[ -z "$MY_GIT_USER" ]]; then
  echo "Could not determine the current user in gh. Try running \`gh auth login\`."
  exit 1
fi

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source "$SCRIPT_DIR/repos.sh"

LATEST_PACKAGE_VERSION=$(
  curl -s https://api.github.com/repos/apple/pkl-project-commons/releases \
    | jq -r '[.[] | select(.tag_name | startswith("pkl.impl.ghactions"))] | .[0].name | split("@")[1]'
)

echo "Latest pkl.impl.ghactions version: $LATEST_PACKAGE_VERSION"
echo ""

declare -a CREATED_PRS
declare -a UPDATED_PRS
declare -a SKIPPED_REPOS

function repo_dir() {
  echo "$SCRIPT_DIR/../build/update_downstream_ci/$1"
}

function fetch_repo() {
  if ! GH_PAGER='' gh repo view "$MY_GIT_USER/$1" --json name > /dev/null 2> /dev/null; then
    echo "🍽️ Forking $1..."
    gh repo fork --default-branch-only --clone=false "apple/$1"
  fi
  echo "📦 Fetching $1..."
  REPO_DIR="$(repo_dir "$1")"
  if [[ ! -d "$REPO_DIR" ]]; then
    git clone -o upstream "git@github.com:apple/$1.git" "$REPO_DIR" 2>&1 | grep -v "Cloning into" || true
    cd "$REPO_DIR"
    git remote add origin "git@github.com:$MY_GIT_USER/$1.git" 2>&1
  else
    cd "$REPO_DIR"
    git fetch upstream 2>&1 | grep -v "From github.com" || true
    git reset &> /dev/null
    git checkout . &> /dev/null
    git checkout main &> /dev/null
    git reset --hard upstream/main &> /dev/null
  fi
}

function update_repo() {
  echo "🔧 Updating $1..."
  cd "$(repo_dir "$1")/.github"

  # if bump-github-actions branch exists, and the PklProject there has the correct version, just exit early.
  if git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
    git checkout "$BRANCH_NAME" &> /dev/null || true
    if git show upstream/main:.github/PklProject | grep -q "pkl.impl.ghactions@$LATEST_PACKAGE_VERSION"; then
      echo "✅ $1 already has the correct version $LATEST_PACKAGE_VERSION"
      SKIPPED_REPOS+=("$1 (already up to date)")
      return 0
    fi
    # wrong version, reset to upstream/main and continue
    git checkout main &> /dev/null || true
    git branch -D "$BRANCH_NAME" &> /dev/null || true
    git reset --hard upstream/main &> /dev/null || true
  fi

  sed -i '' -E "s|(package://pkg.pkl-lang.org/pkl-project-commons/pkl.impl.ghactions@)[0-9]+\.[0-9]+\.[0-9]+|\\1$LATEST_PACKAGE_VERSION|g" PklProject
  echo "  Resolving dependencies..."
  pkl project resolve > /dev/null
  echo "  Cleaning up generated workflows..."
  rm -f ./**/[a-z]*.yml
  echo "  Evaluating Pkl files..."
  pkl eval -m . index.pkl > /dev/null
  if [[ -z "$(git diff)" ]]; then
    echo "✅ Nothing to update for $1"
    SKIPPED_REPOS+=("$1 (no changes needed)")
    return 0
  fi
  echo "  Creating branch and commit..."
  git checkout -b "$BRANCH_NAME" &> /dev/null
  git add . &> /dev/null
  git commit -m "Bump pkl.impl.ghactions to version $LATEST_PACKAGE_VERSION" &> /dev/null

  FORMATTED=0
  if [[ -f ../licenserc.toml ]]; then
    echo "✍️ Formatting: hawkeye"
    (cd .. && hawkeye format --fail-if-updated false)
    FORMATTED=1
  fi
  if [[ -f ../gradlew ]]; then
    echo "✍️ Formatting: spotless"
    test "$1" = "pkl" && (cd .. && ./gradlew assemble)
    (cd .. && ./gradlew spotlessApply) || true
    FORMATTED=1
  fi
  if [[ "$FORMATTED" = 1 ]] && [[ -n "$(git diff)" ]]; then
    echo "  Amending commit with formatting changes..."
    git add . &> /dev/null
    git commit --amend --no-edit &> /dev/null
  fi

  echo "  Pushing to origin..."
  git push --force -u origin "$BRANCH_NAME" 2>&1 | grep -v "branch '$BRANCH_NAME' set up" || true
  echo "  Checking for existing pull request..."
  PR_DATA=$(GH_PAGER='' gh pr view --repo "apple/$1" "$MY_GIT_USER:$BRANCH_NAME" --json url,state)
  PR_DATA_STATUS=$?
  # if this is zero and the state is OPEN, the PR already exists
  if [ $PR_DATA_STATUS = 0 ] && [ "$(jq -r .state <<< "$PR_DATA")" = "OPEN" ]; then
    echo "  Editing pull request..."
    PR_URL=$(jq -r .url <<< "$PR_DATA")
    gh pr edit "$PR_URL" --repo "apple/$1" \
      --title "Bump pkl.impl.ghactions to version $LATEST_PACKAGE_VERSION" \
      --body "Updates pkl.impl.ghactions package to version $LATEST_PACKAGE_VERSION"
    UPDATED_PRS+=("$1|$PR_URL")
    echo "✅ Successfully updated PR for $1"
  else
    echo "  Creating pull request..."
    PR_URL=$(gh pr create --repo "apple/$1" --base main --head "$MY_GIT_USER:$BRANCH_NAME" \
      --title "Bump pkl.impl.ghactions to version $LATEST_PACKAGE_VERSION" \
      --body "Updates pkl.impl.ghactions package to version $LATEST_PACKAGE_VERSION" 2>&1 | grep "https://")
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
