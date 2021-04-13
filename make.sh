#!/bin/bash

PROPERTIES_FILE=build.properties
EXECUTABLE_NAME=ZZT
OUTPUT_ARCHIVE=
TPC_DEFINES=""
FPC_DEFINES=""
TEMP_PATH=$(mktemp -d /tmp/zoo.XXXXXXXXXXXX)
CLEANUP=yes
FREE_PASCAL=
ARCH=i8086
FPC_BINARY=ppcross8086
PLATFORM=msdos
PLATFORM_UNIT_LOWER=dos
PLATFORM_UNIT=DOS
DEBUG_BUILD=

# Parse arguments

OPTIND=1
while getopts "a:d:e:o:p:rg" opt; do
	case "$opt" in
	a)
		IFS='-' read -ra OPTARGARCH <<< "$OPTARG"
		case "${OPTARGARCH[0]}" in
		tp55)
			FREE_PASCAL=
			;;
		fpc)
			FREE_PASCAL=yes
			;;
		*)
			echo "Unknown compiler ${OPTARGARCH[0]}"
			exit 1
			;;
		esac
		ARCH="${OPTARGARCH[1]}"
		case "$ARCH" in
		native)
			FPC_BINARY=fpc
			;;
		i8086)
			FPC_BINARY=ppcross8086
			;;
		i386)
			FPC_BINARY=ppcross386
			;;
		x86_64)
			FPC_BINARY=ppcrossx64
			;;
		arm)
			FPC_BINARY=ppcrossarm
			;;
		*)
			echo "Unknown architecture $ARCH"
			exit 1
			;;
		esac
		PLATFORM="${OPTARGARCH[2]}"
		PLATFORM_UNIT_LOWER="${OPTARGARCH[3]}"
		PLATFORM_UNIT="${PLATFORM_UNIT_LOWER^^}"
		;;
	d)
		FPC_DEFINES=$FPC_DEFINES" -d"$OPTARG
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
	g)
		DEBUG_BUILD=yes
		;;
	esac
done
shift $((OPTIND - 1))

if [ ! -n "$OUTPUT_ARCHIVE" ]; then
	OUTPUT_ARCHIVE="$ARCH"-"$PLATFORM"-"$PLATFORM_UNIT_LOWER".zip
	if [ -n "$FREE_PASCAL" ]; then
		OUTPUT_ARCHIVE=zoo-fpc-"$OUTPUT_ARCHIVE"
	else
		OUTPUT_ARCHIVE=zoo-tpc-"$OUTPUT_ARCHIVE"
	fi
fi

TPC_ARGS=""
FPC_ARGS=""
if [ -z "$DEBUG_BUILD" ]; then
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
		for i in `find "$TEMP_PATH"/SRC -type f`; do
			sed -i -e 's#%'"$KEY"'%#'"$VALUE"'#g' "$i"
		done
	done < "$PROPERTIES_FILE"
fi

FPC_BINARY_PATH="$FPC_PATH"
if [ -x "$(command -v $FPC_BINARY)" ]; then
	FPC_BINARY_PATH=$(realpath $(dirname $(command -v fpc))/..)
fi

sed -i -e 's#%COMPARGS%#'"$TPC_ARGS"'#g' "$TEMP_PATH"/BUILD.BAT
sed -i -e 's#%FPC_PATH%#'"$FPC_PATH"'#g' "$TEMP_PATH"/SYSTEM/fpc.datpack.cfg
for i in `ls "$TEMP_PATH"/SYSTEM/fpc.*.cfg`; do
	sed -i -e 's#%FPC_PATH%#'"$FPC_BINARY_PATH"'#g' "$i"
done
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
	cp ../SYSTEM/fpc.datpack.cfg fpc.cfg
	"$FPC_PATH"/bin/ppcross8086 DATPACK.PAS
	cp DATPACK.exe ../BUILD/DATPACK.EXE
	cd ..

	cd SYSTEM
	touch ../SRC/fpc.cfg
	if [ -f fpc."$ARCH"."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg ]; then
		cat fpc."$ARCH"."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
	elif [ -f fpc."$ARCH"."$PLATFORM".any.cfg ]; then
		cat fpc."$ARCH"."$PLATFORM".any.cfg >> ../SRC/fpc.cfg
		if [ -f fpc.any.any."$PLATFORM_UNIT_LOWER".cfg ]; then
			cat fpc.any.any."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
		else
			echo '-Fu'"$PLATFORM_UNIT" >> ../SRC/fpc.cfg
		fi
	else
		if [ -f fpc."$ARCH".any.any.cfg ]; then
			cat fpc."$ARCH".any.any.cfg >> ../SRC/fpc.cfg
		fi
		if [ -f fpc.any."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg ]; then
			cat fpc.any."$PLATFORM"."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
		else
			if [ -f fpc.any."$PLATFORM".any.cfg ]; then
				cat fpc.any."$PLATFORM".any.cfg >> ../SRC/fpc.cfg
			else
				echo '-T'"$PLATFORM" >> ../SRC/fpc.cfg
			fi
			if [ -f fpc.any.any."$PLATFORM_UNIT_LOWER".cfg ]; then
				cat fpc.any.any."$PLATFORM_UNIT_LOWER".cfg >> ../SRC/fpc.cfg
			else
				echo '-Fu'"$PLATFORM_UNIT" >> ../SRC/fpc.cfg
			fi
		fi
	fi
	cat fpc.base.cfg >> ../SRC/fpc.cfg
	if [ -n "$DEBUG_BUILD" ]; then
		cat fpc.base.debug.cfg >> ../SRC/fpc.cfg
	else
		cat fpc.base.release.cfg >> ../SRC/fpc.cfg
	fi
	cd ../SRC

	echo "[ Building ZZT.EXE ]"
	echo "$FPC_BINARY_PATH"/bin/"$FPC_BINARY" $FPC_ARGS ZZT.PAS
	"$FPC_BINARY_PATH"/bin/"$FPC_BINARY" $FPC_ARGS ZZT.PAS
	if [ -f ZZT.exe ]; then
		cp ZZT.exe ../BUILD/ZZT.EXE
		cp ZZT.exe ../DIST/"$EXECUTABLE_NAME".EXE
	elif [ -f ZZT ]; then
		cp ZZT ../BUILD/ZZT
		cp ZZT ../DIST/"$EXECUTABLE_NAME"
	else
		cd "$RETURN_PATH"
		# rm -rf "$TEMP_PATH"
		exit 1
	fi
	cd ..

	sed -i -e "s/^BUILD$/PACKDAT/" SYSTEM/dosbox.conf
	touch BUILD.LOG
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dosbox -noconsole -conf SYSTEM/dosbox.conf > /dev/null &
	tail --pid $! -n +1 -f BUILD.LOG
else
	# HACK! NEC98 requires SRC/DOS/EXTMEM.PAS, as the underlying standards are
	# the same. (We do this on Free Pascal via fpc.any.any.nec98.cfg.)
	cp SRC/DOS/EXTMEM.PAS SRC/EXTMEM.PAS 2>/dev/null

	cp SRC/"$PLATFORM_UNIT"/*.PAS SRC/ 2>/dev/null
	cp SRC/"$PLATFORM_UNIT"/*.INC SRC/ 2>/dev/null

	touch BUILD.LOG
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy  dosbox -noconsole -conf SYSTEM/dosbox.conf > /dev/null &
	tail --pid $! -n +1 -f BUILD.LOG
fi

if [ ! -f BUILD/ZZT.EXE ]; then
       cd "$RETURN_PATH"
       # rm -r "$TEMP_PATH"
       exit 1
fi

# Post-processing

echo "Packaging..."

if [ "$ARCH" = "i8086" ] && [ "$PLATFORM" = "msdos" ]; then
	if [ -f DIST/"$EXECUTABLE_NAME".EXE ]; then
		rm DIST/"$EXECUTABLE_NAME".EXE
	fi
	if [ ! -x "$(command -v upx)" ]; then
		echo "Not compressing - UPX is not installed!"
		cp BUILD/ZZT.EXE DIST/"$EXECUTABLE_NAME".EXE
	else
		echo "Compressing..."
		upx --8086 -9 -o DIST/"$EXECUTABLE_NAME".EXE BUILD/ZZT.EXE
	fi
fi

if [ -f BUILD/ZZT.DAT ]; then
	cp BUILD/ZZT.DAT DIST/
fi
cp LICENSE.TXT DIST/
cp RES/* DIST/

cp -R DIST/ "$RETURN_PATH"/
#cd DIST
#zip -9 -r "$RETURN_PATH"/OUTPUT/"$OUTPUT_ARCHIVE" .
cd ..

cd "$RETURN_PATH"
if [ -n "$CLEANUP" ]; then
	rm -rf "$TEMP_PATH"
else
	echo 'Not cleaning up as requested; work directory: '"$TEMP_PATH"
fi
