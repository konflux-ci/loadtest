#!/bin/bash

# Merges multiple JSON files into one

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 file1.json file2.json ..."
    exit 1
fi

n=0

echo "[" > merged.json
for var in "$@"; do
    (( n++ ))
    cat "$var" >> merged.json
    if [ "$n" -lt "$#" ]; then
        echo "," >> merged.json
    fi
done
echo "]" >> merged.json

echo "Merged $# files into merged.json"
