#!/usr/bin/env bash
# build.sh — Static-site build for the Constructor Fabric website.
#
# This site has no framework and no package manager: HTML, CSS, JS, and assets
# live at the repository root and are served as-is. The "build" step exists to
# support two goals:
#
#   1. Production deploy: copy the repository contents into the deploy artifact
#      unchanged. The site is served from "/" so asset paths in HTML files
#      resolve naturally.
#
#   2. PR preview: copy the repository contents into the deploy artifact and
#      inject <base href="/website-previews/pr-<N>/"> into each HTML file so
#      repo-root-relative asset paths (e.g. styles.css, partials.jsx,
#      assets/img/favicon.svg) resolve under the preview subpath.
#
# Env vars:
#   PREVIEW_BASE_PATH  Optional. If set, the value is used as the <base href>
#                      and a preview-meta.json file is written into OUTPUT_DIR.
#                      Must start and end with "/" (e.g. /website-previews/pr-123/).
#   OUTPUT_DIR         Directory to populate with the build output.
#                      Defaults to "./_site".
#
# Exits non-zero on the first error.

set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-./_site}"
PREVIEW_BASE_PATH="${PREVIEW_BASE_PATH:-}"

echo "Build start"
echo "  OUTPUT_DIR        = ${OUTPUT_DIR}"
echo "  PREVIEW_BASE_PATH = ${PREVIEW_BASE_PATH:-<unset — production build>}"

# Validate PREVIEW_BASE_PATH if present.
if [[ -n "${PREVIEW_BASE_PATH}" ]]; then
  if [[ "${PREVIEW_BASE_PATH:0:1}" != "/" || "${PREVIEW_BASE_PATH: -1}" != "/" ]]; then
    echo "Error: PREVIEW_BASE_PATH must start and end with '/'" >&2
    exit 1
  fi
fi

# Clean and recreate output dir.
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Copy repo contents (including dotfiles like CNAME, robots.txt, .gitignore is
# intentionally excluded by the caller) into OUTPUT_DIR.
# Use rsync if available for cleaner dotfile handling; fall back to cp.
if command -v rsync >/dev/null 2>&1; then
  # -a: archive, --exclude: skip .git and .dev (dev-only scratch space)
  rsync -a --exclude='.git' --exclude='.dev' --exclude='_site' ./ "${OUTPUT_DIR}/"
else
  # Fallback: copy visible files and a few known dotfiles explicitly.
  cp -R ./* "${OUTPUT_DIR}/" 2>/dev/null || true
  for f in CNAME robots.txt .nojekyll; do
    if [[ -f "${f}" && ! -e "${OUTPUT_DIR}/${f}" ]]; then
      cp "${f}" "${OUTPUT_DIR}/${f}"
    fi
  done
fi

# Inject <base href> for preview builds only.
if [[ -n "${PREVIEW_BASE_PATH}" ]]; then
  echo "Injecting <base href=\"${PREVIEW_BASE_PATH}\"> into HTML files"
  # Find every .html file in OUTPUT_DIR (portable, no GNU-only flags).
  # Use a while-read loop to handle paths with spaces safely.
  find "${OUTPUT_DIR}" -type f -name '*.html' -print0 |
    while IFS= read -r -d '' html_file; do
      # Use python for an exact, idempotent edit: insert <base ...> immediately
      # after <head> if not already present.
      python3 - "$html_file" "${PREVIEW_BASE_PATH}" <<'PYEOF'
import re
import sys

path = sys.argv[1]
base = sys.argv[2]

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Skip if a <base> tag is already present (idempotent).
if re.search(r'<base\s', content, flags=re.IGNORECASE):
    sys.exit(0)

# Insert <base> right after <head> (case-insensitive, allow attributes on <head>).
new_tag = f'<base href="{base}"/>'
new_content, n = re.subn(
    r'(<head\b[^>]*>)',
    r'\1\n' + new_tag,
    content,
    count=1,
    flags=re.IGNORECASE,
)

if n == 0:
    # No <head> tag — unusual; fall back to inserting right after <html ...>.
    new_content, n2 = re.subn(
        r'(<html\b[^>]*>)',
        r'\1\n<head>' + new_tag + '</head>',
        content,
        count=1,
        flags=re.IGNORECASE,
    )
    if n2 == 0:
        print(f'WARN: no <head> or <html> tag in {path}; skipping base injection', file=sys.stderr)
        sys.exit(0)

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)
PYEOF
    done

  # Write preview-meta.json describing this deployment.
  # Values are intentionally simple — these are read by humans, not the app.
  pr_number="$(echo "${PREVIEW_BASE_PATH}" | sed -E 's@.*/pr-([0-9]+)/?$@\1@')"
  meta_path="${OUTPUT_DIR}/preview-meta.json"
  cat > "${meta_path}" <<JSON
{
  "pr_number": ${pr_number:-null},
  "preview_base_path": "${PREVIEW_BASE_PATH}",
  "preview_url": "https://constructorfabric.github.io/website-previews/pr-${pr_number:-unknown}/"
}
JSON
  echo "Wrote ${meta_path}"
fi

echo "Build done"
ls -la "${OUTPUT_DIR}"