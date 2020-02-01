#!/bin/bash

cd "${GITHUB_WORKSPACE}" \
  || (echo "Workspace is unavailable" >&2; exit 1)

set -eu

if [[ "${INPUT_BRANCH}" == refs/heads/* ]]
then
  BRANCH=$(echo ${INPUT_BRANCH} | sed -e "s|^refs/heads/||")
else
  BRANCH=${INPUT_BRANCH}
fi

echo -e "machine github.com\nlogin ${INPUT_GITHUB_TOKEN}" > ~/.netrc
git config user.name ${INPUT_GIT_USER}
git config user.email ${INPUT_GIT_EMAIL}

go mod download
go mod tidy

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

case ${INPUT_PUSH:-no} in
  no)
    ;;
  yes)
    git push origin ${BRANCH};
    ;;
  force)
    git push -f origin ${BRANCH};
    ;;
  *)
    echo "Unknown push value: ${INPUT_PUSH}" >&2;
    exit 1;
    ;;
esac
