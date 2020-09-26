#!/bin/bash

PROPERTIES_FILE=build.properties
EXECUTABLE_NAME=ZZT.EXE
OUTPUT_ARCHIVE=zoo.zip
TPC_DEFINES=""
TEMP_PATH=$(mktemp -d /tmp/zoo.XXXXXXXXXXXX)
CLEANUP=yes

# Parse arguments

OPTIND=1
while getopts "d:e:o:p:r" opt; do
	case "$opt" in
	d)
		if [ -n "$TPC_DEFINES" ]; then
			TPC_DEFINES=$TPC_DEFINES","$OPTARG
		else
			TPC_DEFINES=$OPTARG
		fi
		;;
	e)
		EXECUTABLE_NAME=$OPTARG
		;;
	o)
		OUTPUT_ARCHIVE=$OPTARG
		;;
	p)
		PROPERTIES_FILE=$OPTARG
		;;
	r)
		CLEANUP=
		;;
	esac
done
shift $((OPTIND - 1))

TPC_ARGS=""
if [ -n "$TPC_DEFINES" ]; then
	TPC_ARGS="$TPC_ARGS"' /D'"$TPC_DEFINES"
fi

if [ ! -d "OUTPUT" ]; then
	mkdir "OUTPUT"
fi

echo "Preparing Pascal code..."

for i in DOC RES SRC SYSTEM TOOLS VENDOR BUILD.BAT LICENSE.TXT; do
	cp -R "$i" "$TEMP_PATH"/
done

for i in BUILD DIST; do
	mkdir "$TEMP_PATH"/"$i"
done

# Replace symbols with ones from PROPERTIES_FILE
if [ -f "$PROPERTIES_FILE" ]; then
	while IFS='=' read -r KEY VALUE; do
		for i in "$TEMP_PATH"/SRC/*.*; do
			sed -i -e 's#%'"$KEY"'%#'"$VALUE"'#g' "$i"
		done
	done < "$PROPERTIES_FILE"
fi

sed -i -e 's#%COMPARGS%#'"$TPC_ARGS"'#g' "$TEMP_PATH"/BUILD.BAT

echo "Compiling Pascal code..."

RETURN_PATH=$(pwd)
cd "$TEMP_PATH"

touch BUILD.LOG
SDL_VIDEODRIVER=dummy dosbox -noconsole -conf SYSTEM/dosbox.conf > /dev/null &
tail --pid $! -n +1 -f BUILD.LOG

if [ ! -f BUILD/ZZT.EXE ]; then
	cd "$RETURN_PATH"
	rm -r "$TEMP_PATH"
	exit 1
fi

# Post-processing

echo "Packaging..."

if [ ! -x "$(command -v upx)" ]; then
	echo "Not compressing - UPX is not installed!"
	cp BUILD/ZZT.EXE DIST/"$EXECUTABLE_NAME"
else
	echo "Compressing..."
	upx --8086 -9 -o DIST/"$EXECUTABLE_NAME" BUILD/ZZT.EXE
fi

cp BUILD/ZZT.DAT DIST/
cp LICENSE.TXT DIST/
cp RES/* DIST/

cd DIST
zip -9 -r "$RETURN_PATH"/OUTPUT/"$OUTPUT_ARCHIVE" .
cd ..

cd "$RETURN_PATH"
if [ -n "$CLEANUP" ]; then
	rm -r "$TEMP_PATH"
else
	echo 'Not cleaning up as requested; work directory: '"$TEMP_PATH"
fi
