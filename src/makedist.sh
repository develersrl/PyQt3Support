#!/bin/bash
set -e # exit on error
set -u # stop on undeclared variable

VER=r5-pre
SDKVER=0.7-pre
PYQT4VER=4.9.1
PYQT3VER=3.18.1

DOWNLOAD=downloads
RELEASE=release

license=${1:-unset}

DIFF_OPTIONS="--unified --recursive --new-file --ignore-all-space"
MERGE_OPTIONS="--no-backup-if-mismatch --merge --ignore-whitespace --remove-empty-files"

if [ "$license" = "gpl" ]; then
  DIST=gpl
  REMOTEDIR=http://www.riverbankcomputing.co.uk/static/Downloads
  PYQT4DIR=PyQt-x11-${DIST}-${PYQT4VER}
  PYQT3DIR=PyQt-x11-${DIST}-${PYQT3VER}
elif [ "$license" = "commercial" ]; then
  DIST=commercial
  REMOTEDIR=http://download.yourself.it/
  PYQT4DIR=PyQt-win-${DIST}-${PYQT4VER}
  PYQT3DIR=PyQt-${DIST}-${PYQT3VER}
else
  echo "Usage:"
  echo "    $0 [gpl|commercial]"
  exit 1
fi

pushd $(dirname $0)/../

[ ! -d ${DOWNLOAD} ] && mkdir $DOWNLOAD
pushd $DOWNLOAD

echo "=========================================================="
echo "Preparing the distribution packages"
echo "=========================================================="

if [ $DIST = "gpl" ]; then
	echo "----------------------------------------------------------"
	echo "Downloading PyQt4, PyQt3 and sip sources..."
	echo "----------------------------------------------------------"

	wget -c ${REMOTEDIR}/PyQt4/${PYQT4DIR}.tar.gz
	[ ! -d ${PYQT4DIR} ] && tar zxf ${PYQT4DIR}.tar.gz

	wget -c ${REMOTEDIR}/PyQt3/${PYQT3DIR}.tar.gz
	[ ! -d ${PYQT3DIR} ] && tar zxf ${PYQT3DIR}.tar.gz
fi;

popd

[ ! -d ${RELEASE} ] && mkdir $RELEASE

echo "----------------------------------------------------------"
echo "Building the full package..."
echo "----------------------------------------------------------"
FDESTDIR=$RELEASE/PyQt3Support-${VER}-PyQt${PYQT4VER}-${DIST}

rm -rf $FDESTDIR

echo "Merging PyQt3Support methods in PyQt4 sources..."
src/q3sipconvert.py $DOWNLOAD/${PYQT3DIR} $DOWNLOAD/${PYQT4DIR}

echo "Copying PyQt3Support sources in $FDESTDIR"
mv PyQt3Support $FDESTDIR

cp README.TXT $FDESTDIR/PYQT3SUPPORT.TXT

function merge_diffs {
  orig=$1
  new=$2
  diff=$3
  dest=$4
  extra=${5:-}
  echo merge_diffs $orig $new $diff $dest $extra
  patch_opts="$MERGE_OPTIONS $extra"
  local merge=$(patch $patch_opts $new < $diff 1>&2)
  # diff exits with 1 if file are different
  local different=$(diff $DIFF_OPTIONS $orig $new | filterdiff --remove-timestamps --strip=3 > $dest; echo $?)
  if [ "$different" != "0" ]; then
    # grep exits with 0 if no match is found
    local conflicts=$(grep --silent "<<<<<<" $dest; echo $?)
    if [ "$conflicts" == "0" ]; then
      echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
      echo "ERROR: Conflicts in $dest!"
      echo "Fix conflicts in $new and update the patch with:"
      echo "  diff $DIFF_OPTIONS $orig $new | filterdiff --remove-timestamps > $diff"
      echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
      exit 1
    else
      echo "Diff file $dest changed, update patch $diff with:"
      echo "  mv $dest $diff"
    fi
  fi
}

echo "----------------------------------------------------------"
echo "Patching configure.py..."
echo "----------------------------------------------------------"
merge_diffs $DOWNLOAD/${PYQT4DIR}/configure.py $FDESTDIR/configure.py src/configure.diff src/configure.diff.${PYQT4VER}

echo "----------------------------------------------------------"
echo "Patching pyuic..."
echo "----------------------------------------------------------"
merge_diffs $DOWNLOAD/${PYQT4DIR}/pyuic $FDESTDIR/pyuic src/pyuic.diff src/pyuic.diff.${PYQT4VER} --directory

echo "----------------------------------------------------------"
echo "Building ${FDESTDIR}.tar.gz package..."
echo "----------------------------------------------------------"
rm -rf ${FDESTDIR}.tar.gz
tar -cf ${FDESTDIR}.tar $FDESTDIR
gzip ${FDESTDIR}.tar


echo "----------------------------------------------------------"
echo "Building the addon package patch..."
echo "----------------------------------------------------------"
PDESTNAME=${FDESTDIR}.patch

cp $FDESTDIR/PYQT3SUPPORT.TXT $PDESTNAME
cat src/configure.diff >> $PDESTNAME
cat src/pyuic.diff >> $PDESTNAME
diff $DIFF_OPTIONS $DOWNLOAD/${PYQT4DIR}/sip $FDESTDIR/sip | filterdiff --remove-timestamps --strip=3 >> $PDESTNAME

echo "----------------------------------------------------------"
echo "Building the source package..."
echo "----------------------------------------------------------"
SDK=PyQt3Support_sdk_${SDKVER}

rm -rf /tmp/${SDK}
hg clone ./ /tmp/${SDK}
pushd /tmp
tar -cf ${SDK}.tar ${SDK}
gzip ${SDK}.tar
popd
mv /tmp/${SDK}.tar.gz ./$RELEASE/

echo "----------------------------------------------------------"
echo "Done!"
echo "----------------------------------------------------------"

popd
