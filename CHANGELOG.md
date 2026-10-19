# Changelog

## v0.2.4

- **修正開機時可能跑到 QTS 的系統 Docker。** `find_docker` 在 Container Station 的 `bin/docker` 不能執行時，會退而使用 `system-docker`，那是 QTS 自己的 daemon（AI 服務中心、LLM Core 等都在上面）。QuTS hero h6.1 開機時，`bin/docker` 是指向 `/lib/container-station/wrapper/` 的符號連結，目標要等 Container Station 啟動後才建立，`system-docker` 卻已經能回應。open-webui-ollama-qpkg 2.1.0 的測試中實際發生：App 把狀態頁、網路與 busybox 建在 `system-docker` 上，`_bg_start` 在等待迴圈裡找不到自己的容器，約 16 分鐘後才進入下載流程。現在只使用 Container Station 的 docker，找不到時回傳失敗，由呼叫端繼續等待；修正後同一台 NAS 開機 62 秒內正常啟動。曾受影響的 NAS 可用 `system-docker ps -a` 檢查是否留有 `*-landing` 容器。
- `pkg_post_install` 在 `chown -R 0:0` 之後移除群組與其他人的寫入權限。QTS 的 gid 0 是 administrators 群組，以 umask 002 建置的套件會讓所有管理者帳號都能修改以 root 執行的腳本。GitHub runner 的建置原本就是 644／755。
- `tests/lifecycle.sh` 新增「Container Station 的 CLI 不能執行時不使用 `system-docker`」情境，共 77 項；在 v0.2.3 的核心上這個情境會失敗。

## v0.2.3

- **修正升級時狀態頁可能搶走網頁埠。** App Center 升級時先跑 post-install 的 `bgpull`，再跑 `start`。在 NAS 上 Container Station 忙於安裝，`_bg_pull` 可能晚幾秒才走到開狀態頁的判斷，此時舊容器剛被暫停、`start` 正要以 `KEEP_OLD` 重新啟動它；舊判斷是「web 容器沒在執行就開狀態頁」，於是兩者搶同一個埠。open-webui-ollama-qpkg 2.0.3 實際遇到，App 早約 0.1 秒拿到埠；若狀態頁先綁到，`docker start` 失敗，`do_start` 改走下載路徑，App 停機到新映像下載完。現在改看 web 容器是否存在：存在就只寫 `updating`，交給隨後的啟動讓舊版繼續服務；首次安裝沒有容器，照舊顯示狀態頁。
- `tests/lifecycle.sh` 的 4b 情境改照 App Center 的順序先跑 `bgpull`，並以可變慢的 docker 包裝讓下載停在進行中，共 76 項。

## v0.2.2

- **升級時不再停機等下載。** v0.2.1 遇到新的鎖定值時，會先停掉容器、讓狀態頁佔住網頁埠，下載完才重建；下載很慢時 App 就一直停著。open-webui-ollama-qpkg 2.0.1 實際遇到：open-webui v0.11.4 發佈當天 ghcr 只有約 80 KB/s，NAS 停機 25 分鐘。現在既有容器先以舊版繼續服務（`run_container` 的 `KEEP_OLD` 路徑），背景下載完成後以 `RECREATE_RUNNING=1` 替換；下載失敗時維持舊版，狀態仍是 `running`，事件記錄寫警告。
- 背景下載遇到先前留下、仍在進行的下載（可能是舊版腳本啟動的）時，改為等它結束再自己套用結果，不再直接退出；舊版腳本不會替換執行中的容器。
- 狀態頁新增 `updating` 狀態。`PULL_RETRY_DELAY` 可調整整輪下載的重試間隔（預設 30 秒）。
- `tests/lifecycle.sh` 新增下載失敗與接手舊下載的情境，共 72 項。

## v0.2.1

- 升級時不再在前景下載 image。`start` 原本只要容器都存在就直接進 `run_all`，當新版套件帶來新的鎖定 digest 時，容器因指紋不同要重建，`docker run` 會在前景把整個 image 拉下來，App Center 一直等到下載完。現在逐一判斷：image 在本機，或容器存在且不需要重建（`docker start` 不需要 image），才直接啟動；否則走狀態頁與背景下載。開機時物件庫先列出容器、image 較晚出現的情況不受影響，因為那時容器不需要重建。
- `tests/lifecycle.sh` 新增「容器存在、鎖定換版」情境，共 62 項；在 v0.2.0 的核心上這個情境會失敗。

## v0.2.0

- 選用容器。`app_enabled_<id>` 鉤子回傳非零時，該容器不下載、不建立、狀態頁不列、`status` 不等它，已在執行的會被停止（不刪除，重新開啟時沿用）。列在 `OPTIONAL_CONTAINERS` 的容器啟動失敗只寫 Warning 事件，App 仍回報 `running`，狀態頁標示「選用，未執行」。v0.1.2 沒有這兩項時，只能讓 `app_run_<id>` 直接 `return 0`，結果是 image 照樣下載，而且 `status` 回報 not running，QTS 會把整個 App 當成停止。
- `check-pins.sh` 不變：關閉的容器照樣要在 `images.lock` 裡鎖定，關閉只是不起，不是不存在。
- `_bg_start` 等待物件庫時改看第一個啟用的容器，第一個容器被關閉時不會空等 `CS_WAIT_TIMEOUT`。
- 安裝後 `chown -R 0:0` 整個安裝目錄。qbuild 會保留建置者的 uid（GitHub runner 是 1001，本機建置是自己的 uid），在 NAS 上這個 uid 可能對應到真實的一般使用者，他就能改寫 QTS 以 root 執行的服務腳本。v0.1.x 的套件在 NAS 上實測都有這個問題。
- `tests/lifecycle.sh` 新增選用容器情境（關閉、啟動失敗、重新開啟、再關閉），共 57 項。

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
