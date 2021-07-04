# go-sum-fix-action
GitHub Action to update go.sum.

## Updates

Since v0.3.0, **go-sum-fix-action fails if previous commit is not tidied**. This is to prevent causing infinite loop of force-push by Renovate bot and go-sum-fix-action.

## Example

Example to automatically fix `go.sum` in Renovate Bot's pull requests.

```yaml
name: go-mod-fix
on:
  push:
    branches:
      - renovate/*

jobs:
  go-mod-fix:
    runs-on: ubuntu-latest
    steps:
      - name: checkout
        uses: actions/checkout@v2
        with:
          fetch-depth: 2
      - name: fix
        uses: at-wat/go-sum-fix-action@v0
        with:
          git_user: @@MAINTAINER_NAME@@
          git_email: @@MAINTAINER_EMAIL_ADDRESS@@
          github_token: ${{ secrets.GITHUB_TOKEN }}
          commit_style: squash
          push: force
          update_import_path: true # update import path on major update
```
