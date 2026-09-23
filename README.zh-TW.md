# qpkg-template

[English](README.md)

QNAP Container Station 薄殼 QPKG 範本。套件本身不含任何 Docker image 或二進位檔，只放管理腳本、設定檔範本、image 鎖定檔與首次啟動的狀態頁；image 由 Container Station 在安裝後於背景下載。

骨架抽自 [open-webui-ollama-qpkg](https://github.com/ivanusto/open-webui-ollama-qpkg) v1.0.7，架構參考 [qnap-dev/containerized-qpkg](https://github.com/qnap-dev/containerized-qpkg)。內建的示範 App 是 [traefik/whoami](https://github.com/traefik/whoami)，一個幾 MB、無狀態的 HTTP 服務，用來證明骨架打包得出來、裝得起來。

本範本是鐵人賽系列「[地端維運三十天](https://github.com/ivanusto/onprem-ops-30days)」的共用骨架。

## 特色

- **不阻塞 QTS 開機**：Container Station 還沒就緒時，啟動改由 `setsid` 派生的背景工作等待，主程序立即返回。
- **確認 daemon 真的醒了**：`docker info` 與 `docker ps` 都要成功，且相隔 10 秒連續兩次，才算就緒。
- **冪等啟動與設定指紋**：`docker run` 的所有參數做雜湊，設定變了才重建容器，沒變就 `docker start`。
- **image digest 鎖定**：`images.lock` 以 `repository:tag@sha256:...` 記錄版本，啟動後比對本機 image 的 digest；`update` 只在有人改了鎖定值時才真的換版。
- **狀態頁**：下載期間以 busybox httpd 佔住網頁埠，顯示進度；App 的健康檢查路徑回應後，同一個網址自動換成 App 本身。
- **`diag` 子命令**：一次印出 docker、registry DNS、image 鎖定狀態、容器、網路、設定與最後的 log。
- **可驗證的 release**：CI 附上 `SHA256SUMS`、`images.lock` 與 GitHub 建置來源證明（build provenance attestation）。

## 兩層分界

| 層 | 檔案 | 內容 | 新 App 要改嗎 |
|---|---|---|---|
| 通用 | `shared/lib/qpkg-core.sh` | docker 探測與等待、背景派生、冪等啟動與指紋、digest 驗證、狀態頁、`diag`、子命令分派 | 不用 |
| 通用 | `package_routines` | 安裝前檢查 Container Station、保留既有設定、背景下載、移除時保留資料 | 只改名稱（`new-app.sh` 代勞） |
| 通用 | `shared/web/index.html` | 狀態機、輪詢、交接給 App | 不用 |
| 通用 | `Dockerfile`、`Makefile`、CI | QDK 打包、測試、release | 不用 |
| 案例 | `shared/<slug>.sh` | 設定區塊、容器清單、`docker run` 參數、狀態頁欄位 | 要 |
| 案例 | `shared/images.lock` | image 與 digest | 要 |
| 案例 | `shared/<slug>.conf.default` | 使用者可調的設定 | 要 |
| 案例 | `qpkg.cfg`、`icons/` | 套件描述、預設埠、圖示 | 要 |

## 從範本建立新套件

1. 在 GitHub 按「Use this template」建立 repo，clone 下來。
2. 改名：

   ```sh
   scripts/new-app.sh JellyfinQnap "Jellyfin" jellyfin
   ```

   第一個參數是 App Center 的內部名稱。App Center 以內部名稱判斷是否為同一個 App，若商店日後出現同名套件會被強制覆蓋更新，所以不要直接用上游名稱。

3. 鎖定 image：

   ```sh
   scripts/pin-images.sh APP_IMAGE=jellyfin/jellyfin:10.11.0
   ```

4. 編輯 `shared/<slug>.sh` 的設定區塊與鉤子函式（見下節）、`qpkg.cfg` 的 `QPKG_VER` 與 `QPKG_WEB_PORT`、替換 `icons/`。
5. 測試與打包：

   ```sh
   make test   # shellcheck、pin 檢查、生命週期測試、new-app 測試
   make        # 產出 build/<名稱>_<版本>_x86_64.qpkg
   ```

## 服務腳本的設定與鉤子

| 名稱 | 必要 | 說明 |
|---|---|---|
| `QPKG_NAME`、`DISPLAY_NAME`、`SCRIPT_NAME`、`CONF_NAME` | 是 | 名稱，`new-app.sh` 會填好 |
| `CONTAINERS` | 是 | 容器 id 清單，依啟動順序排列，停止時反序 |
| `OPTIONAL_CONTAINERS` | 否 | 啟動失敗時只記警告、不讓整個 App 失敗的容器 id，狀態頁會標示為選用 |
| `WEB_ID` | 是 | 發布 `WEB_PORT` 的容器 id，狀態頁會暫借這個埠 |
| `HEALTH_PATH` | 是 | App 就緒時回應 2xx 的路徑，狀態頁據此交接 |
| `DIAG_HOSTS` | 否 | `diag` 額外檢查 DNS 的主機 |
| `app_defaults` | 是 | 填入未設定的預設值，至少要有 `<ID>_CONTAINER_NAME` 與 `WEB_PORT` |
| `app_run_<id>` | 是 | 以 `"$DOCKER" run -d` 建立容器 |
| `app_fingerprint_<id>` | 是 | 印出所有出現在 `docker run` 上的值；漏列的設定改了不會生效 |
| `app_enabled_<id>` | 否 | 回傳非零表示關閉這個容器：不下載、不建立、狀態頁不列，已在執行的會被停止。它的 image 仍須鎖定 |
| `app_needs_recreate_<id>` | 否 | 容器停止時回傳 0 表示要重建，例如 GPU 晚註冊的自我修復 |
| `app_run_fallback_<id>` | 否 | `app_run_<id>` 失敗時的替代方案，例如退回不帶 `--gpus` |
| `app_status_fields` | 否 | 狀態頁額外欄位，每行 `英文標籤\|中文標籤\|值` |
| `app_diag` | 否 | `diag` 額外輸出 |

每個容器 id 對應的變數以大寫 id 為前綴：`<ID>_IMAGE`（來自 `images.lock`，可由設定檔覆寫）、`<ID>_CONTAINER_NAME`、選用的 `<ID>_DATA_PATH`（核心會在建立容器前 `mkdir -p`）。產生一次就要保存的密鑰，在 `app_defaults` 裡呼叫 `ensure_secret <變數名>`。

## 子命令

以管理員身分在 NAS 上執行（沒有 root 時容器仍會動，但 QTS 事件記錄與 App Center 連結的埠寫不進去）：

```sh
sudo /etc/init.d/myapp.sh status
sudo /etc/init.d/myapp.sh restart          # 套用設定變更，只重建有變動的容器
sudo /etc/init.d/myapp.sh update --check   # 上游 tag 是否已換版，不動容器
sudo /etc/init.d/myapp.sh update           # 套用變更後的鎖定值
sudo /etc/init.d/myapp.sh diag
sudo /etc/init.d/myapp.sh remove           # 移除容器與網路，資料保留
```

`status.json` 的狀態值：`waiting-for-container-station`、`downloading-image`、`pull-failed`、`starting`、`running`、`stopped`、`error`、`no-container-engine`。

## 版本鎖定與升級

`shared/images.lock` 隨套件出貨，每行一個 `KEY=repository:tag@sha256:digest`。tag 給人看，digest 才是實際執行的版本。digest 是 manifest list 的 digest，同一個鎖定值在 x86_64 與 ARM 機型都適用。

升級流程：

1. `sudo /etc/init.d/<slug>.sh update --check` 或開發機上 `scripts/pin-images.sh` 查看上游是否換版。
2. 在 repo 用 `scripts/pin-images.sh APP_IMAGE=<repository>:<新 tag>` 更新鎖定值，發新版 QPKG；或在 NAS 的設定檔覆寫 `APP_IMAGE`。
3. `update` 或 `restart`，只有 image 或設定有變的容器會重建。

`start` 或 `restart` 遇到新的鎖定值、而 image 還不在本機時（App Center 裝完新版後通常就是這樣），既有容器繼續以舊版服務，image 在背景下載，完整下載後才替換，這時不使用狀態頁。下載失敗時舊版照常運作，狀態維持 `running`，事件記錄寫警告。上游剛發版時，映像站的 CDN 可能連續數小時只有平常速度的零頭，升級絕不能讓 App 停著等下載。

設定檔寫浮動 tag（沒有 `@sha256`）時照樣可以執行，但事件記錄會警告，狀態頁與 `diag` 會標示為未鎖定。

每個容器的鎖定狀態有五種：`pinned-ok`（本機 image 與鎖定值相符）、`pinned-mismatch`（不符，記錄 Error）、`unpinned`（浮動 tag，記錄 Warning）、`unverifiable`（以 `docker load` 匯入，沒有 registry digest 可比對，記錄 Warning）、`missing`（尚未下載）。

## 驗證 release

```sh
sha256sum -c SHA256SUMS
gh attestation verify MyApp_0.2.2_x86_64.qpkg --repo ivanusto/qpkg-template --source-ref refs/tags/v0.2.2
```

`images.lock` 同時附在 release，不必解開 `.qpkg` 就能知道裡面鎖的是哪一個 image。

`--source-ref` 不可省略。attestation 綁的是檔案內容，內容相同的檔案（例如沒有變動的 `images.lock`）在不同版本各有一份聲明，不加限制時任何一份都能通過驗證。`gh attestation` 需要 GitHub CLI 2.49.0 以上。

## CI 的供應鏈鎖定

建置工具與 App 的 image 適用同一個原則：不引用會被別人移動的名稱。

| 引用 | 鎖定方式 | 更新方式 |
|---|---|---|
| GitHub Actions | 完整 commit SHA，註解保留版本號 | Dependabot 每週提 PR |
| QDK | `QDK_REF`，workflow 與 Dockerfile 必須相同 | 手動改兩處 |
| builder 基底 image | `ubuntu:22.04@sha256:...` | Dependabot 每週提 PR |
| shellcheck image | Makefile 的 `SHELLCHECK` 帶 digest | 手動 |

`scripts/check-ci-pins.sh`（包含在 `make check-pins`）檢查以上四項，任一項退回浮動參考就讓 CI 失敗。打 tag 時 CI 另外檢查 tag 與 `qpkg.cfg` 的 `QPKG_VER` 一致，不一致就不發 release：先改 `qpkg.cfg` 與 CHANGELOG、commit，再打 tag。

## 安裝到 NAS

1. App Center 右上角「手動安裝」，選擇 `.qpkg`。
2. 套件未經 QNAP 簽章，若被拒絕，到 App Center 設定的一般頁籤允許安裝未簽署的應用程式。
3. 安裝完成後點圖示，下載期間會看到狀態頁，完成後自動換成 App。

## 注意事項

- QDK 的安裝腳本會編譯 `qpkg_encrypt`，缺少 gcc 會產出 App Center 拒收的 `.qpkg`，Dockerfile 已包含。
- 腳本在 QTS 的 busybox sh 上執行，必須維持 LF 換行，`.gitattributes` 已設定。
- 目前只打包 x86_64。套件內容與架構無關，需要 ARM 版時在 `qpkg.cfg` 加上 `QDK_DATA_DIR_ARM_64` 並以 `qbuild --build-arch arm_64` 打包。
- 薄殼需要 NAS 能連到 registry。隔離網段建議改用私有 registry，digest 驗證照常運作。若改用 `docker save` / `docker load` 匯入，必須以 **tag** 匯出（`docker save repository:tag`，以 digest 匯出的 image 載入後沒有任何名稱）；匯入的 image 沒有 registry digest，套件會以 tag 啟動並標示為 `unverifiable`，鎖定值無法驗證。

## 授權

Apache-2.0，見 [LICENSE](LICENSE)。
