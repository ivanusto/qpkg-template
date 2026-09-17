# Changelog

## v0.1.2

- CI 引用的東西全部鎖定：四個 GitHub Actions 釘到完整 commit SHA 並以註解保留版本號（checkout v4.4.0、upload-artifact v4.6.2、attest-build-provenance v2.4.0、action-gh-release v2.6.2）；QDK 釘在 `b7b5f4c`，workflow 與 Dockerfile 共用同一個 `QDK_REF`；Dockerfile 的 `ubuntu:22.04` 與 Makefile 的 shellcheck image 改以 digest 鎖定。
- 新增 `scripts/check-ci-pins.sh`，併入 `make check-pins` 與 CI，任一項退回浮動參考就讓建置失敗。
- 打 tag 時檢查 tag 與 `qpkg.cfg` 的 `QPKG_VER` 一致，不一致就不發 release。
- 新增 `.github/dependabot.yml`，每週為 Actions 與 Dockerfile 基底 image 提 PR；`QDK_REF` 與 shellcheck image 需手動更新。
- `tests/lifecycle.sh` 開始前一併刪除示範 image 的裸 tag，結束時清掉 docker load 情境留下的 tag。原本本機若殘留該 tag，首次啟動會跳過下載流程並判成 `unverifiable`，GitHub 的 runner 不受影響。

## v0.1.1

- `NOTICE.md`：來源、關係聲明、上游軟體授權與商標。`scripts/new-app.sh` 會把上游段落換成待填的佔位文字；release 與 `SHA256SUMS` 一併附上。
- 以 `docker load` 匯入的 image 可以啟動。匯入後 image 保有 tag 但沒有 RepoDigests，`repository:tag@sha256` 參考在本機查不到，v0.1.0 會誤判為尚未下載而進入下載流程，隔離網段最後停在 `pull-failed`。現在改以 tag 啟動（僅限該 tag 沒有任何 repo digest 時），鎖定狀態標示為新的 `unverifiable`。
- `tests/lifecycle.sh` 新增匯入情境；`tests/new-app.sh` 檢查 NOTICE.md 佔位。

## v0.1.0

- 從 open-webui-ollama-qpkg v1.0.7 抽出的薄殼骨架：`shared/lib/qpkg-core.sh` 通用引擎、`shared/myapp.sh` 示範 App（traefik/whoami）。
- `shared/images.lock` digest 鎖定，`scripts/pin-images.sh`、`scripts/check-pins.sh`，`update --check`。
- CI：shellcheck、pin 檢查、生命週期與 new-app 測試、qbuild，tag 時發 release 並附 `SHA256SUMS` 與 build provenance attestation。
