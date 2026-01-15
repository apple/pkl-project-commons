#!/usr/bin/env bash

# This script will, for each Pkl repo, approve PRs created by ./update_downstream_ci.sh.
#
# Usage: ./approve_downstream_prs.sh

set -eo pipefail

MY_GIT_USER="$(gh api user --jq '.login')"

if [[ -z "$MY_GIT_USER" ]]; then
  echo "Could not determine the current user in gh. Try running \`gh auth login\`."
  exit 1
fi

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source "$SCRIPT_DIR/repos.sh"

VERSION=$(
  curl -s https://api.github.com/repos/apple/pkl-project-commons/releases \
    | jq -r '[.[] | select(.tag_name | startswith("pkl.impl.ghactions"))] | .[0].name | split("@")[1]'
)

echo "Latest pkl.impl.ghactions version: $VERSION"

find_pr_and_approve() {
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
    jq --arg MY_GIT_USER "$MY_GIT_USER" \
    '.reviews | map(select(.author.login == $MY_GIT_USER and .state == "APPROVED")) | length')"
  if [ "$existing_approvals" != "0" ]; then
    echo "✅ https://github.com/apple/$repo/pull/$pr_number already approved"
    return 0
  fi

  echo "🔧 Approve https://github.com/apple/$repo/pull/$pr_number? Files changed:"
  GH_PAGER='' gh pr diff --name-only --repo "apple/$repo" "$pr_number"
  echo
  # shellcheck disable=SC2162
  read -p "Press enter to approve or ^C to quit"
  gh pr review --repo "apple/$repo" "$pr_number" --approve
  echo ""
}

for repo in "${REPOS[@]}"; do
  find_pr_and_approve "$repo"
done
