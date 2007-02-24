# This file declares functions to install the uClibc C library
# Copyright 2007 Yann E. MORIN
# Licensed under the GPL v2. See COPYING in the root of this package


# Check that uClibc has been previously configured
do_libc_check_config() {
    CT_DoStep INFO "Checking C library configuration"

    CT_TestOrAbort "You did not provide a uClibc config file!" -n "${CT_LIBC_UCLIBC_CONFIG_FILE}" -a -f "${CT_LIBC_UCLIBC_CONFIG_FILE}"

    cp "${CT_LIBC_UCLIBC_CONFIG_FILE}" "${CT_BUILD_DIR}/uClibc.config"

    if egrep '^KERNEL_SOURCE=' "${CT_LIBC_UCLIBC_CONFIG_FILE}" >/dev/null 2>&1; then
        CT_DoLog WARN "Your uClibc version refers to the kernel _sources_, which is bad."
        CT_DoLog WARN "I can't guarantee that our little hack will work. Please try to upgrade."
    fi

    CT_DoLog EXTRA "Munging uClibc configuration"
    mungeuClibcConfig "${CT_BUILD_DIR}/uClibc.config"

    CT_EndStep
}

# This functions installs uClibc's headers
do_libc_headers() {
    # Only need to install bootstrap uClibc headers for gcc-3.0 and above?  Or maybe just gcc-3.3 and above?
    # See also http://gcc.gnu.org/PR8180, which complains about the need for this step.
    grep -q 'gcc-[34]' "${CT_SRC_DIR}/${CT_CC_CORE_FILE}/ChangeLog" || return 0

    CT_DoStep INFO "Installing C library headers"

    mkdir -p "${CT_BUILD_DIR}/build-libc-headers"
    cd "${CT_BUILD_DIR}/build-libc-headers"

    # Simply copy files until uClibc has the ablity to build out-of-tree
    CT_DoLog EXTRA "Copying sources to build dir"
    { cd "${CT_SRC_DIR}/${CT_LIBC_FILE}"; tar cf - .; } |tar xf -

    # Retrieve the config file
    cp "${CT_BUILD_DIR}/uClibc.config" .config

    # uClibc uses the CROSS environment variable as a prefix to the
    # compiler tools to use.  Setting it to the empty string forces
    # use of the native build host tools, which we need at this
    # stage, as we don't have target tools yet.
    CT_DoLog EXTRA "Applying configuration"
    CT_DoYes "" |make CROSS= PREFIX="${CT_SYSROOT_DIR}/" oldconfig 2>&1 |CT_DoLog DEBUG

    CT_DoLog EXTRA "Building headers"
    make ${PARALLELMFLAGS} CROSS= PREFIX="${CT_SYSROOT_DIR}/" headers 2>&1 |CT_DoLog DEBUG

    CT_DoLog EXTRA "Installing headers"
    make CROSS= PREFIX="${CT_SYSROOT_DIR}/" install_dev 2>&1 |CT_DoLog DEBUG

    CT_EndStep
}

# This function build and install the full uClibc
do_libc() {
    CT_DoStep INFO "Installing C library"

    mkdir -p "${CT_BUILD_DIR}/build-libc"
    cd "${CT_BUILD_DIR}/build-libc"

    # Simply copy files until uClibc has the ablity to build out-of-tree
    CT_DoLog EXTRA "Copying sources to build dir"
    { cd "${CT_SRC_DIR}/${CT_LIBC_FILE}"; tar cf - .; } |tar xf -

    # Retrieve the config file
    cp "${CT_BUILD_DIR}/uClibc.config" .config

    # uClibc uses the CROSS environment variable as a prefix to the compiler
    # tools to use.  The newly built tools should be in our path, so we need
    # only give the correct name for them.
    # Note about CFLAGS: In uClibc, CFLAGS are generated by Rules.mak,
    # depending  on the configuration of the library. That is, they are tailored
    # to best fit the target. So it is useless and seems to be a bad thing to
    # use LIBC_EXTRA_CFLAGS here.
    CT_DoLog EXTRA "Applying configuration"
    CT_DoYes "" |make ${PARALLELMFLAGS}             \
                      CROSS=${CT_TARGET}-           \
                      PREFIX="${CT_SYSROOT_DIR}/"   \
                      oldconfig                     2>&1 |CT_DoLog DEBUG

    # We do _not_ want to strip anything for now, in case we specifically
    # asked for a debug toolchain, thus the STRIPTOOL= assignment
    CT_DoLog EXTRA "Building C library"
    make ${PARALLELMFLAGS}              \
         CROSS=${CT_TARGET}-            \
         PREFIX="${CT_SYSROOT_DIR}/"    \
         STRIPTOOL=true                 \
         all                            2>&1 |CT_DoLog DEBUG

    # YEM-FIXME: we want to install libraries in $SYSROOT/lib, but we don't want
    # to install headers in $SYSROOT/include, thus making only install_runtime.
    # Plus, the headers were previously installed earlier with install_dev, so
    # all should be well. Unfortunately, the install_dev target does not install
    # crti.o and consorts... :-( So reverting to target 'install'.
    # Note: PARALLELMFLAGS is not usefull for installation.
    # We do _not_ want to strip anything for now, in case we specifically
    # asked for a debug toolchain, thus the STRIPTOOL= assignment
    CT_DoLog EXTRA "Installing C library"
    make CROSS=${CT_TARGET}-            \
         PREFIX="${CT_SYSROOT_DIR}/"    \
         STRIPTOOL=true                 \
         install                        2>&1 |CT_DoLog DEBUG

    CT_EndStep
}

# This function is used to install those components needing the final C compiler
do_libc_finish() {
    CT_DoStep INFO "Finishing C library"
    # uClibc has nothing to finish
    CT_DoLog EXTRA "uClibc has nothing to finish"
    CT_EndStep
}

# Initialises the .config file to sensible values
mungeuClibcConfig() {
    config_file="$1"
    munge_file="${CT_BUILD_DIR}/munge-uClibc-config.sed"

    cat > "${munge_file}" <<-ENDSED
s/^(TARGET_.*)=y$/# \\1 is not set/
s/^# TARGET_${CT_KERNEL_ARCH} is not set/TARGET_${CT_KERNEL_ARCH}=y/
s/^TARGET_ARCH=".*"/TARGET_ARCH="${CT_KERNEL_ARCH}"/
ENDSED

    case "${CT_ARCH_BE},${CT_ARCH_LE}" in
        y,) cat >> "${munge_file}" <<-ENDSED
s/.*(ARCH_BIG_ENDIAN).*/\\1=y/
s/.*(ARCH_LITTLE_ENDIAN).*/# \\1 is not set/
ENDSED
        ;;
        ,y) cat >> "${munge_file}" <<-ENDSED
s/.*(ARCH_BIG_ENDIAN).*/# \\1 is not set/
s/.*(ARCH_LITTLE_ENDIAN).*/\\1=y/
ENDSED
        ;;
    esac

    case "${CT_ARCH_FLOAT_HW},${CT_ARCH_FLOAT_SW}" in
        y,) cat >> "${munge_file}" <<-ENDSED
s/.*(HAS_FPU).*/\\1=y/
ENDSED
            ;;
        ,y) cat >> "${munge_file}" <<-ENDSED
s/.*(HAS_FPU).*/\\# \\1 is not set/
ENDSED
            ;;
    esac

    # Change paths to work with crosstool
    # From http://www.uclibc.org/cgi-bin/viewcvs.cgi?rev=16846&view=rev
    #  " we just want the kernel headers, not the whole kernel source ...
    #  " so people may need to update their paths slightly
    quoted_kernel_source=`echo "${CT_HEADERS_DIR}" | sed -r -e 's,/include/?$,,; s,/,\\\\/,g;'`
    quoted_headers_dir=`echo ${CT_HEADERS_DIR} | sed -r -e 's,/,\\\\/,g;'`
    # CROSS_COMPILER_PREFIX is left as is, as the CROSS parameter is forced on the command line
    # DEVEL_PREFIX is left as '/usr/' because it is post-pended to $PREFIX, wich is the correct value of ${PREFIX}/${TARGET}
    # Some (old) versions of uClibc use KERNEL_SOURCE (which is _wrong_), and
    # newer versions use KERNEL_HEADERS (which is right). See:
    cat >> "${munge_file}" <<-ENDSED
s/^DEVEL_PREFIX=".*"/DEVEL_PREFIX="\\/usr\\/"/
s/^RUNTIME_PREFIX=".*"/RUNTIME_PREFIX="\\/"/
s/^SHARED_LIB_LOADER_PREFIX=.*/SHARED_LIB_LOADER_PREFIX="\\/lib\\/"/
s/^KERNEL_SOURCE=".*"/KERNEL_SOURCE="${quoted_kernel_source}"/
s/^KERNEL_HEADERS=".*"/KERNEL_HEADERS="${quoted_headers_dir}"/
s/^UCLIBC_DOWNLOAD_PREGENERATED_LOCALE=y/\\# UCLIBC_DOWNLOAD_PREGENERATED_LOCALE is not set/
ENDSED

    # Hack our -pipe into WARNINGS, which will be internally incorporated to
    # CFLAGS. This a dirty hack, but yet needed
    if [ "${CT_USE_PIPES}" = "y" ]; then
        cat >> "${munge_file}" <<-ENDSED
s/^(WARNINGS=".*)"$/\\1 -pipe"/
ENDSED
    fi

    # Force on options needed for C++ if we'll be making a C++ compiler.
    # Note that the two PREGEN_LOCALE and the XLOCALE lines may be missing
    # entirely if LOCALE is not set.  If LOCALE was already set, we'll
    # assume the user has already made all the appropriate generation
    # arrangements.  Note that having the uClibc Makefile download the
    # pregenerated locales is not compatible with crosstool; besides,
    # crosstool downloads them as part of getandpatch.sh.
    if [ "${CT_CC_LANG_CXX}" = "y" ]; then
        cat >> "${munge_file}" <<-ENDSED
s/^# DO_C99_MATH is not set/DO_C99_MATH=y/
s/^# UCLIBC_CTOR_DTOR is not set/UCLIBC_CTOR_DTOR=y/
# Add these three lines when doing C++?
#s/^# UCLIBC_HAS_WCHAR is not set/UCLIBC_HAS_WCHAR=y/
#s/^# UCLIBC_HAS_LOCALE is not set/UCLIBC_HAS_LOCALE=y\\nUCLIBC_PREGENERATED_LOCALE_DATA=y\\n\\# UCLIBC_DOWNLOAD_PREGENERATED_LOCALE_DATA is not set\\n\\# UCLIBC_HAS_XLOCALE is not set/
#s/^# UCLIBC_HAS_GNU_GETOPT is not set/UCLIBC_HAS_GNU_GETOPT=y/
ENDSED
    fi

    # Force on debug options if asked for
    case "${CT_LIBC_UCLIBC_DEBUG_LEVEL}" in
      0)
        cat >>"${munge_file}" <<-ENDSED
s/^PTHREADS_DEBUG_SUPPORT=y/# PTHREADS_DEBUG_SUPPORT is not set/
s/^DODEBUG=y/# DODEBUG is not set/
s/^DODEBUG_PT=y/# DODEBUG_PT is not set/
s/^DOASSERTS=y/# DOASSERTS is not set/
s/^SUPPORT_LD_DEBUG=y/# SUPPORT_LD_DEBUG is not set/
s/^SUPPORT_LD_DEBUG_EARLY=y/# SUPPORT_LD_DEBUG_EARLY is not set/
ENDSED
        ;;
      1)
        cat >>"${munge_file}" <<-ENDSED
s/^# PTHREADS_DEBUG_SUPPORT is not set.*/PTHREADS_DEBUG_SUPPORT=y/
s/^# DODEBUG is not set.*/DODEBUG=y/
s/^DODEBUG_PT=y/# DODEBUG_PT is not set/
s/^DOASSERTS=y/# DOASSERTS is not set/
s/^SUPPORT_LD_DEBUG=y/# SUPPORT_LD_DEBUG is not set/
s/^SUPPORT_LD_DEBUG_EARLY=y/# SUPPORT_LD_DEBUG_EARLY is not set/
ENDSED
        ;;
      2)
        cat >>"${munge_file}" <<-ENDSED
s/^# PTHREADS_DEBUG_SUPPORT is not set.*/PTHREADS_DEBUG_SUPPORT=y/
s/^# DODEBUG is not set.*/DODEBUG=y/
s/^# DODEBUG_PT is not set.*/DODEBUG_PT=y/
s/^# DOASSERTS is not set.*/DOASSERTS=y/
s/^# SUPPORT_LD_DEBUG is not set.*/SUPPORT_LD_DEBUG=y/
s/^# SUPPORT_LD_DEBUG_EARLY is not set.*/SUPPORT_LD_DEBUG_EARLY=y/
ENDSED
        ;;
    esac
    sed -r -i -f "${munge_file}" "${config_file}"
    rm -f "${munge_file}"
}
