#!/bin/bash

PROPERTIES_FILE=build.properties
EXECUTABLE_NAME=ZZT.EXE
OUTPUT_ARCHIVE=zoo.zip
TPC_DEFINES=""
FPC_DEFINES=""
TEMP_PATH=$(mktemp -d /tmp/zoo.XXXXXXXXXXXX)
CLEANUP=yes
DEBUG=
FREE_PASCAL=

# Parse arguments

OPTIND=1
while getopts "d:e:fgo:p:r" opt; do
	case "$opt" in
	d)
		if [ -n "$TPC_DEFINES" ]; then
			TPC_DEFINES=$TPC_DEFINES","$OPTARG
		else
			TPC_DEFINES=$OPTARG
		fi
		FPC_DEFINES=$FPC_DEFINES" -d"$OPTARG
		;;
	e)
		EXECUTABLE_NAME=$OPTARG
		;;
	f)
		FREE_PASCAL=yes
		;;
	g)
		DEBUG=yes
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
FPC_ARGS=""
if [ -z "$DEBUG" ]; then
	TPC_ARGS='/$D- /$L- /$S-'
fi
if [ -n "$TPC_DEFINES" ]; then
	TPC_ARGS="$TPC_ARGS"' /D'"$TPC_DEFINES"
	FPC_ARGS="$FPC_ARGS"' '"$FPC_DEFINES"
fi

if [ ! -d "OUTPUT" ]; then
	mkdir "OUTPUT"
fi

echo "Preparing Pascal code..."

for i in DOC RES SRC SYSTEM TOOLS VENDOR LICENSE.TXT; do
	cp -R "$i" "$TEMP_PATH"/
done
cp -R "$TEMP_PATH"/SYSTEM/*.BAT "$TEMP_PATH"/

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
sed -i -e 's#%FPC_PATH%#'"$FPC_PATH"'#g' "$TEMP_PATH"/SYSTEM/fpc.cfg
echo "Compiling Pascal code..."

RETURN_PATH=$(pwd)
cd "$TEMP_PATH"

if [ -n "$FREE_PASCAL" ]; then
	if [ ! -d "$FPC_PATH" ]; then
		echo "Please set the FPC_PATH environment variable!"
		exit 1
	fi

	echo "[ Building DATPACK.EXE ]"
	cd TOOLS
	cp ../SYSTEM/fpc.cfg .
	"$FPC_PATH"/bin/ppcross8086 DATPACK.PAS
	cp DATPACK.exe ../BUILD/DATPACK.EXE
	cd ..

	echo "[ Building ZZT.EXE ]"
	cd SRC
	cp ../SYSTEM/fpc.cfg .
	"$FPC_PATH"/bin/ppcross8086 $FPC_ARGS ZZT.PAS
	cp ZZT.exe ../BUILD/ZZT.EXE
	cd ..

	sed -i -e "s/^BUILD$/PACKDAT/" SYSTEM/dosbox.conf
	touch BUILD.LOG
	SDL_VIDEODRIVER=dummy dosbox -noconsole -conf SYSTEM/dosbox.conf > /dev/null &
	tail --pid $! -n +1 -f BUILD.LOG
else
	touch BUILD.LOG
	SDL_VIDEODRIVER=dummy dosbox -noconsole -conf SYSTEM/dosbox.conf > /dev/null &
	tail --pid $! -n +1 -f BUILD.LOG
fi

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

if [ -f BUILD/ZZT.DAT ]; then
	cp BUILD/ZZT.DAT DIST/
fi
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
