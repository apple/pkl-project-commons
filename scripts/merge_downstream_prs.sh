#!/usr/bin/env bash

# This script will, for each Pkl repo, merge PRs created by ./update_downstream_ci.sh that are approved and have passing checks.
#
# Usage: ./merge_downstream_prs.sh

set -eo pipefail

MY_GIT_USER="$(gh api user --jq '.login')"

if [[ -z "$MY_GIT_USER" ]]; then
  echo "Could not determine the current user in gh. Try running \`gh auth login -s workflow\`."
  exit 1
fi

if [[ "$(gh auth status --json hosts --jq '.hosts."github.com"[] | .scopes')" != *workflow* ]]; then
  echo "No \`workflow\` scope found in current session. Try running \`gh auth login -s workflow\`."
  exit 1
fi

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source "$SCRIPT_DIR/repos.sh"

VERSION=$(
  curl -s https://api.github.com/repos/apple/pkl-project-commons/releases \
    | jq -r '[.[] | select(.tag_name | startswith("pkl.impl.ghactions"))] | .[0].name | split("@")[1]'
)

echo "Latest pkl.impl.ghactions version: $VERSION"

find_pr_and_merge() {
  repo="$1"
  pr_number="$(gh pr list --repo "apple/$repo" --json title,number \
    | jq --arg VERSION "$VERSION" \
      '.[]
      | select(.title == "Bump pkl.impl.ghactions to version \($VERSION)")
      | .number')"

  if [ -z "$pr_number" ]; then
    echo "✅ No PR to approve for $repo"
    return 0
  fi

  existing_approvals="$(GH_PAGER='' gh pr view --repo "apple/$repo" "$pr_number" --json reviews | \
    jq '.reviews | map(select(.state == "APPROVED")) | length')"
  if [ "$existing_approvals" = "0" ]; then
    echo "❌ https://github.com/apple/$repo/pull/$pr_number is not approved"
    return 0
  fi

  non_successful_status_checks="$(GH_PAGER='' gh pr view --repo "apple/$repo" "$pr_number" --json statusCheckRollup | \
    jq --arg MY_GIT_USER "$MY_GIT_USER" \
    '.statusCheckRollup | map(select(.status != "COMPLETED" or (.conclusion != "SUCCESS" and .conclusion != "SKIPPED"))) | length')"
  if [ "$non_successful_status_checks" != "0" ]; then
    echo "❌ https://github.com/apple/$repo/pull/$pr_number has failing status checks"
    return 0
  fi

  echo "🔧 Merging https://github.com/apple/$repo/pull/$pr_number"
  gh pr merge --repo "apple/$repo" "$pr_number" --squash --delete-branch
}

for repo in "${REPOS[@]}"; do
  find_pr_and_merge "$repo"
done
