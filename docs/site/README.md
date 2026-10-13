# StrataSolidity website

A landing page and user guide, built as static HTML from the same markdown
that feeds the `docs/guide` mdBook sources (`docs/guide/src/*.md` is the one
copy; nothing here duplicates it).

```
_src/
  build.py             generates index.html, docs/*.html, assets/search-index.js
  capture_outputs.py   runs the real strataSolidity binary on _src/examples/*.sol
                        and saves its output, so the landing page never shows
                        invented output
  templates/           page shells (doc.html, landing.html)
  examples/            contracts shown on the landing page, plus captured
                        *.out and outputs.json
assets/                site.css, site.js, favicon.png, strata-mark.png
docs/, index.html, assets/search-index.js   generated — gitignored, not committed
```

## Building

From the repository root, after `lake build`:

```bash
pip install markdown pygments      # once
python3 docs/site/_src/capture_outputs.py   # refresh examples/*.out (needs a working strataSolidity build)
python3 docs/site/_src/build.py             # generate the site
```

Open `docs/site/index.html` directly, or serve the directory
(`python3 -m http.server --directory docs/site`).

## Fonts

The page uses the system font stack (`-apple-system`, `Segoe UI`, etc.), not
a bundled typeface — this is a public repository, and the Amazon Ember font
files used by some internal AWS brand templates carry a redistribution
restriction that isn't appropriate here.

## Deployment

`.github/workflows/deploy-pages.yml` builds this site and uploads it as a
Pages artifact. The workflow trigger is intentionally left at
`workflow_dispatch` only — GitHub Pages is not enabled for this repository.
Restoring the `push` trigger is a maintainer decision once Pages is turned on
in the repository settings.
