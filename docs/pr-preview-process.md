# PR preview process

This document explains how pull request previews work for the Constructor Fabric public website, why they are hosted where they are, and how to troubleshoot common failures.

If you only want to contribute, you can stop reading after the first section. The rest is for maintainers.

---

## 1. For contributors: opening a PR

1. Fork and clone the repository. See [CONTRIBUTING.md](../CONTRIBUTING.md).
2. Make your changes locally. Preview locally with the VS Code **Live Preview** extension or by running `python3 -m http.server` from the repository root.
3. Push your branch and open a pull request against `main`.
4. Within a few minutes, the **`Website PR CI`** check will start running on your PR.
5. When CI succeeds, the **`Publish Website Preview`** workflow will run and post a comment on your PR of the form:
   ```
   Preview deployment is ready:
   https://constructorfabric.github.io/website-previews/pr-<YOUR_PR_NUMBER>/
   ```
6. Click the preview URL and review your change there. Production (`constructorfabric.org`) is **not** affected by your PR.
7. Push more commits as needed — each push re-runs CI and re-publishes the preview.
8. After merge to `main`, the **`Deploy Website Production`** workflow publishes your change to `constructorfabric.org`. The PR preview remains available temporarily and is cleaned up automatically.

---

## 2. CI checks that run on your PR

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `Website PR CI` | `pull_request` opened/synchronize/reopen | Builds the static site with a preview base path, verifies the base tag injection, and uploads the result as an artifact. **No write permissions, no secrets.** |
| `Publish Website Preview` | `workflow_run` on `Website PR CI` (only when conclusion is `success`) | Downloads the artifact, checks out `constructorfabric/website-previews`, copies the artifact into `pr-<N>/`, commits, and pushes. Comments on your PR with the preview URL. |
| `Deploy Website Production` | `push` to `main` | Builds production with no base path override and deploys to GitHub Pages on `constructorfabric.org`. Does **not** run on PRs. |

A failure in `Website PR CI` will block `Publish Website Preview`. A failure in `Publish Website Preview` does **not** block merging — but please ping a maintainer, since the preview URL is the primary review surface.

---

## 3. Where the preview URL appears

GitHub Actions comments the preview URL automatically as a single bot comment on the source PR. It looks like:

```
Preview deployment is ready:
https://constructorfabric.github.io/website-previews/pr-123/
```

The URL is also visible in the `Publish Website Preview` workflow run summary under the **`deploy`** step output.

The preview is served by **GitHub Pages** on the `constructorfabric/website-previews` repository. There is no auth — anyone with the link can view it. Do not embed private data in previews.

---

## 4. How reviewers should use diff + preview

For text and HTML changes, the diff is usually enough. Open the preview URL to confirm:

- Layout still renders correctly on common viewport widths (resize your browser to ~360px and ~1280px).
- Asset paths resolve (no broken CSS or images). If assets are broken, the `<base href>` injection likely failed — see troubleshooting.
- No console errors in the browser devtools.

For visual changes, take fresh screenshots in both desktop and mobile viewports and attach them to the PR. The PR template has placeholders for these.

---

## 5. Why previews are hosted under `constructorfabric.github.io`

There are two reasons:

1. **Origin separation.** Previews run contributor-controlled HTML and JavaScript. Hosting them under `constructorfabric.github.io` instead of `constructorfabric.org` means a malicious preview cannot read production cookies, set cookies on the production domain, or trick a logged-in user.
2. **Privilege separation.** Only the low-privilege `Website PR CI` workflow touches the source repo. The privileged `Publish Website Preview` workflow uses a GitHub App installation token scoped **only** to `constructorfabric/website-previews`. There is no token in the source repo's secrets that can write to the source repo itself.

The trade-off is that preview URLs are slightly less pretty. We accept this.

---

## 6. Required admin configuration

The following are configured **once**, by a repository administrator. Contributors do not need to touch any of this.

### In `constructorfabric/website` (source repo)

**Repository variables** (Settings → Secrets and variables → Actions → Variables):

| Name | Value |
| --- | --- |
| `AUTOMATION_APP_ID` | Numeric ID of the GitHub App (the existing "Constructor Fabric App" or a dedicated "Constructor Fabric Website Preview App"). |
| `PREVIEW_REPOSITORY` | `constructorfabric/website-previews` |
| `PREVIEW_RETENTION_DAYS` | `30` |

**Repository secrets**:

| Name | Value |
| --- | --- |
| `AUTOMATION_APP_PRIVATE_KEY` | Private key downloaded from the GitHub App's settings page. |

### In `constructorfabric/website-previews` (preview repo)

- GitHub Pages enabled, branch `main`, folder `/ (root)`.
- GitHub App installed with `Contents: Read and write` (and `Metadata: Read`).
- The starter files from `.preview-repository/` in the source repo pushed to `main`.

### GitHub App permissions

Minimum required for preview publishing:

- Repository permissions: **Contents: Read and write**, **Metadata: Read**
- Installed only on `constructorfabric/website-previews`
- No organization-wide permissions

If the existing "Constructor Fabric App" has broader scope or is installed on many repos, prefer creating a dedicated app for website previews. See `.dev/01_manual_operations_guide.md` in this repo for the full setup procedure.

### Branch protection on `main` in the source repo

After the first successful run of `Website PR CI`, add it as a required status check:

- Check name: **`Website PR CI / build, lint, link check`**

Do **not** require `Publish Website Preview` or `Deploy Website Production` as a PR status check — both run after the PR is approved/merged and neither gates the merge.

---

## 7. How cleanup works

A scheduled workflow in `constructorfabric/website-previews` (`.preview-repository/.github/workflows/cleanup-previews.yml`) runs **daily at 03:17 UTC**. It:

1. Reads the `PREVIEW_RETENTION_DAYS` repository variable (default: `30`) from the preview repo.
2. Iterates over every `pr-*` directory.
3. For each, finds the timestamp of the most recent commit that touched that directory.
4. If the timestamp is older than the retention period, deletes the directory with `git rm -rf`.
5. Commits and pushes the deletion.

The cleanup can also be triggered manually with `workflow_dispatch`. You can override the retention period per-run by passing a `retention_days` input — useful for testing.

**Important**: the retention clock is based on the **last commit** to the directory, not the original PR open time. A PR that is still being updated stays alive.

---

## 8. Troubleshooting

### "I opened a PR but no preview URL appeared."

1. Open the PR's **Checks** tab. Look for:
   - `Website PR CI` — failed?
   - `Publish Website Preview` — failed?
2. If `Website PR CI` failed, read its log. Common causes:
   - **Build script error.** The build script is `.github/scripts/build.sh`. It runs `rsync` (with `cp` fallback), then `python3` to inject `<base href>`. If neither tool is present on the runner, the build will fail — but `ubuntu-latest` has both.
   - **Forbidden file paths.** GitHub Actions cannot check out files with paths that match certain patterns. Check for unusual filenames in your diff.
3. If `Website PR CI` succeeded but `Publish Website Preview` did not run, confirm that `Website PR CI` actually finished with `success` and that the workflow_run trigger is configured (it is, in `website-preview-publish.yml`).
4. If `Publish Website Preview` failed, read its log. Common causes:
   - **Missing or invalid secrets/variables.** `AUTOMATION_APP_ID`, `AUTOMATION_APP_PRIVATE_KEY`, or `PREVIEW_REPOSITORY` are wrong.
   - **App not installed on the preview repo**, or lacks `Contents: Read and write`.
   - **gh CLI auth failed.** `actions/create-github-app-token@v2` will error if the app ID or private key is invalid.
5. If everything ran but the preview URL returns 404:
   - The preview directory may have been cleaned up. Re-trigger by pushing a new commit.
   - The preview repo's GitHub Pages settings may have been disabled. Re-enable under Settings → Pages.

### "The preview loads but assets (CSS, JS, images) are broken."

The build script injects `<base href="/website-previews/pr-<N>/">` into every HTML file. If a new HTML file was added that does not contain a `<head>` tag, the injection is skipped. Confirm:

```bash
curl -s https://constructorfabric.github.io/website-previews/pr-<N>/ | head
```

You should see a `<base ...>` line right after `<head>`. If not, file an issue.

### "Production is broken."

Production is unaffected by PR previews. If `constructorfabric.org` is broken:

1. Check the **`Deploy Website Production`** workflow runs on `main`. The most recent run will tell you whether the deploy itself failed.
2. If a recent commit to `main` introduced the regression, revert it.
3. The production build does **not** inject a `<base>` tag. If `constructorfabric.org` is serving HTML with a `<base href="/website-previews/...">`, the wrong workflow ran — investigate immediately and roll back.

### "Cleanup deleted a preview I still need."

The retention period is configurable. You can either:

- Push a new commit to the PR to re-deploy the preview.
- Or, manually re-create the directory:
  ```bash
  gh workflow run Publish\ Website\ Preview --repo constructorfabric/website
  # find the latest successful PR CI run for that PR, then re-trigger publish
  ```
  In practice, just pushing a commit is simpler.

---

## 9. Local validation

Before pushing, you can mirror the CI build locally:

```bash
# Preview build
OUTPUT_DIR=./_site PREVIEW_BASE_PATH=/website-previews/pr-test/ bash .github/scripts/build.sh
( cd _site && python3 -m http.server 8000 )
# Open http://localhost:8000/pr-test/ — assets should resolve under that path.

# Production build
OUTPUT_DIR=./_site bash .github/scripts/build.sh
( cd _site && python3 -m http.server 8001 )
# Open http://localhost:8001/ — assets should resolve at root.
```

If `python3` complains about indentation in the inline script, you are using an older version. `python3.7+` is fine; `python3.9+` recommended.