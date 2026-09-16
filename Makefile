# Thin QPKG build, tests and release files.
#
#   make              build build/<QPKG_NAME>_<version>_x86_64.qpkg in Docker
#   make test         lint, pin check, lifecycle test, new-app test
#   make pin          re-resolve every tag in shared/images.lock
#   make release-files  copy images.lock and LICENSE into build/, write SHA256SUMS
#   make clean

BUILDER_IMAGE := qpkg-template-builder
SHELLCHECK    := koalaman/shellcheck-alpine:stable
SRC           := $(CURDIR)
SH_FILES      := $(wildcard shared/*.sh shared/lib/*.sh scripts/*.sh tests/*.sh) package_routines

.PHONY: all builder qpkg lint check-pins test test-lifecycle test-new-app pin release-files clean

all: qpkg

builder:
	docker build -t $(BUILDER_IMAGE) .

qpkg: builder
	docker run --rm -u "$$(id -u):$$(id -g)" -v "$(SRC)":/src -w /src $(BUILDER_IMAGE) \
		qbuild --build-arch x86_64
	@ls -l build/*.qpkg

lint:
	docker run --rm -v "$(SRC)":/mnt -w /mnt $(SHELLCHECK) \
		shellcheck -s sh -x -P SCRIPTDIR -e SC1091 $(SH_FILES) tests/stubs/*

check-pins:
	sh scripts/check-pins.sh

test-lifecycle:
	sh tests/lifecycle.sh

test-new-app:
	sh tests/new-app.sh

test: lint check-pins test-lifecycle test-new-app

pin:
	sh scripts/pin-images.sh

release-files:
	cp shared/images.lock LICENSE NOTICE.md build/
	cd build && sha256sum *.qpkg images.lock LICENSE NOTICE.md > SHA256SUMS && cat SHA256SUMS

clean:
	rm -rf build
