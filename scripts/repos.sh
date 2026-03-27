set -eo pipefail

export REPOS=(
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
  "highlightjs-pkl"
  "pkl-readers"
)

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
