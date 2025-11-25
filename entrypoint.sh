#!/bin/bash

cd "${GITHUB_WORKSPACE}" \
  || (echo "Workspace is unavailable" >&2; exit 1)

if [ -z "${INPUT_GITHUB_TOKEN}" ]
then
  echo "github_token is not provided" >&2
  exit 1
fi

set -eu

git config --global --add safe.directory ${GITHUB_WORKSPACE}
commit_author="$(git show HEAD --pretty=format:%ae -s)"
if [ ! "${commit_author}" = "bot@renovateapp.com" ] && [ ! "${commit_author}" = "29139614+renovate[bot]@users.noreply.github.com" ]
then
  echo "HEAD commit author is not Renovate Bot" >&2
  exit 0
fi

commit_message="$(git log --oneline -n1 --format="%s")"

update_import_path=false
if echo "${commit_message}" | grep -s -e " to v[0-9]\+\$"
then
  case ${INPUT_UPDATE_IMPORT_PATH:-true} in
    true)
      grep -n "update_import_path:\s\+true" .github/workflows/*.y*ml | while read line
      do
        file=$(echo ${line} | cut -d: -f1)
        line=$(echo ${line} | cut -d: -f2)
        echo "::warning file=${file},line=${line},title=DEPRECATED::update_import_path option is deprecated. Use Renovate gomodUpdateImportPaths option instead."
      done
      update_import_path=true
      from_to=$(echo "${commit_message}" | sed -n 's|[uU]pdate module \(\S\+\)/\(v[0-9]\+\) to \(v[0-9]\+\)$|\1/\2 \1/\3|p')
      import_path_from=$(echo ${from_to} | cut -f1 -d" ")
      import_path_to=$(echo ${from_to} | cut -f2 -d" ")
      if [ -z "${import_path_from}" ] || [ -z "${import_path_to}" ]
      then
        echo "Skipping +incompatible" >&2
        exit 0
      fi
      ;;
    *)
      echo "Skipping major version update. Import path must be manually updated" >&2
      exit 0
      ;;
  esac
fi

monorepo=
monorepo_major=
monorepo_version=
for pkg in ${INPUT_MONOREPOS}
do
  pkg_esc=$(echo ${pkg} | sed 's/\./\\./g')
  if echo "${commit_message}" | grep -s -e "[uU]pdate module ${pkg_esc} to "
  then
    monorepo=$(echo ${pkg} | sed 's|/v[0-9]\+$||')
    monorepo_major=$(echo ${pkg} | sed -n 's|^.*\(/v[0-9]\+\)$|\1|p')
    monorepo_version=$(echo "${commit_message}" | sed -n "s|^.*[uU]pdate module ${pkg_esc} to \(v[0-9\.]\+\)\$|\1|p")
    echo "Monorepo ${monorepo} ${monorepo_major} ${monorepo_version}"
    break
  fi
done

export GOPRIVATE=${INPUT_GOPRIVATE:-}

BRANCH=$(git symbolic-ref -q --short HEAD) \
  || (echo "You are in 'detached HEAD' state" >&2; exit 1)

echo "--- original git config"
git config --list --show-origin
echo "---"

echo "Setting up authentication"
cp .git/config .git/config.bak
cp ~/.gitconfig ~/.gitconfig.bak
revert_git_config() {
  mv .git/config.bak .git/config
  mv ~/.gitconfig.bak ~/.gitconfig
}
trap revert_git_config EXIT

git config --unset-all http."https://github.com/".extraheader || true
git config --global --unset-all http."https://github.com/".extraheader || true
git config --get-regexp '^includeif.gitdir:.*/git-credentials.*' \
  | xargs -n1 git config --unset-all

echo "--- cleaned git config"
git config --list --show-origin
echo "---"

git config --global --add http."https://github.com/".extraheader "Authorization: Basic $(echo -n "x-access-token:${INPUT_GITHUB_TOKEN}" | base64 | tr -d '\n')"
git config user.name ${INPUT_GIT_USER}
git config user.email ${INPUT_GIT_EMAIL}

INPUT_GO_MOD_PATHS=${INPUT_GO_MOD_PATHS:-$(
  find . -name go.mod -printf '%d %p\n' \
    | sort -n \
    | sed 's/^[0-9]\+\s\+//' \
    | xargs -n1 dirname
)}

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

if [ -n "${monorepo}" ] && [ -n "${monorepo_version}" ]
then
  tmpdir=$(mktemp -d)
  git clone -b ${monorepo_version} --depth=1 https://${monorepo} ${tmpdir}
  echo "Updating submodules of ${monorepo} ${monorepo_version}"
  tags=$(git -C ${tmpdir} tag --list --points-at HEAD)

  for tag in ${tags}
  do
    subpkg=$(dirname ${tag})
    subpkg_version=$(basename ${tag})

    echo ${INPUT_GO_MOD_PATHS} | xargs -r -n1 echo | while read dir
    do
      if grep -s -F "${monorepo}${monorepo_major}/${subpkg}" ${dir}/go.mod
      then
        echo "  - ${subpkg} ${subpkg_version}"
        from=$(echo "${monorepo}${monorepo_major}/${subpkg} v[0-9\.]\+" | sed 's/\./\\./g')
        to="${monorepo}${monorepo_major}/${subpkg} ${subpkg_version}"
        sed "s|\<${from}\>|${to}|" -i ${dir}/go.mod
      fi
    done
  done
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
  echo "Indirect dependencies are updated" >&2
  if [ "${INPUT_CHECK_NO_INDIRECT_DIFFS:-true}" = 'true' ]
  then
    git restore .
    echo "Skipping commit to avoid infinite push loop" >&2
    exit 0
  fi
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
