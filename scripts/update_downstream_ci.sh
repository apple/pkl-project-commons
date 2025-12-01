#!/usr/bin/env bash
# This script will, for each Pkl repo, bump the version of `pkl.impl.ghactions` to the latest version, and
# create a GitHub pull request.
# It assumes that every repo exists in a forked account.
#
# Usage: ./update_downstream_ci.sh

set -eo pipefail

MY_GIT_USER="$(gh api user --jq '.login')"

if [[ -z "$MY_GIT_USER" ]]; then
  echo "Could not determine the current user in gh. Try running \`gh auth login\`."
  exit 1
fi

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

REPOS=(
  "pkl"
  "pkl-go"
  "pkl-go-examples"
  "pkl-intellij"
  "pkl-jvm-examples"
  "pkl-k8s"
  "pkl-k8s-examples"
  "pkl-lang.org"
  "pkl-lsp"
  "pkl-neovim"
  "pkl-package-docs"
  "pkl-pantry"
  "pkl-spring"
  "pkl-swift"
  "pkl-swift-examples"
  "pkl-vscode"
  "pkl.tmbundle"
  "rules_pkl"
  "tree-sitter-pkl"
)

LATEST_PACKAGE_VERSION=$(
  curl -s https://api.github.com/repos/apple/pkl-project-commons/releases \
    | jq -r '[.[] | select(.tag_name | startswith("pkl.impl.ghactions"))] | .[0].name | split("@")[1]'
)

echo "Latest pkl.impl.ghactions version: $LATEST_PACKAGE_VERSION"
echo ""

declare -a CREATED_PRS
declare -a SKIPPED_REPOS

function repo_dir() {
  echo "$SCRIPT_DIR/../build/update_downstream_ci/$1"
}

function fetch_repo() {
  echo "📦 Fetching $1..."
  REPO_DIR="$(repo_dir "$1")"
  if [[ ! -d "$REPO_DIR" ]]; then
    git clone -o upstream "git@github.com:apple/$1.git" "$REPO_DIR" 2>&1 | grep -v "Cloning into" || true
    cd "$REPO_DIR"
    git remote add origin "git@github.com:$MY_GIT_USER/$1.git" 2>&1
  else
    cd "$REPO_DIR"
    git fetch upstream 2>&1 | grep -v "From github.com" || true
    git checkout main &> /dev/null
    git reset --hard upstream/main &> /dev/null
  fi
}

function update_repo() {
  echo "🔧 Updating $1..."
  cd "$(repo_dir "$1")/.github"

  # if bump-github-actions branch exists, and the PklProject there has the correct version, just exit early.
  if git show-ref --verify --quiet refs/heads/bump-github-actions; then
    git checkout bump-github-actions &> /dev/null || true
    if grep -q "pkl.impl.ghactions@$LATEST_PACKAGE_VERSION" PklProject; then
      echo "✅ $1 already has the correct version $LATEST_PACKAGE_VERSION"
      SKIPPED_REPOS+=("$1 (already up to date)")
      return 0
    fi
    # wrong version, reset to upstream/main and continue
    git checkout main &> /dev/null || true
    git branch -D bump-github-actions &> /dev/null || true
    git reset --hard upstream/main &> /dev/null || true
  fi

  sed -i '' -E "s|(package://pkg.pkl-lang.org/pkl-project-commons/pkl.impl.ghactions@)[0-9]+\.[0-9]+\.[0-9]+|\\1$LATEST_PACKAGE_VERSION|g" PklProject
  echo "  Resolving dependencies..."
  pkl project resolve > /dev/null
  echo "  Evaluating Pkl files..."
  pkl eval -m . index.pkl > /dev/null
  if [[ -z "$(git diff)" ]]; then
    echo "✅ Nothing to update for $1"
    SKIPPED_REPOS+=("$1 (no changes needed)")
    return 0
  fi
  echo "  Creating branch and commit..."
  git co -b bump-github-actions &> /dev/null
  git add . &> /dev/null
  git commit -m "Bump pkl.impl.ghactions to version $LATEST_PACKAGE_VERSION" &> /dev/null
  echo "  Pushing to origin..."
  git push --force -u origin bump-github-actions 2>&1 | grep -v "branch 'bump-github-actions' set up" || true
  echo "  Creating pull request..."
  PR_URL=$(gh pr create --repo "apple/$1" --base main --head "$MY_GIT_USER:bump-github-actions" \
    --title "Bump pkl.impl.ghactions to version $LATEST_PACKAGE_VERSION" \
    --body "Updates pkl.impl.ghactions package to version $LATEST_PACKAGE_VERSION" 2>&1 | grep "https://")
  echo "$PR_URL"
  CREATED_PRS+=("$1|$PR_URL")
  echo "✅ Successfully created PR for $1"
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

if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then
  echo "Skipped (${#SKIPPED_REPOS[@]}):"
  for skip_info in "${SKIPPED_REPOS[@]}"; do
    echo "  • $skip_info"
  done
  echo ""
fi
