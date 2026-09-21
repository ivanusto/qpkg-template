# qpkg-template

[繁體中文](README.zh-TW.md)

A template for thin QNAP Container Station QPKGs. The package ships no Docker image and no binaries: only management scripts, a configuration template, an image lock file and a first-run status page. Container Station downloads the image in the background after installation.

The skeleton is extracted from [open-webui-ollama-qpkg](https://github.com/ivanusto/open-webui-ollama-qpkg) v1.0.7; the layout follows [qnap-dev/containerized-qpkg](https://github.com/qnap-dev/containerized-qpkg). The bundled demo app is [traefik/whoami](https://github.com/traefik/whoami), a stateless HTTP service of a few MB that proves the skeleton builds and installs.

## Features

- **Never blocks the QTS boot.** If Container Station is not ready, the start is handed to a `setsid`-detached background job and the init script returns at once.
- **Waits until the daemon is really up.** Both `docker info` and `docker ps` must succeed, twice in a row 10 s apart.
- **Idempotent start with configuration fingerprints.** Every `docker run` argument is hashed; a container is recreated only when its settings changed, otherwise it is simply started.
- **Image digest pinning.** `images.lock` records `repository:tag@sha256:...`; the local image digest is verified after start, and `update` only changes versions when someone changed a pin.
- **Status page.** While images download, a busybox httpd holds the web port and shows progress; once the app's health path answers, the same URL becomes the app.
- **`diag` subcommand.** Docker, registry DNS, pin state, containers, network, settings and the latest logs in one go.
- **Verifiable releases.** CI attaches `SHA256SUMS`, `images.lock` and a GitHub build provenance attestation.

## The two layers

| Layer | File | Contents | Edit for a new app? |
|---|---|---|---|
| Generic | `shared/lib/qpkg-core.sh` | docker discovery and waiting, detached jobs, idempotent start and fingerprints, digest checks, status page, `diag`, command dispatch | No |
| Generic | `package_routines` | Container Station check, keep existing settings, background download, keep data on removal | Names only (done by `new-app.sh`) |
| Generic | `shared/web/index.html` | State machine, polling, hand-over to the app | No |
| Generic | `Dockerfile`, `Makefile`, CI | QDK build, tests, release | No |
| App | `shared/<slug>.sh` | Settings block, container list, `docker run` arguments, status page fields | Yes |
| App | `shared/images.lock` | Images and digests | Yes |
| App | `shared/<slug>.conf.default` | User-tunable settings | Yes |
| App | `qpkg.cfg`, `icons/` | Package description, default port, icons | Yes |

## Creating a package from the template

1. Click "Use this template" on GitHub and clone the new repository.
2. Rename:

   ```sh
   scripts/new-app.sh JellyfinQnap "Jellyfin" jellyfin
   ```

   The first argument is App Center's internal name. App Center treats packages with the same internal name as the same app, so a store app with that name would overwrite yours. Do not use the bare upstream name.

3. Pin the image:

   ```sh
   scripts/pin-images.sh APP_IMAGE=jellyfin/jellyfin:10.11.0
   ```

4. Edit the settings block and hooks in `shared/<slug>.sh` (next section), `QPKG_VER` and `QPKG_WEB_PORT` in `qpkg.cfg`, and replace `icons/`.
5. Test and build:

   ```sh
   make test   # shellcheck, pin check, lifecycle test, new-app test
   make        # build/<name>_<version>_x86_64.qpkg
   ```

## Settings and hooks in the service script

| Name | Required | Purpose |
|---|---|---|
| `QPKG_NAME`, `DISPLAY_NAME`, `SCRIPT_NAME`, `CONF_NAME` | yes | Names, filled in by `new-app.sh` |
| `CONTAINERS` | yes | Container ids in start order; stop runs in reverse |
| `OPTIONAL_CONTAINERS` | no | Ids whose start failure is logged as a warning instead of failing the app; the status page marks them |
| `WEB_ID` | yes | Id of the container that publishes `WEB_PORT`; the status page borrows that port |
| `HEALTH_PATH` | yes | Path that answers 2xx once the app is ready; the status page hands over on it |
| `DIAG_HOSTS` | no | Extra hosts for the `diag` DNS check |
| `app_defaults` | yes | Fill in unset defaults; at least `<ID>_CONTAINER_NAME` and `WEB_PORT` |
| `app_run_<id>` | yes | Create the container with `"$DOCKER" run -d` |
| `app_fingerprint_<id>` | yes | Print every value used on the `docker run` line; anything missing is silently not applied |
| `app_enabled_<id>` | no | Return non-zero to switch the container off: it is not downloaded, created or listed, and a running one is stopped. Its image must still be pinned |
| `app_needs_recreate_<id>` | no | Return 0 to recreate a stopped container, e.g. GPU self-heal after a late runtime registration |
| `app_run_fallback_<id>` | no | Fallback when `app_run_<id>` fails, e.g. retry without `--gpus` |
| `app_status_fields` | no | Extra status page rows, one `label_en\|label_zh\|value` per line |
| `app_diag` | no | Extra `diag` output |

Per-container variables use the uppercase id as prefix: `<ID>_IMAGE` (from `images.lock`, overridable in the .conf file), `<ID>_CONTAINER_NAME`, and optionally `<ID>_DATA_PATH` (created by the core before the container). For a secret that must be generated once and kept, call `ensure_secret <VAR>` in `app_defaults`.

## Subcommands

Run as admin on the NAS. Without root the containers still work, but the QTS event log and the App Center link port cannot be updated.

```sh
sudo /etc/init.d/myapp.sh status
sudo /etc/init.d/myapp.sh restart          # apply settings; only changed containers are recreated
sudo /etc/init.d/myapp.sh update --check   # has the pinned tag moved upstream? touches nothing
sudo /etc/init.d/myapp.sh update           # apply a changed pin
sudo /etc/init.d/myapp.sh diag
sudo /etc/init.d/myapp.sh remove           # remove containers and network, keep data
```

States in `status.json`: `waiting-for-container-station`, `downloading-image`, `pull-failed`, `starting`, `running`, `stopped`, `error`, `no-container-engine`.

## Pinning and upgrades

`shared/images.lock` ships with the package, one `KEY=repository:tag@sha256:digest` per line. The tag is for humans; the digest is what runs. It is the manifest list digest, so one pin covers both x86_64 and ARM models.

To upgrade:

1. `sudo /etc/init.d/<slug>.sh update --check` on the NAS, or `scripts/pin-images.sh` on a workstation, to see whether upstream moved.
2. `scripts/pin-images.sh APP_IMAGE=<repository>:<new tag>` in the repository and release a new QPKG, or override `APP_IMAGE` in the .conf file on the NAS.
3. `update` or `restart`; only containers whose image or settings changed are recreated.

A floating tag (no `@sha256`) in the .conf file still works, but it logs a warning and shows as unpinned on the status page and in `diag`.

Each container has one of five pin states: `pinned-ok` (the local image matches the pin), `pinned-mismatch` (it does not; logged as an error), `unpinned` (floating tag; warning), `unverifiable` (imported with `docker load`, no registry digest to compare; warning), `missing` (not downloaded yet).

## Verifying a release

```sh
sha256sum -c SHA256SUMS
gh attestation verify MyApp_0.2.1_x86_64.qpkg --repo ivanusto/qpkg-template --source-ref refs/tags/v0.2.1
```

`images.lock` is attached to the release as well, so you can see which image a package pins without unpacking it.

Keep `--source-ref`. An attestation is bound to file content, and identical files (such as an unchanged `images.lock`) carry one attestation per release, so without it any of them passes. `gh attestation` needs GitHub CLI 2.49.0 or later.

## Supply chain of the CI itself

The build tools follow the same rule as the app image: never reference a name someone else can move.

| Reference | Pinned as | Updated by |
|---|---|---|
| GitHub Actions | full commit SHA, version in a comment | Dependabot, weekly PRs |
| QDK | `QDK_REF`, identical in the workflow and the Dockerfile | by hand, both places |
| builder base image | `ubuntu:22.04@sha256:...` | Dependabot, weekly PRs |
| shellcheck image | `SHELLCHECK` in the Makefile with a digest | by hand |

`scripts/check-ci-pins.sh` (part of `make check-pins`) checks all four and fails CI if any of them falls back to a movable reference. On a tag, CI also checks that the tag matches `QPKG_VER` in `qpkg.cfg` and refuses to release otherwise: bump `qpkg.cfg` and the CHANGELOG, commit, then tag.

## Installing on the NAS

1. App Center, "Install Manually" (top right), pick the `.qpkg`.
2. The package is not signed by QNAP. If it is rejected, allow unsigned applications in App Center settings, General tab.
3. Open the app from its icon: the status page shows the download, then the app takes over.

## Notes

- QDK's installer compiles `qpkg_encrypt`. Without gcc the resulting `.qpkg` is rejected by App Center; the Dockerfile installs it.
- The scripts run on busybox sh under QTS and must keep LF line endings; `.gitattributes` enforces this.
- Only x86_64 is built. The payload is architecture-independent: for ARM add `QDK_DATA_DIR_ARM_64` to `qpkg.cfg` and build with `qbuild --build-arch arm_64`.
- A thin package needs registry access from the NAS. On isolated networks prefer a private registry, where digest verification keeps working. If you import with `docker save` / `docker load` instead, export by **tag** (`docker save repository:tag`; an image saved by digest loads back with no name at all). An imported image has no registry digest, so the package starts it by tag and reports `unverifiable`: the pin cannot be checked.

## License

Apache-2.0, see [LICENSE](LICENSE).
