# NOTICE

[English](#english)

## 來源

本專案為原創，管理腳本抽自同一作者的 open-webui-ollama-qpkg。套件結構參考 QNAP 官方的 [qnap-dev/containerized-qpkg](https://github.com/qnap-dev/containerized-qpkg)。本專案的授權（Apache-2.0，見 [LICENSE](LICENSE)）僅涵蓋本 repo 內的檔案。

## 關係聲明

本專案為非官方的社群維護套件，與 QNAP Systems, Inc. 及下列上游專案均無隸屬、維護或背書關係。

<!-- upstream:start -->
## 上游軟體

本套件僅自動化部署官方未經修改的 [traefik/whoami](https://github.com/traefik/whoami) image，不重新散布該軟體。實際使用的版本記錄在 `shared/images.lock`。whoami 依其自身授權（Apache-2.0，[LICENSE](https://github.com/traefik/whoami/blob/master/LICENSE)）提供，使用本套件即表示接受該授權。

狀態頁使用官方未經修改的 [busybox](https://hub.docker.com/_/busybox) image（GPL-2.0），同樣不重新散布。

## 商標

Traefik 為 Traefik Labs 的商標。QNAP、QTS、QuTS hero 與 Container Station 為 QNAP Systems, Inc. 的商標。
<!-- upstream:end -->

---

## English

**Origin.** This project is original work; the management scripts are extracted from open-webui-ollama-qpkg by the same author, and the package layout follows QNAP's [qnap-dev/containerized-qpkg](https://github.com/qnap-dev/containerized-qpkg). This project's license (Apache-2.0, see [LICENSE](LICENSE)) covers only the files in this repository.

**Affiliation.** This is an unofficial, community-maintained package. It is not affiliated with, maintained or endorsed by QNAP Systems, Inc. or the upstream projects named here.

<!-- upstream-en:start -->
**Upstream software.** The package only automates the deployment of the official, unmodified [traefik/whoami](https://github.com/traefik/whoami) image and does not redistribute it. The exact version is recorded in `shared/images.lock`. whoami is provided under its own license (Apache-2.0); using this package means accepting it. The status page uses the official, unmodified [busybox](https://hub.docker.com/_/busybox) image (GPL-2.0), likewise not redistributed.

**Trademarks.** Traefik is a trademark of Traefik Labs. QNAP, QTS, QuTS hero and Container Station are trademarks of QNAP Systems, Inc.
<!-- upstream-en:end -->
