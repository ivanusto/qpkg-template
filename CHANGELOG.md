# Changelog

## v0.1.1

- `NOTICE.md`：來源、關係聲明、上游軟體授權與商標。`scripts/new-app.sh` 會把上游段落換成待填的佔位文字；release 與 `SHA256SUMS` 一併附上。
- 以 `docker load` 匯入的 image 可以啟動。匯入後 image 保有 tag 但沒有 RepoDigests，`repository:tag@sha256` 參考在本機查不到，v0.1.0 會誤判為尚未下載而進入下載流程，隔離網段最後停在 `pull-failed`。現在改以 tag 啟動（僅限該 tag 沒有任何 repo digest 時），鎖定狀態標示為新的 `unverifiable`。
- `tests/lifecycle.sh` 新增匯入情境；`tests/new-app.sh` 檢查 NOTICE.md 佔位。

## v0.1.0

- 從 open-webui-ollama-qpkg v1.0.7 抽出的薄殼骨架：`shared/lib/qpkg-core.sh` 通用引擎、`shared/myapp.sh` 示範 App（traefik/whoami）。
- `shared/images.lock` digest 鎖定，`scripts/pin-images.sh`、`scripts/check-pins.sh`，`update --check`。
- CI：shellcheck、pin 檢查、生命週期與 new-app 測試、qbuild，tag 時發 release 並附 `SHA256SUMS` 與 build provenance attestation。
