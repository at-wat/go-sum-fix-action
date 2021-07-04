#!/bin/bash

cd "${GITHUB_WORKSPACE}" \
  || (echo "Workspace is unavailable" >&2; exit 1)

if [ -z "${INPUT_GITHUB_TOKEN}" ]
then
  echo "github_token is not provided" >&2
  exit 1
fi

set -eu

if [ ! "$(git show HEAD --pretty=format:%ae -s)" = "bot@renovateapp.com" ]
then
  echo "HEAD commit author is not Renovate Bot" >&2
  exit 0
fi

update_import_path=false
if git log --oneline -n1 --format="%s" | grep -s -e " to v[0-9]\+$"
then
  case ${INPUT_UPDATE_IMPORT_PATH:-true} in
    true)
      update_import_path=true
      from_to=$(git log --oneline -n1 --format="%s" | sed -n 's|^Update module \(\S\+\)/\(v[0-9]\+\) to \(v[0-9]\+\)$|\1/\2 \1/\3|p')
      import_path_from=$(echo ${from_to} | cut -f1 -d" ")
      import_path_to=$(echo ${from_to} | cut -f2 -d" ")
      ;;
    *)
      echo "Skipping major version update. Import path must be manually updated" >&2
      exit 0
      ;;
  esac
fi

export GOPRIVATE=${INPUT_GOPRIVATE:-}

BRANCH=$(git symbolic-ref -q --short HEAD) \
  || (echo "You are in 'detached HEAD' state" >&2; exit 1)

echo "Setting up authentication"
cp .git/config .git/config.bak
revert_git_config() {
  mv .git/config.bak .git/config
}
trap revert_git_config EXIT

git config --unset http."https://github.com/".extraheader || true
git config --global --add http."https://github.com/".extraheader "Authorization: Basic $(echo -n "x-access-token:${INPUT_GITHUB_TOKEN}" | base64 | tr -d '\n')"
git config user.name ${INPUT_GIT_USER}
git config user.email ${INPUT_GIT_EMAIL}

INPUT_GO_MOD_PATHS=${INPUT_GO_MOD_PATHS:-$(find . -name go.mod | xargs -r -n1 dirname)}

case ${INPUT_CHECK_PREVIOUSLY_TIDIED:-true} in
  true)
    echo "Checking that previous commit is tidied"
    previous_commit_not_tidied=false
    git fetch --depth=2 origin ${BRANCH}
    if git checkout HEAD^
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
        previous_commit_not_tidied=true
      fi
      git stash
      git checkout ${BRANCH}
    else
      echo "Previous commit not found; skipping check" >&2
    fi
    if ${previous_commit_not_tidied}
    then
      echo "Previous commit is not tidied" >&2
      echo "Skipping commit to avoid infinite push loop" >&2
      exit 1
    fi
    ;;
esac

if ${update_import_path}
then
  echo "Updating import path from ${import_path_from} to ${import_path_to}"
  sed "s|\"$(echo ${import_path_from} | sed 's/\./\\./g')|\"${import_path_to}|" \
    -i $(find . -name "*.go")
fi

echo "Tidying"
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

# Check no `// indirect` is updated
if git diff | grep -e '^[+\-].* // indirect$'
then
  git restore .
  echo "Indirect dependencies are updated" >&2
  echo "Skipping commit to avoid infinite push loop" >&2
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

echo "Pushing to the repository"
origin=https://github.com/${GITHUB_REPOSITORY}
case ${INPUT_PUSH:-no} in
  no)
    ;;
  yes)
    git push --verbose ${origin} ${BRANCH};
    ;;
  force)
    git push --verbose -f ${origin} ${BRANCH};
    ;;
  *)
    echo "Unknown push value: ${INPUT_PUSH}" >&2;
    exit 1;
    ;;
esac
