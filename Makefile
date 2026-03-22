# vim: ts=8:sw=8:ft=make:noai:noet
SHELL=/bin/bash

.PHONY: clean
.PHONY: pack
.PHONY: prep
.PHONY: test
.PHONY: venv

# Options
ARCH?=amd64
BUILD_BASE?=quay.io/centos/centos:stream9
BUILD_DIR?=./build
CONTAINERFILE?=Containerfile
ENTRYPOINT?=python3
NAME?=demo
OS?=linux
PACKAGE?=demo
PY?=3.9
VERSION?=$(shell git rev-parse HEAD)

# Constants
BUILD_BASE_TAG:=$(shell echo "${BUILD_BASE}" | sed 's^.*/^^g; s/:/-/g' | cut -f2 -d'/')

# Tests
NO_PACKAGE:=$(shell [ "${PACKAGE}" != "" ] && echo 0 || echo 1)
#

init: prep

all: build

all_versions:
	@printf "all_el9\nall_el8\nall_el7\nall_resolute\nall_noble\nall_jammy\nall_trixie\nall_bookworm\nall_bullseye\n"

all_el9: export BUILD_BASE=docker.io/redhat/ubi9
all_el9: export BUILD_BASE_TAG=el9
all_el9: export PY=3.9
all_el9: build

all_ol9: export BUILD_BASE=docker.io/oraclelinux:9
all_ol9: export BUILD_BASE_TAG=ol9
all_ol9: export PY=3.9
all_ol9: build

all_el8: export BUILD_BASE=docker.io/redhat/ubi8
all_el8: export BUILD_BASE_TAG=el8
all_el8: export PY=3.9
all_el8: build

all_ol8: export BUILD_BASE=docker.io/oraclelinux:8
all_ol8: export BUILD_BASE_TAG=ol8
all_ol8: export PY=3.9
all_ol8: build

all_el7: export BUILD_BASE=quay.io/centos/centos:7
all_el7: export BUILD_BASE_TAG=centos-7
all_el7: export PY=3.8
all_el7: build

all_resolute: export BUILD_BASE=ubuntu:resolute
all_resolute: export BUILD_BASE_TAG=ubuntu-resolute
all_resolute: export PY=3.14
all_resolute: build

all_noble: export BUILD_BASE=ubuntu:noble
all_noble: export BUILD_BASE_TAG=ubuntu-noble
all_noble: export PY=3.12
all_noble: build

all_jammy: export BUILD_BASE=ubuntu:jammy
all_jammy: export BUILD_BASE_TAG=ubuntu-jammy
all_jammy: export PY=3.10
all_jammy: build

all_trixie: export BUILD_BASE=debian:trixie
all_trixie: export BUILD_BASE_TAG=debian-trixie
all_trixie: export PY=3.13
all_trixie: build

all_bookworm: export BUILD_BASE=debian:bookworm
all_bookworm: export BUILD_BASE_TAG=debian-bookworm
all_bookworm: export PY=3.11
all_bookworm: build

all_bullseye: export BUILD_BASE=debian:bullseye
all_bullseye: export BUILD_BASE_TAG=debian-bullseye
all_bullseye: export PY=3.9
all_bullseye: build

build: prep package_image package_pex

show: export VNAME=${PACKAGE}/${BUILD_BASE_TAG}:${VERSION}
show: export VDIR=${BUILD_DIR}/${OS}/${ARCH}/${BUILD_BASE_TAG}
show:
	@echo "VNAME: ${VNAME}"
	@echo "VDIR: ${VDIR}"

package_image: export VDIR=${BUILD_DIR}/${OS}/${ARCH}/${BUILD_BASE_TAG}
package_image: export VNAME=${PACKAGE}/${BUILD_BASE_TAG}:${VERSION}
package_image: prep
package_image:
	@podman image pull "${BUILD_BASE}"
	@buildah build -f "${CONTAINERFILE}" \
	  --build-arg BASE="${BUILD_BASE}" \
	  --build-arg BUNDLE="bundle.tgz" \
	  --build-arg ENTRYPOINT="${ENTRYPOINT}" \
	  --build-arg PACKAGE="${PACKAGE}" \
	  --build-arg PYTHON_VERSION="${PY}" \
	  --build-arg USER_NAME=nobody \
	  --build-arg USER_UID=65534 \
	  --squash --no-cache --force-rm --compress --tag "${VNAME}" .

package_pex: export VDIR=${BUILD_DIR}/${OS}/${ARCH}/${BUILD_BASE_TAG}
package_pex: export VNAME=${PACKAGE}/${BUILD_BASE_TAG}:${VERSION}
package_pex:
	@podman unshare scripts/export-pex.sh

clean:
	@find "${BUILD_DIR}" -type f -print -delete
	@rm -vrf bundle.tgz venv "${BUILD_DIR}/tmp"

pack:
ifndef BUNDLE
	@echo Exporting bundle
	@git archive --output=bundle.tgz --format=tar.gz "${VERSION}" "${PACKAGE}"
else
	@echo Copying custom bundle "${BUNDLE}"
	@cp -a "${BUNDLE}" bundle.tgz
endif

prep: pack
prep:
ifeq ($(NO_PACKAGE), 1)
	@echo "PACKAGE is unset"
	@exit 1
else
	@install -d "${BUILD_DIR}/${OS}/${ARCH}/${BUILD_BASE_TAG}"
	@install -d "${BUILD_DIR}/tmp"
endif

venv:
	@python3 -m venv venv
	@venv/bin/pip install -U pip wheel
