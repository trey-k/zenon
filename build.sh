#!/bin/bash

RELEASES_FILE=build.releases
if [ -n "$1" ]; then
	RELEASES_FILE="$1"
fi

if [ -d "OUTPUT" ]; then
	rm -r "OUTPUT"
fi

while IFS= read -r line
do
	echo 'Building '"$line"'...'
	./make.sh $line
done < "$RELEASES_FILE"
