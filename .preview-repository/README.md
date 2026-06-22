# website-previews — setup instructions

This directory contains starter files for the **`constructorfabric/website-previews`** repository.

That repository is the destination for pull request previews of `constructorfabric/website`. It is **separate** from the source repository so that contributor-controlled HTML and JavaScript can never run on the production origin (`constructorfabric.org`).

## Why a separate repo?

- Previews are served from `https://constructorfabric.github.io/website-previews/pr-<N>/` — a different origin from production.
- Only a low-privilege workflow in the source repo uploads preview artifacts. The privileged publishing workflow uses a GitHub App installation token scoped only to `website-previews`, so a compromised PR cannot write to the source repo or any other repo.
- Old previews are cleaned up automatically by a scheduled workflow in this repo.

## One-time setup (admin)

1. **Create the repository** `constructorfabric/website-previews` (public).
2. **Enable GitHub Pages**: Settings → Pages → Branch: `main`, Folder: `/ (root)`.
3. **Install the GitHub App** ("Constructor Fabric App" or a dedicated preview app) on this repository with:
   - Repository permissions: **Contents: Read and write**, **Metadata: Read**
4. **Push the starter files from this directory** to `website-previews`:
   ```bash
   # from a fresh clone of constructorfabric/website-previews
   cp -R /path/to/constructorfabric/website/.preview-repository/. .
   # particularly:
   #   index.html
   #   robots.txt
   #   README.md
   #   .github/workflows/cleanup-previews.yml
   git add . && git commit -m "Initial preview-repo setup" && git push origin main
   ```
5. **Configure variables/secrets in the SOURCE repo** (`constructorfabric/website`):
   - Variables: `AUTOMATION_APP_ID`, `PREVIEW_REPOSITORY=constructorfabric/website-previews`, `PREVIEW_RETENTION_DAYS=30`
   - Secret: `AUTOMATION_APP_PRIVATE_KEY`

## Files in this directory

| File | Purpose |
| --- | --- |
| `index.html` | Placeholder landing page. Real content is added under `pr-<N>/` by automation. Includes `<meta name="robots" content="noindex, nofollow">`. |
| `robots.txt` | Tells well-behaved crawlers to stay out of all preview pages. |
| `README.md` | This file. |
| `.github/workflows/cleanup-previews.yml` | Daily cleanup of stale previews. |

## Cleanup behavior

The cleanup workflow runs daily at 03:17 UTC and can also be triggered manually with `workflow_dispatch`. It:

1. Reads the `PREVIEW_RETENTION_DAYS` repository variable (default: `30`).
2. Removes any `pr-*` directory whose last commit is older than the retention period.
3. Commits and pushes the deletion.

The retention period applies to the **last commit time of the preview directory**, not the original PR open time. A PR that keeps getting updated stays alive.

## Manual cleanup (testing)

To force-delete a preview immediately (useful when testing):

```bash
gh workflow run cleanup-previews.yml \
  --repo constructorfabric/website-previews \
  -f retention_days=0
```

Use `0` only against test previews.