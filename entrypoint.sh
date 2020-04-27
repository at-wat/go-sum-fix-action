#!/bin/bash

cd "${GITHUB_WORKSPACE}" \
  || (echo "Workspace is unavailable" >&2; exit 1)

set -eu

export GOPRIVATE=${INPUT_GOPRIVATE:-}

BRANCH=$(git symbolic-ref -q --short HEAD) \
  || (echo "You are in 'detached HEAD' state." >&2; exit 1)

# Workaround to use correct token
git config --unset url."https://github".insteadOf || true
git config --global --unset url."https://github".insteadOf || true

echo -e "machine github.com\nlogin ${INPUT_GITHUB_TOKEN}" > ~/.netrc
git config user.name ${INPUT_GIT_USER}
git config user.email ${INPUT_GIT_EMAIL}

INPUT_GO_MOD_PATHS=${INPUT_GO_MOD_PATHS:-$(find . -name go.mod | xargs -r -n1 dirname)}

echo ${INPUT_GO_MOD_PATHS} | xargs -r -n1 echo | while read dir
do
  cd ${dir}
  go mod download
  go mod tidy
  cd "${GITHUB_WORKSPACE}"
done

if git diff --exit-code
then
  echo "Up-to-date"
  exit 0
fi

case ${INPUT_COMMIT_STYLE:-add} in
  add)
    git add .;
    git commit -m ${INPUT_COMMIT_MESSAGE:-"Fix go.sum"};
    ;;
  squash)
    git add .;
    git commit --amend --no-edit;
    ;;
  *)
    echo "Unknown commit_style value: ${INPUT_COMMIT_STYLE}" >&2;
    exit 1;
    ;;
esac

origin=https://github.com/${GITHUB_REPOSITORY}
case ${INPUT_PUSH:-no} in
  no)
    ;;
  yes)
    git push ${origin} ${BRANCH};
    ;;
  force)
    git push -f ${origin} ${BRANCH};
    ;;
  *)
    echo "Unknown push value: ${INPUT_PUSH}" >&2;
    exit 1;
    ;;
esac
