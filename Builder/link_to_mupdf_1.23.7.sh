#!/usr/bin/env bash
#. ~/.profile
set -euo pipefail

# get the location of this script, we will checkout mupdf into the same directory
BUILD_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $BUILD_DIR

VERSION_TAG="1.23.7"
MUPDF_FOLDER=mupdf-$VERSION_TAG
ARG="${1:-}"
ARG2="${2:-}"
MUPDF_ABIS="${MUPDF_ABIS:-armeabi-v7a arm64-v8a x86 x86_64}"

if [ "$ARG" == "fdroid" ]; then
  MUPDF_FOLDER=$MUPDF_FOLDER-fdroid
fi

if [ -d "$MUPDF_FOLDER" ] && [ ! -d "$MUPDF_FOLDER/.git" ]; then
  rm -rf "$MUPDF_FOLDER"
fi

if [ ! -d "$MUPDF_FOLDER/.git" ]; then
  git clone https://github.com/ArtifexSoftware/mupdf.git --branch "$VERSION_TAG" "$MUPDF_FOLDER"
fi

MUPDF_ROOT=$BUILD_DIR/$MUPDF_FOLDER


MUPDF_JAVA=$MUPDF_ROOT/platform/librera
mkdir -p $MUPDF_JAVA/jni

SRC=jni/~mupdf-$VERSION_TAG
DEST=$MUPDF_ROOT/source
LIBS=$BUILD_DIR/../app/src/main/jniLibs

echo "MUPDF :" $VERSION_TAG
echo "================== "

mkdir -p $SRC
mkdir -p $MUPDF_FOLDER

cd $MUPDF_FOLDER

echo "=================="
git submodule sync --recursive
git submodule update --init --recursive

if [ "$ARG" == "clean" ]; then
  git reset --hard &&  git clean -f -d
  rm -rf generated
  rm -rf build
  make clean
fi

if [ ! -f "Makelists" ] || [ ! -f "generated/resources/fonts/sil/CharisSIL.cff.c" ] || [ ! -f "generated/resources/fonts/noto/NotoSerif-Regular.otf.c" ]; then
  make generate
fi

test -f generated/resources/fonts/sil/CharisSIL.cff.c
test -f generated/resources/fonts/noto/NotoSerif-Regular.otf.c

if [ "${BUILD_MUPDF_RELEASE:-false}" == "true" ] && [ ! -d "build/release" ]; then
  make release
fi

cd ..

rm -rf  $MUPDF_JAVA/jni
cp -Rp jni $MUPDF_JAVA/jni
mv $MUPDF_JAVA/jni/Android-$VERSION_TAG.mk $MUPDF_JAVA/jni/Android.mk


rm -rf $LIBS
mkdir $LIBS

for ABI in $MUPDF_ABIS; do
  ln -s "$MUPDF_JAVA/libs/$ABI" "$LIBS/$ABI"
done

if [ "$ARG" == "copy" ]; then

cp -rpv $DEST/html/css-apply.c    $SRC/css-apply.c
cp -rpv $DEST/html/epub-doc.c     $SRC/epub-doc.c
cp -rpv $DEST/html/html-layout.c  $SRC/html-layout.c
cp -rpv $DEST/html/html-parse.c   $SRC/html-parse.c

cp -rpv $DEST/cbz/mucbz.c         $SRC/mucbz.c
cp -rpv $DEST/cbz/muimg.c         $SRC/muimg.c

cp -rpv $DEST/fitz/load-webp.c    $SRC/load-webp.c
cp -rpv $DEST/fitz/image.c        $SRC/image.c
cp -rpv $DEST/fitz/unzip.c        $SRC/unzip.c
cp -rpv $DEST/fitz/directory.c    $SRC/directory.c
cp -rpv $DEST/fitz/xml.c          $SRC/xml.c
cp -rpv $DEST/fitz/list-device.c  $SRC/list-device.c
cp -rpv $DEST/fitz/pdf-xref.c  $SRC/pdf-xref.c

cp -rpv $DEST/fitz/image-imp.h                              $SRC/image-imp.h
cp -rpv $MUPDF_ROOT/include/mupdf/fitz/compressed-buffer.h  $SRC/compressed-buffer.h
cp -rpv $MUPDF_ROOT/include/mupdf/fitz/context.h            $SRC/context.h

else

cp -rpv $SRC/css-apply.c         $DEST/html/css-apply.c
cp -rpv $SRC/epub-doc.c          $DEST/html/epub-doc.c
cp -rpv $SRC/html-layout.c       $DEST/html/html-layout.c
cp -rpv $SRC/html-parse.c        $DEST/html/html-parse.c

cp -rpv $SRC/mucbz.c             $DEST/cbz/mucbz.c
cp -rpv $SRC/muimg.c             $DEST/cbz/muimg.c

cp -rpv $SRC/load-webp.c         $DEST/fitz/load-webp.c
cp -rpv $SRC/image.c             $DEST/fitz/image.c
cp -rpv $SRC/unzip.c             $DEST/fitz/unzip.c
cp -rpv $SRC/directory.c         $DEST/fitz/directory.c
cp -rpv $SRC/xml.c               $DEST/fitz/xml.c
cp -rpv $SRC/list-device.c       $DEST/fitz/list-device.c
cp -rpv $SRC/pdf-xref.c          $DEST/pdf/pdf-xref.c

cp -rpv $SRC/image-imp.h         $DEST/fitz/image-imp.h
cp -rpv $SRC/compressed-buffer.h $MUPDF_ROOT/include/mupdf/fitz/compressed-buffer.h
cp -rpv $SRC/context.h $MUPDF_ROOT/include/mupdf/fitz/context.h

cp -rpv $SRC/j2k.c $MUPDF_ROOT/thirdparty/openjpeg/src/lib/openjp2/j2k.c
cp -rpv $SRC/pi.c $MUPDF_ROOT/thirdparty/openjpeg/src/lib/openjp2/pi.c

#/Users/ivanivanenko/git/LibreraReader/Builder/mupdf-1.23.7/thirdparty/openjpeg/src/lib/openjp2/pi.c
#/Users/ivanivanenko/git/LibreraReader/Builder/mupdf-1.23.7/thirdparty/openjpeg/src/lib/openjp2/j2k.c

cd $MUPDF_JAVA

NDK_VERSION="29.0.14206865"
FDRIOD_NDK_VERSION="21.4.7075529"

if [ "$(uname)" == "Darwin" ]; then
  FDRIOD_NDK_VERSION=$NDK_VERSION
fi

PATH1=/Users/ivanivanenko/Library/Android/sdk/ndk
PATH2=/home/dev/Android/Sdk/ndk
PATH3=$ANDROID_HOME/ndk

if [ ! -d "$PATH1/$NDK_VERSION" ]; then
    echo "-- NDK ERROR --"
    echo "$PATH1/$NDK_VERSION NDK NOT FOUND"
    echo "----"
fi

if [ "$ARG" == "clean_ndk" ]; then
  rm -rf $MUPDF_JAVA/obj

  if [ "$ARG2" == "fdroid" ]; then
   $PATH1/$FDRIOD_NDK_VERSION/ndk-build clean
   $PATH2/$FDRIOD_NDK_VERSION/ndk-build clean
  else
   $PATH1/$NDK_VERSION/ndk-build clean
   $PATH2/$NDK_VERSION/ndk-build clean
  fi

fi

build_mupdf_abis() {
  local NDK="$1"
  local PIDS=()

  for ABI in $MUPDF_ABIS; do
    "$NDK" NDK_APPLICATION_MK=jni/Application.mk APP_ABI="$ABI" APP_PLATFORM=android-24 &
    PIDS+=("$!")
  done

  for PID in "${PIDS[@]}"; do
    wait "$PID"
  done
}

if [ "$ARG" == "fdroid" ]; then
  NDK_FOUND=0
  for NDK in "${ANDROID_NDK_HOME:-}/ndk-build" "$PATH1/$FDRIOD_NDK_VERSION/ndk-build" "$PATH2/$FDRIOD_NDK_VERSION/ndk-build" "$PATH3/$FDRIOD_NDK_VERSION/ndk-build";
    do
	  if [ -f "$NDK" ]; then
	  NDK_FOUND=1
	  build_mupdf_abis "$NDK"
	  echo "=================="
	  echo "NDK:"  $NDK
	  echo "APP_PLATFORM=android-24"
      break
      fi
    done
  if [ "$NDK_FOUND" -eq 0 ]; then
    echo "No usable ndk-build found"
    exit 1
  fi
else
  NDK_FOUND=0
  for NDK in "${ANDROID_NDK_HOME:-}/ndk-build" "$PATH1/$NDK_VERSION/ndk-build" "$PATH2/$NDK_VERSION/ndk-build" "$PATH3/$NDK_VERSION/ndk-build";
  do
    if [ -f "$NDK" ]; then
    NDK_FOUND=1
    build_mupdf_abis "$NDK"
    echo "=================="
    echo "NDK:"  $NDK
    echo "APP_PLATFORM=android-24"
    break
    fi
  done
  if [ "$NDK_FOUND" -eq 0 ]; then
    echo "No usable ndk-build found"
    exit 1
  fi

fi

echo "=================="
echo "MUPDF:"$MUPDF_JAVA
echo "JNI:"$LIBS
echo "=================="
fi
