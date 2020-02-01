# go-sum-fix-action
GitHub Action to update go.sum.


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
```
