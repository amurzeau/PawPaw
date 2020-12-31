#!/bin/bash

set -e

cd $(dirname ${0})
PAWPAW_ROOT="${PWD}"

# ---------------------------------------------------------------------------------------------------------------------
# check target

target="${1}"

if [ -z "${target}" ]; then
    echo "usage: ${0} <target>"
    exit 1
fi

# ---------------------------------------------------------------------------------------------------------------------
# run bootstrap dependencies

./bootstrap-common.sh "${target}"
./bootstrap-plugins.sh "${target}"
./bootstrap-qt.sh "${target}"

# ---------------------------------------------------------------------------------------------------------------------
# source setup code

source setup/check_target.sh
source setup/env.sh
source setup/functions.sh
source setup/versions.sh

# ---------------------------------------------------------------------------------------------------------------------
# custom function as needed for pyqt packages

function build_conf_python() {
    local name="${1}"
    local version="${2}"
    local extraconfrules="${3}"

    local pkgdir="${PAWPAW_BUILDDIR}/${name}-${version}"

    _prebuild "${name}" "${pkgdir}"

    # remove flags not compatible with python
    export CFLAGS="$(echo ${CFLAGS} | sed -e 's/-fvisibility=hidden//')"
    export CFLAGS="$(echo ${CFLAGS} | sed -e 's/-ffast-math//')"
    #export CFLAGS="$(echo ${CFLAGS} | sed -e 's/-fdata-sections -ffunction-sections//')"
    #export LDFLAGS="$(echo ${LDFLAGS} | sed -e 's/-Wl,-dead_strip -Wl,-dead_strip_dylibs//')"
    #export LDFLAGS="$(echo ${LDFLAGS} | sed -e 's/-fdata-sections -ffunction-sections//')"

    if [ ! -f "${pkgdir}/.stamp_configured" ]; then
        pushd "${pkgdir}"
        ./configure ${extraconfrules}
        touch .stamp_configured
        popd
    fi

    if [ ! -f "${pkgdir}/.stamp_built" ]; then
        pushd "${pkgdir}"
        make ${MAKE_ARGS} ${EXTRA_MAKE_ARGS}
        touch .stamp_built
        popd
    fi

    if [ ! -f "${pkgdir}/.stamp_installed" ]; then
        pushd "${pkgdir}"
        make ${MAKE_ARGS} -j 1 install
        touch .stamp_installed
        popd
    fi

    _postbuild
}

function build_pyqt() {
    local name="${1}"
    local version="${2}"
    local extraconfrules="${3}"

    local pkgdir="${PAWPAW_BUILDDIR}/${name}-${version}"

    _prebuild "${name}" "${pkgdir}"

    # remove flags not compatible with python
    export CFLAGS="$(echo ${CFLAGS} | sed -e 's/-fvisibility=hidden//')"
    export CFLAGS="$(echo ${CFLAGS} | sed -e 's/-ffast-math//')"
    #export CFLAGS="$(echo ${CFLAGS} | sed -e 's/-fdata-sections -ffunction-sections//')"
    export CXXFLAGS="$(echo ${CXXFLAGS} | sed -e 's/-fvisibility=hidden//')"
    export CXXFLAGS="$(echo ${CXXFLAGS} | sed -e 's/-ffast-math//')"
    #export CXXFLAGS="$(echo ${CXXFLAGS} | sed -e 's/-fvisibility-inlines-hidden//')"
    #export CXXFLAGS="$(echo ${CXXFLAGS} | sed -e 's/-fdata-sections -ffunction-sections//')"
    #export LDFLAGS="$(echo ${LDFLAGS} | sed -e 's/-Wl,-dead_strip -Wl,-dead_strip_dylibs//')"
    #export LDFLAGS="$(echo ${LDFLAGS} | sed -e 's/-fdata-sections -ffunction-sections//')"

    if [ ! -f "${pkgdir}/.stamp_configured" ]; then
        pushd "${pkgdir}"
        python3 configure.py ${extraconfrules}
        # used in sip
        sed -i -e 's/CFLAGS *=/CFLAGS +=/' */Makefile
        sed -i -e 's/CXXFLAGS *=/CXXFLAGS +=/' */Makefile
        sed -i -e 's/LIBS *=/LIBS += $(LDFLAGS)/' */Makefile
        sed -i -e 's|$(DESTDIR)/usr|$(DESTDIR)$(PREFIX)|g' */Makefile
        touch .stamp_configured
        popd
    fi

    if [ ! -f "${pkgdir}/.stamp_built" ]; then
        pushd "${pkgdir}"
        make PREFIX="${PAWPAW_PREFIX}" PKG_CONFIG="${TARGET_PKG_CONFIG}" ${MAKE_ARGS}
        touch .stamp_built
        popd
    fi

    if [ ! -f "${pkgdir}/.stamp_installed" ]; then
        pushd "${pkgdir}"
        make PREFIX="${PAWPAW_PREFIX}" PKG_CONFIG="${TARGET_PKG_CONFIG}" ${MAKE_ARGS} -j 1 install
        touch .stamp_installed
        popd
    fi
}

# ---------------------------------------------------------------------------------------------------------------------
# file/magic (posix only)

if [ "${WIN32}" -eq 0 ]; then
    download file "${FILE_VERSION}" "ftp://ftp.astron.com/pub/file"
    build_autoconf file "${FILE_VERSION}"
fi

# ---------------------------------------------------------------------------------------------------------------------
# python

if [ "${MACOS_UNIVERSAL}" -eq 1 ]; then
    PYTHON_EXTRAFLAGS = "--enable-optimizations"
fi

download Python "${PYTHON_VERSION}" "https://www.python.org/ftp/python/${PYTHON_VERSION}" "tgz"
patch_file Python "${PYTHON_VERSION}" "Modules/Setup.dist" 's/#zlib zlibmodule.c/zlib zlibmodule.c/'
build_conf_python Python "${PYTHON_VERSION}" "--prefix=${PAWPAW_PREFIX} --enable-shared ${PYTHON_EXTRAFLAGS}"

# ---------------------------------------------------------------------------------------------------------------------
# sip

if [ "${SIP_VERSION}" = "4.19.19" ]; then
    SIP_DOWNLOAD_URL="https://files.kde.org/krita/build/dependencies"
    SIP_EXTRAFLAGS="--sip-module PyQt5.sip"
else
    SIP_DOWNLOAD_URL="http://sourceforge.net/projects/pyqt/files/sip/sip-${SIP_VERSION}"
fi

download sip "${SIP_VERSION}" "${SIP_DOWNLOAD_URL}"
build_pyqt sip "${SIP_VERSION}" "${SIP_EXTRAFLAGS}"

# ---------------------------------------------------------------------------------------------------------------------
# pyqt5

if [ "${PYQT5_VERSION}" = "5.13.1" ]; then
    PYQT5_DOWNLOAD_URL="https://files.kde.org/krita/build/dependencies"
else
    PYQT5_DOWNLOAD_URL="http://sourceforge.net/projects/pyqt/files/PyQt5/PyQt-${PYQT5_VERSION}"
fi

download PyQt5_gpl "${PYQT5_VERSION}" "${PYQT5_DOWNLOAD_URL}"
build_pyqt PyQt5_gpl "${PYQT5_VERSION}" "--concatenate --confirm-license -c"

# ---------------------------------------------------------------------------------------------------------------------
# pyliblo

download pyliblo "${PYLIBLO_VERSION}" "http://das.nasophon.de/download"
build_python pyliblo "${PYLIBLO_VERSION}"

# ---------------------------------------------------------------------------------------------------------------------
# setuptools_scm (optional)

if [ -n "${SETUPTOOLS_SCM_VERSION}" ]; then
    download setuptools_scm "${SETUPTOOLS_SCM_VERSION}" "https://files.pythonhosted.org/packages/ed/b6/979bfa7b81878b2b4475dde092aac517e7f25dd33661796ec35664907b31"
    build_python setuptools_scm "${SETUPTOOLS_SCM_VERSION}"
fi

# ---------------------------------------------------------------------------------------------------------------------
# toml (optional)

if [ -n "${TOML_VERSION}" ]; then
    download toml "${TOML_VERSION}" "https://files.pythonhosted.org/packages/be/ba/1f744cdc819428fc6b5084ec34d9b30660f6f9daaf70eead706e3203ec3c"
    build_python toml "${TOML_VERSION}"
fi

# ---------------------------------------------------------------------------------------------------------------------
# zipp (optional)

if [ -n "${ZIPP_VERSION}" ]; then
    download zipp "${ZIPP_VERSION}" "https://files.pythonhosted.org/packages/ce/b0/757db659e8b91cb3ea47d90350d7735817fe1df36086afc77c1c4610d559"
    build_python zipp "${ZIPP_VERSION}"
fi

# ---------------------------------------------------------------------------------------------------------------------
# importlib_metadata (optional)

if [ -n "${IMPORTLIB_METADATA_VERSION}" ]; then
    download importlib_metadata "${IMPORTLIB_METADATA_VERSION}" "https://files.pythonhosted.org/packages/3f/a8/16dc098b0addd1c20719c18a86e985be851b3ec1e103e703297169bb22cc"
    build_python importlib_metadata "${IMPORTLIB_METADATA_VERSION}"
fi

# ---------------------------------------------------------------------------------------------------------------------
# cxfreeze

download cx_Freeze "${CXFREEZE_VERSION}" "https://github.com/anthony-tuininga/cx_Freeze/archive" "" "nv"
if [ "${CXFREEZE_VERSION}" = "5.13.1" ]; then
    patch_file cx_Freeze "${CXFREEZE_VERSION}" "setup.py" 's/"python%s.%s"/"python%s.%sm"/'
    patch_file cx_Freeze "${CXFREEZE_VERSION}" "setup.py" 's/extra_postargs=extraArgs,/extra_postargs=extraArgs+os.getenv("LDFLAGS").split(),/'
    patch_file cx_Freeze "${CXFREEZE_VERSION}" "cx_Freeze/macdist.py" 's/, use_builtin_types=False//'
fi
build_python cx_Freeze "${CXFREEZE_VERSION}"

# ---------------------------------------------------------------------------------------------------------------------
