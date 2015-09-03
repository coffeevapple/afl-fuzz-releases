#!/bin/sh
#
# american fuzzy lop - high-performance binary-only instrumentation
# -----------------------------------------------------------------
#
# Written by Andrew Griffiths <agriffiths@google.com> and
#            Michal Zalewski <lcamtuf@google.com>
#
# Copyright 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# This script downloads, patches, and builds a version of QEMU modified
# to allow non-instrumented binaries to be run under afl-fuzz.
#
# The same principle can be used to run cross-CPU binaries by changing
# --target-list when calling ./configure.
#

QEMU_URL="http://wiki.qemu-project.org/download/qemu-2.2.0.tar.bz2"
QEMU_SHA384="69f4ac3094b0577b7181840c9c7b7a048df2bd03c0d851eef8174fd052a1ba786cff15a7dbd94410cbfcb53cb823a30c"

echo "============================================"
echo "AFL binary-only instrumentation build script"
echo "============================================"
echo

echo "[*] Performing basic sanity checks..."

if [ ! "`uname -s`" = "Linux" ]; then

  echo "[-] Error: QEMU instrumentation is supported only on Linux."
  exit 1

fi

if [ ! -f "patches/afl-qemu-cpu-inl.h" -o ! -f "../config.h" ]; then

  echo "[-] Error: key files not found - wrong working directory?"
  exit 1

fi

T=`which libtool 2>/dev/null`

if [ "$T" = "" ]; then

  echo "[-] Error: 'libtool' not found, please install first."
  exit 1

fi

T=`which wget 2>/dev/null`

if [ "$T" = "" ]; then

  echo "[-] Error: 'wget' not found, please install first."
  exit 1

fi

T=`which sha384sum 2>/dev/null`

if [ "$T" = "" ]; then

  echo "[-] Error: 'sha384sum' not found, please install first."
  exit 1

fi

if [ ! -d "/usr/include/glib-2.0/" -a ! -d "/usr/local/include/glib-2.0/" ]; then

  echo "[-] Error: devel version of 'glib2' not found, please install first."
  exit 1

fi

if echo "$CC" | grep -qF /afl-; then

  echo "[-] Error: do not use afl-gcc or afl-clang to compile this tool."
  exit 1

fi

echo "[+] All checks passed!"

ARCHIVE="`basename -- "$QEMU_URL"`"

CKSUM=`sha384sum -- "$ARCHIVE" 2>/dev/null | cut -d' ' -f1`

if [ ! "$CKSUM" = "$QEMU_SHA384" ]; then

  echo "[*] Downloading qemu 2.2.0 from the web..."
  rm -f "$ARCHIVE"
  wget -O "$ARCHIVE" -- "$QEMU_URL" || exit 1

  CKSUM=`sha384sum -- "$ARCHIVE" 2>/dev/null | cut -d' ' -f1`

fi

if [ "$CKSUM" = "$QEMU_SHA384" ]; then

  echo "[+] Cryptographic signature on $ARCHIVE checks out."

else

  echo "[-] Error: signature mismatch on $ARCHIVE (perhaps download error?)."
  exit 1

fi

echo "[*] Uncompressing archive (this will take a while)..."

rm -rf "qemu-2.2.0" || exit 1
tar xf "$ARCHIVE" || exit 1

echo "[+] Unpacking successful."

echo "[*] Applying patches..."

patch -p0 <patches/elfload.diff || exit 1
patch -p0 <patches/cpu-exec.diff || exit 1
patch -p0 <patches/translate-all.diff || exit 1

echo "[+] Patching done."

test "$CPU_TARGET" = "" && CPU_TARGET="`uname -i`"

echo "[*] Configuring QEMU for $CPU_TARGET..."

cd qemu-2.2.0 || exit 1

CFLAGS="-O3" ./configure --disable-system --enable-linux-user \
  --enable-guest-base --disable-gtk --disable-sdl --disable-vnc \
  --target-list="${CPU_TARGET}-linux-user" || exit 1

echo "[+] Configuration complete."

echo "[*] Attempting to build QEMU (fingers crossed!)..."

make || exit 1

echo "[+] Build process successful!"

echo "[*] Copying binary..."

cp -f "${CPU_TARGET}-linux-user/qemu-${CPU_TARGET}" "../../afl-qemu-trace" || exit 1

cd ..
ls -l ../afl-qemu-trace || exit 1

echo "[+] Successfully created '../afl-qemu-trace'."

echo "[*] Testing the build..."

cd ..

make >/dev/null || exit 1

gcc test-instr.c -o test-instr || exit 1

unset AFL_INST_RATIO

echo 0 | ./afl-showmap -m none -Q -q -o .test-instr0 ./test-instr || exit 1
echo 1 | ./afl-showmap -m none -Q -q -o .test-instr1 ./test-instr || exit 1

rm -f test-instr

cmp -s .test-instr0 .test-instr1
DR="$?"

rm -f .test-instr0 .test-instr1

if [ "$DR" = "0" ]; then

  echo "[-] Error: afl-qemu-trace instrumentation doesn't seem to work!"
  exit 1

fi

echo "[+] Instrumentation tests passed. "

echo "[+] All set, you can now use the -Q mode in afl-fuzz!"

exit 0
