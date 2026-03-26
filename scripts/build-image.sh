#!/bin/bash

set -o nounset -o errexit -o errtrace -o pipefail

[ "${DEBUG:-}" = "1" ] && set -o xtrace

declare -r BUNDLE="${2}"
declare -r DISTRO="${1}"
declare -r PYTHON_VERSION="${3:-3.9}"
declare -r USERNAME="${USER_NAME:-percona}"
declare -ri USERUID=${USER_UID:-1000}

declare -a BUILD_FILES
declare -a ENV_INFO
declare -a PACKAGES_OS
declare -a PACKAGES_PIP
declare -a REQUIREMENTS=( /dev/null )

test -f "${BUNDLE}"

function setup {
    install -o "${USERNAME}" -m 0750 -d /app

    case "${DISTRO}" in
        # TODO: add support for UBI - ubi, ubi-minimal, ubi-init
        ## https://developers.redhat.com/products/rhel/ubi
        "centos:stream8"|"centos:stream9"|"centos:stream10"|"ubi8"|"ubi9"|"ubi10"|"oraclelinux:8"|"oraclelinux:9"|"oraclelinux:10") setup_redhat "${@}";;
        # TODO: remove el7 support completely, leaving as disabled now in case it is required
        #"centos:7") setup_redhat_legacy "${@}";;
        "ubuntu:26.04"|"ubuntu:resolute"|"ubuntu:24.04"|"ubuntu:noble"|"ubuntu:22.04"|"ubuntu:jammy"|\
        "debian:trixie"|"debian:13"|"debian:bookworm"|"debian:12"|"debian:bullseye"|"debian:11") setup_debian "${@}";;
        #"python:3.10-slim") ;;
        *) echo "Unsupported distro: ${DISTRO}"; exit 1
    esac
}

function setup_debian {
    local extra_packages
    local -ar extra_packages=( "${@}" )
    local -a packages

    for extra_package in "${extra_packages[@]}"; do
        if [ -f "${extra_package}" ]; then
            mapfile -t packages < "${extra_package}"
        fi
    done

    case "${DISTRO}" in
        *) packages+=( python3-minimal python3-venv )
    esac

    apt update -qqy
    apt install -qqy "${packages[@]}"
    apt clean -qqy
}

function setup_redhat {
    local extra_packages
    local -ar extra_packages=( "${@}" )
    local -a packages
    local -a repos

    for extra_package in "${extra_packages[@]}"; do
        if [ -f "${extra_package}" ]; then
            mapfile -t packages < "${extra_package}"
        fi
    done

    dnf makecache -y

    case "${DISTRO}" in
        "centos:stream8"|"ubi8"|"oraclelinux:8") packages+=( python38 python38-wheel python39 python39-wheel );;
        "ubi9") packages+=( python3 python-wheel-wheel );;
        "oraclelinux:9") packages+=( python3 python3-wheel-wheel ); repos=( "--enablerepo=ol9_codeready_builder" );;
        "centos:stream9") packages+=( python3 python-wheel-wheel ); repos=( "--enablerepo=crb" );;
        "ubi10") packages+=( python3 python-wheel-wheel );;
        "oraclelinux:10") packages+=( python3 python3-wheel-wheel ); repos=( "--enablerepo=ol10_codeready_builder" );;
        "centos:stream10") packages+=( python3 python-wheel-wheel ); repos=( "--enablerepo=crb" );;
    esac

    dnf install -y "${repos[@]}" "${packages[@]}"
    dnf clean all
}

function setup_redhat_legacy {
    local extra_packages
    local -ar extra_packages=( "${@}" )
    local -a packages

    for extra_package in "${extra_packages[@]}"; do
        if [ -f "${extra_package}" ]; then
            mapfile -t packages < "${extra_package}"
        fi
    done

    case "${DISTRO}" in
        *) packages+=( rh-python38 rh-python38-python-wheel )
    esac

    yum makecache -y
    yum install -y centos-release-scl
    yum install -y "${packages[@]}"
    yum clean all
    update-alternatives --install /usr/bin/python3.8 python3.8 /opt/rh/rh-python38/root/bin/python3.8 100
}

function extract_bundle {
    local parent_dir=
    local -a parent_dirs=
    mapfile -t parent_dirs < <(tar -tf "${BUNDLE}" | cut -f1 -d/ | sort -u)

    tar -C /opt --owner=root --group=root -xf "${BUNDLE}"
    for parent_dir in "${parent_dirs[@]}"; do
        chmod -R o=rX "/opt/${parent_dir}" || true

        [ -f "/opt/${parent_dir}/requirements.txt" ] && REQUIREMENTS+=( "/opt/${parent_dir}/requirements.txt" )
        [ -f "/opt/${parent_dir}/extra_packages_os.txt" ] && PACKAGES_OS+=( "/opt/${parent_dir}/extra_packages_os.txt" )
        [ -f "/opt/${parent_dir}/extra_packages_pip.txt" ] && PACKAGES_PIP+=( "/opt/${parent_dir}/extra_packages_pip.txt" )
        [ -f "/opt/${parent_dir}/.env" ] && ENV_INFO+=( "/opt/${parent_dir}/.env" )
        [ -f "/opt/${parent_dir}/setup.cfg" ] && BUILD_FILES+=( "/opt/${parent_dir}" )
    done
}

function build_pex {
    local pex_command=
    local pex_module=
    local pex_output=
    local requirements='/tmp/requirements.txt'

    local -a pex_extra_args=( '--' '--help' )

    for env in "${ENV_INFO[@]}"; do
        # shellcheck disable=SC1090
        source "${env}"
    done
    # shellcheck disable=SC1091
    source /app/venv/bin/activate

    test -n "${requirements}"
    test -n "${pex_command}" || test -n "${pex_module}"
    test -n "${pex_output}"

    cat "${REQUIREMENTS[@]}" <("/app/venv/bin/pip${PYTHON_VERSION}" freeze) | sed 's/ @ /@/g' | grep -Ev '^pkg_resources==' > "${requirements}"

    if [ "${pex_command}" != "" ]; then
        /app/venv/bin/pex -r "${requirements}" -c "${pex_command}" -o "/app/${pex_output}${PYTHON_VERSION}" "${pex_extra_args[@]}"
    else
        /app/venv/bin/pex -r "${requirements}" -m "${pex_module}" -o "/app/${pex_output}${PYTHON_VERSION}" "${pex_extra_args[@]}"
    fi
}

function prep {
    local build_dir=
    local requirement=
    local extra_packages
    local -ar extra_packages=( "${@}" )

    for extra_package in "${extra_packages[@]}"; do
        if [ -f "${extra_package}" ]; then
            REQUIREMENTS+=( "${extra_package}" )
        fi
    done

    "/usr/bin/python${PYTHON_VERSION}" -m venv --clear /app/venv
    "/app/venv/bin/pip${PYTHON_VERSION}" install --quiet --upgrade pip pex wheel build

    for requirement in "${REQUIREMENTS[@]}"; do
        "/app/venv/bin/pip${PYTHON_VERSION}" install --quiet -r "${requirement}"
    done

    for build_dir in "${BUILD_FILES[@]}"; do
        "/app/venv/bin/python${PYTHON_VERSION}" -m build "${build_dir}"
        "/app/venv/bin/pip${PYTHON_VERSION}" install "${build_dir}"/dist/*.whl
    done
}

id -un "${USERUID}" || {
    useradd -d /app \
        -s /sbin/nologin \
        -u "${USERUID}" \
        "${USERNAME}"
}

setup "${PACKAGES_OS[@]}"
extract_bundle

if [ "${PACKAGES_PIP[*]}" != "" ]; then
    prep "${PACKAGES_PIP[@]}"
else
    prep
fi
build_pex
