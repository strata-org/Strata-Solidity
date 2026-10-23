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
pip install -r docs/site/requirements.txt   # once
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

`.github/workflows/deploy-pages.yml` builds this site and deploys it to
<https://strata-org.github.io/Strata-Solidity/> on every push to `main` that
changes `docs/site/` or `docs/guide/src/`, and on demand from the Actions
tab. It then fails if the published root or guide index does not serve the
site.

The repository's Pages source must stay "GitHub Actions" (Settings →
Pages). With a branch source, GitHub's built-in `pages-build-deployment`
also runs on every push and publishes a Jekyll render of the folder, which
has no `index.html` because the generated pages are not committed.
