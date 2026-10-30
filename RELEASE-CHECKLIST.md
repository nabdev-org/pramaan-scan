# Release checklist for pramaan-scan v1.0.0

This folder is a local git repository with one commit and no remote. Nothing has been published. These are the steps to publish it as `nabdev-org/pramaan-scan` and list it on GitHub Marketplace.

Delete this file before the first push, or keep it in the repository as the maintainer's checklist. Marketplace asks that the repository hold only what the action needs, so deleting it is the cleaner choice.

## 1. Decide first

- [ ] Licence. Choose MIT or Apache-2.0, add `LICENSE`, delete `LICENSE.choose-me.md`. See that file.
- [ ] Repository name. `pramaan-scan` gives `uses: nabdev-org/pramaan-scan@v1`. No reason was found to change it.
- [ ] Marketplace name. The `name` in `action.yml` is `Pramaan scan`. It must not match another Marketplace action, a user or organisation, or a Marketplace category. Search https://github.com/marketplace?type=actions for it. If it is taken, change `name` and say so in `CHANGELOG.md`.
- [ ] Default collector. `collector_version` defaults to `0.29.0` and `collector_sha256` to empty, from `integrations/collector-pin.json` in the platform repo. Customers whose Pramaan serves another version must set `collector_version`. Keep that version in step with what new installations serve.
- [ ] Pinned sha256 or not. With no signed collector release yet, `collector-pin.json` has an empty sha256, so the action reads `SHA256SUMS` from the customer's Pramaan. That works today. It is weaker than a pin, and the README says so. Recommendation: keep the default empty in this public action even after the first signed release. A default sha256 only fits customers on that exact version. A customer who changed `collector_version` alone would fail with a sha256 mismatch. Tell customers to pin their own sha256 from Settings, Collectors instead. If you do put a default sha256 here, it must be from a signed release, and the README section "How the collector is checked" needs a line saying which version it belongs to.

## 2. Check before you publish

- [ ] A Pramaan you control serves `{api_url}/downloads/collector/pramaan-0.29.0.pyz` and `{api_url}/downloads/collector/SHA256SUMS` with no sign-in, and `SHA256SUMS` has a line for `pramaan-0.29.0.pyz`.
- [ ] Run the action once end to end against UAT from a private test repository, before the Marketplace listing. Use a throwaway upload key registered on a test application, with `uses: ./` or the local path. Check an upload lands, `fail_on: P0` passes on a clean repository, and `fail_on: none` returns without waiting. The self-test in `tests/` uses a fake collector and never reaches a real Pramaan.
- [ ] https://pramaan.neaurabuild.com is live and says what the README links to it for.
- [ ] contactus@neaurabuild.com is read by someone who can handle a security report.
- [ ] The organisation's Actions policy allows `actions/*` and `raven-actions/actionlint`, which the test workflow uses. Organisation settings, Actions, General.

## 3. Create the repository and push

Run these from this folder, signed in to `gh` as an owner of `nabdev-org`:

```
cd "/Users/amman/dev/SBOM+CBOM/pramaan-scan-action"
git add -A && git commit -m "Add licence"        # after choosing the licence
gh repo create nabdev-org/pramaan-scan --public \
  --description "Make an SBOM with the Pramaan collector, upload it signed, and fail on new findings." \
  --source . --remote origin
git push -u origin main
```

Then on GitHub:

- [ ] Actions tab: the Test workflow passes on `ubuntu-latest` and `macos-latest`.
- [ ] Settings, General: turn off Wiki and Projects if not used.
- [ ] Settings, Code security: turn on private vulnerability reporting, so reports can also come through GitHub.
- [ ] Settings, Rules: protect `main` (pull requests, the Test check required) and add a tag rule for `v*` so only maintainers can create or move release tags.

## 4. Tag v1.0.0 and v1

```
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
git tag -a v1 -m "v1 -> v1.0.0" v1.0.0^{}
git push origin v1
```

For each later 1.x release, tag the new version, then move `v1` to it:

```
git tag -a v1.0.1 -m "v1.0.1" && git push origin v1.0.1
git tag -fa v1 -m "v1 -> v1.0.1" v1.0.1^{} && git push --force origin v1
```

`v1` moves. `v1.0.0` never does. Customers who pin a commit sha are not affected by either.

## 5. List it on GitHub Marketplace

1. An owner of `nabdev-org` accepts the GitHub Marketplace Developer Agreement. The publish screen in step 3 below links to it, and the publish box stays disabled until it is accepted.
2. Make sure the account publishing has two-factor authentication on. Publishing needs it.
3. Open `action.yml` on the repository page and choose Draft a release in the banner.
4. Tick Publish this Action to the GitHub Marketplace.
5. Fix anything the metadata check reports until it says everything looks good. It reads `name`, `description`, `author` and `branding` from `action.yml`.
6. Primary category: Security. Second category: Continuous integration (or Dependency management).
7. Icon and colour come from `branding` in `action.yml`: the Feather icon `shield` on `blue`. Check the preview. To change them, edit `action.yml` and release again.
8. Choose the existing tag `v1.0.0`. Title `v1.0.0`. Paste the 1.0.0 section of `CHANGELOG.md` as the notes.
9. Publish release.

## 6. After publishing

- [ ] Search the Marketplace for "Pramaan scan" and open the listing. Check the README renders and the links work.
- [ ] Change the GitHub Actions example in the platform repo's `integrations/github-action/README.md` and the product's Settings, Collectors help to `uses: nabdev-org/pramaan-scan@v1`.
- [ ] When a new collector ships, `tools/release/collector_release.py pin` updates the four templates in the platform repo, but not this repository. Bump `collector_version` (and `collector_sha256`, if you chose to pin one) here by hand. Its `action.yml` keeps the same layout, so the same patterns match. Then release a new 1.x version.
