#!/bin/bash

set -o errexit -o pipefail -o noclobber -o nounset

DPKG_OPTS=(
    -o Dpkg::Options::="--force-confold"
)
VAGRANT_LIBVIRT_VERSION=${VAGRANT_LIBVIRT_VERSION:-"latest"}
VAGRANT_LIBVIRT_REPO=${VAGRANT_LIBVIRT_REPO:-"https://github.com/vagrant-libvirt/vagrant-libvirt.git"}

function version_compare() {
    [[ $1 == $2 ]] && return 0

    local IFS=.
    local v1=(${1})
    local v2=(${2})
    local i

    for (( i=0; i<${#v1[@]} || i<${#v2[@]}; i++ ))
    do
        if [[ ${v1[i]:-0} -gt ${v2[i]:-0} ]]
        then
            return 1
        elif [[ ${v1[i]:-0} -lt ${v2[i]:-0} ]]
        then
            return 2
        fi
    done

    return 0
}

function restart_libvirt() {
    service_name=${1:-libvirtd}
    # it appears there can be issues with libvirt being started before certain
    # packages that are required for create behaviour on first run. Restart to
    # ensure the daemon picks up the latest environment and can create a VM
    # on the first attempt. Otherwise will need to reboot
    sudo systemctl restart ${service_name}
}

function apt_get() {
    # sudo-rs, the default sudo from Ubuntu 25.10, doesn't support -E so
    # pass the environment needed for a noninteractive run explicitly.
    sudo env \
        DEBIAN_FRONTEND=noninteractive \
        DEBCONF_NONINTERACTIVE_SEEN=true \
        apt-get "$@"
}

function setup_apt() {
    if [[ -f /etc/apt/sources.list ]]
    then
        sudo sed -i "s/# deb-src/deb-src/" /etc/apt/sources.list
    fi
    # deb822 format, used by default from Ubuntu 24.04 and Debian 12
    for sources in /etc/apt/sources.list.d/*.sources
    do
        [[ -f ${sources} ]] || continue
        sudo sed -i "s/^Types: deb$/Types: deb deb-src/" ${sources}
    done
    apt_get update
    apt_get -y "${DPKG_OPTS[@]}" upgrade
    apt_get -y build-dep ruby-libvirt
}

function setup_arch() {
    sudo pacman -Syu --noconfirm --noprogressbar
    sudo pacman -S --needed --noprogressbar --noconfirm  \
        autoconf \
        automake \
        binutils \
        dnsmasq \
        git \
        gcc \
        libvirt \
        libxml2 \
        libxslt \
        make \
        nftables \
        openbsd-netcat \
        pkgconf \
        qemu-base \
        ruby \
        wget \
        ;
    sudo systemctl enable --now libvirtd
}

function setup_centos() {
    sudo dnf config-manager --set-enabled crb
    sudo dnf -y update
    sudo dnf -y install \
        @virtualization-host-environment \
        autoconf \
        automake \
        binutils \
        byacc \
        cmake \
        gcc \
        gcc-c++ \
        git \
        libguestfs-tools \
        libvirt \
        libvirt-devel \
        make \
        qemu-kvm \
        rpm-build \
        ruby-devel \
        wget \
        zlib-devel \
        ;
    restart_libvirt
}

function setup_debian() {
    setup_apt
    apt_get -y "${DPKG_OPTS[@]}" install \
        ebtables \
        git \
        libvirt-clients \
        libvirt-daemon \
        libvirt-daemon-system \
        qemu-system-x86 \
        qemu-utils \
        wget \
        ;
    restart_libvirt
}

function setup_fedora() {
    sudo dnf -y update
    sudo dnf -y install \
        @virtualization \
        autoconf \
        automake \
        binutils \
        byacc \
        cmake \
        gcc \
        gcc-c++ \
        git \
        libguestfs-tools \
        libvirt-devel \
        make \
        wget \
        zlib-devel \
        ;
    restart_libvirt
}

function setup_opensuse-leap() {
    sudo zypper refresh
    sudo zypper install --no-confirm \
        gcc \
        git \
        libguestfs \
        libvirt \
        libvirt-devel \
        make \
        qemu-kvm \
        polkit \
        ruby-devel \
        wget \
        ;
    restart_libvirt
}

function setup_ubuntu() {
    setup_apt
    apt_get -y "${DPKG_OPTS[@]}" install \
        git \
        libvirt-clients \
        libvirt-daemon \
        libvirt-daemon-system \
        qemu-system-x86 \
        qemu-utils \
        wget \
        ;
    restart_libvirt
}

function setup_distro() {
    local distro=${1}
    local version=${2:-}

    if [[ -n "${version}" ]] && [[ $(type -t setup_${distro}_${version} 2>/dev/null) == 'function' ]]
    then
        eval setup_${distro}_${version}
    else
        eval setup_${distro}
    fi
}


function download_vagrant() {
    local version=${1}
    local pkgext=${2}
    local pkgversion=${version}
    local arch="x86_64"
    # package name format for releases < 2.3.0
    local pkg="vagrant_${pkgversion}_${arch}.${pkgext}"

    local version_comparison=0
    version_compare ${version} "2.3.0" || version_comparison=$?

    # for version 2.3.0 (and newer?) the package version is different
    # and debs now use the amd64 arch.
    if [[ ${version_comparison} -le 1 ]]
    then
        # for rpm, deb, and zst the version number now appends '-1'
        pkgversion="${version}-1"
        if [[ "${pkgext}" == "rpm" ]]
        then
            pkg="vagrant-${pkgversion}.${arch}.${pkgext}"
        elif [[ "${pkgext}" == "pkg.tar.zst" ]]
        then
            pkg="vagrant-${pkgversion}-${arch}.${pkgext}"
        elif [[ "${pkgext}" == "deb" ]]
        then
            arch="amd64"
            pkg="vagrant_${pkgversion}_${arch}.${pkgext}"
        fi
    fi


    wget --no-verbose https://releases.hashicorp.com/vagrant/${version}/${pkg} -O /tmp/${pkg}.tmp
    mv /tmp/${pkg}.tmp /tmp/${pkg}

    DOWNLOADED_VAGRANT_PKG=${pkg}
}

function install_rake_arch() {
    sudo pacman -S --needed --noprogressbar --noconfirm  \
        ruby-bundler \
        ruby-rake
}

function install_rake_centos() {
    sudo yum -y install \
        rubygem-bundler \
        rubygem-rake
}

function install_rake_debian() {
    apt_get install -y \
        bundler \
        rake
}

function install_rake_fedora() {
    sudo dnf -y install \
        rubygem-rake
}

function install_rake_opensuse-leap() {
    sudo zypper install --no-confirm \
        'rubygem(bundler)' \
        'rubygem(rake)'
}

function install_rake_ubuntu() {
    install_rake_debian $@
}

function install_vagrant_arch() {
    local version=$1

    download_vagrant ${version} pkg.tar.zst
    sudo pacman -U --needed --noprogressbar --noconfirm /tmp/${DOWNLOADED_VAGRANT_PKG}
}

function install_vagrant_centos() {
    local version=$1

    download_vagrant ${version} rpm
    sudo -E rpm -Uh --force /tmp/${DOWNLOADED_VAGRANT_PKG}
}

function install_vagrant_debian() {
    local version=$1

    download_vagrant ${version} deb
    sudo dpkg -i /tmp/${DOWNLOADED_VAGRANT_PKG}
}

function install_vagrant_fedora() {
    install_vagrant_centos $@
}

function install_vagrant_opensuse-leap() {
    local version=$1

    download_vagrant ${version} rpm
    sudo zypper install --allow-unsigned-rpm --no-confirm /tmp/${DOWNLOADED_VAGRANT_PKG}
}

function install_vagrant_ubuntu() {
    install_vagrant_debian $@
}

function use_system_libs() {
    # Vagrant puts its embedded libs on LD_LIBRARY_PATH when building the
    # plugin's native extensions, so they're picked over the system ones
    # both when running tools and when linking against libvirt. Remove
    # those that conflict, so the system ones are used instead.
    local lib
    for lib in "$@"
    do
        sudo rm -f /opt/vagrant/embedded/lib/lib${lib}.so*
    done
}

function patch_vagrant_arch() {
    # /bin/sh links libreadline, and the embedded one can't resolve the
    # termcap symbols of the system's libtinfo. libvirt needs the symbol
    # versions of the system's libcurl.
    use_system_libs readline curl
}

function patch_vagrant_opensuse-leap() {
    # /bin/sh links libreadline, and the embedded one can't resolve the
    # termcap symbols of the system's libtinfo.
    use_system_libs readline
}

function install_vagrant() {
    local version=${1}
    local distro=${2}
    local distro_version=${3:-}

    echo "Installing vagrant version '${version}'"

    eval install_vagrant_${distro} ${version}

    if [[ -n "${distro_version}" ]] && [[ $(type -t patch_vagrant_${distro}_${distro_version} 2>/dev/null) == 'function' ]]
    then
        echo "running patch_vagrant_${distro}_${distro_version}"
        eval patch_vagrant_${distro}_${distro_version}
    elif [[ $(type -t patch_vagrant_${distro} 2>/dev/null) == 'function' ]]
    then
        echo "running patch_vagrant_${distro}"
        eval patch_vagrant_${distro}
    else
        echo "no patch functions configured for ${distro} ${distro_version}"
    fi
}

function install_vagrant_libvirt() {
    local distro=${1}

    echo "Testing vagrant-libvirt version: '${VAGRANT_LIBVIRT_VERSION}'"
    if [[ "${VAGRANT_LIBVIRT_VERSION:0:4}" == "git-" ]]
    then
        eval install_rake_${distro}
        if [[ ! -d "./vagrant-libvirt" ]]
        then
            echo "Cloning vagrant-libvirt from: '${VAGRANT_LIBVIRT_REPO}'"
            git clone ${VAGRANT_LIBVIRT_REPO} vagrant-libvirt
        fi
        pushd vagrant-libvirt
        git checkout ${VAGRANT_LIBVIRT_VERSION#git-}
        rm -rf ./pkg
        rake build
        vagrant plugin install ./pkg/vagrant-libvirt-*.gem
        popd
    elif [[ "${VAGRANT_LIBVIRT_VERSION}" == "latest" ]]
    then
        vagrant plugin install vagrant-libvirt
    else
        vagrant plugin install vagrant-libvirt --plugin-version ${VAGRANT_LIBVIRT_VERSION}
    fi
}


OPTIONS=o
LONGOPTS=vagrant-only,vagrant-version:

# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]
then
    echo "Invalid options provided"
    exit 2
fi

eval set -- "$PARSED"

VAGRANT_ONLY=0

while true; do
    case "$1" in
        -o|--vagrant-only)
            VAGRANT_ONLY=1
            shift
            ;;
        --vagrant-version)
            VAGRANT_VERSION=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

echo "Starting vagrant-libvirt installation script"

DISTRO=${DISTRO:-$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"' | tr '[A-Z]' '[a-z]')}
DISTRO_VERSION=${DISTRO_VERSION:-$(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"' | tr '[A-Z]' '[a-z]' | tr -d '.')}

[[ ${VAGRANT_ONLY} -eq 0 ]] && setup_distro ${DISTRO} ${DISTRO_VERSION}

if [[ -z ${VAGRANT_VERSION+x} ]]
then
    VAGRANT_VERSION="$(
        wget -qO - https://checkpoint-api.hashicorp.com/v1/check/vagrant 2>/dev/null | \
            tr ',' '\n' | grep current_version | cut -d: -f2 | tr -d '"'
        )"
fi

install_vagrant ${VAGRANT_VERSION} ${DISTRO} ${DISTRO_VERSION}

[[ ${VAGRANT_ONLY} -eq 0 ]] && install_vagrant_libvirt ${DISTRO}

echo "Finished vagrant-libvirt installation script"
