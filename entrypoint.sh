#!/bin/bash

cd "${GITHUB_WORKSPACE}" \
  || (echo "Workspace is unavailable" >&2; exit 1)

set -eu

if git log --oneline -n1 --format="%s" | grep -s -e " to v[0-9]\+$"
then
  echo "Skipping major version update. Import path must be manually updated" >&2
  exit 0
fi

export GOPRIVATE=${INPUT_GOPRIVATE:-}

BRANCH=$(git symbolic-ref -q --short HEAD) \
  || (echo "You are in 'detached HEAD' state" >&2; exit 1)

# Workaround to use correct token
git config --unset http."https://github.com/".extraheader || true

echo -e "machine github.com\nlogin ${GITHUB_ACTOR}\npassword ${INPUT_GITHUB_TOKEN}" > ~/.netrc
git config user.name ${INPUT_GIT_USER}
git config user.email ${INPUT_GIT_EMAIL}

INPUT_GO_MOD_PATHS=${INPUT_GO_MOD_PATHS:-$(find . -name go.mod | xargs -r -n1 dirname)}

case ${INPUT_CHECK_BASE_TIDIED:-true} in
  true)
    base_branch_not_tidied=false
    base_sha=$(cat ${GITHUB_EVENT_PATH} | jq -r '.before')
    if [ "${base_sha}" = "null" ]
    then
      echo "Base commit not found; skipping base branch check" >&2
    else
      git fetch --depth=100 origin ${BRANCH}
      git log --oneline
      if git checkout ${base_sha}
      then
        echo ${INPUT_GO_MOD_PATHS} | xargs -r -n1 echo | while read dir
        do
          cd ${dir}
          go mod download
          go mod tidy
          cd "${GITHUB_WORKSPACE}"
        done
        if ! git diff --exit-code
        then
          base_branch_not_tidied=true
        fi
        git stash
        git checkout ${BRANCH}
      else
        echo "Base commit not found; skipping base branch check" >&2
      fi
    fi
    if ${base_branch_not_tidied}
    then
      echo "Base branch is not tidied." >&2
      exit 1
    fi
    ;;
esac

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
