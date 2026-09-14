#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$project_dir/CalibrePlugin/WoodWorkShelf"
output_dir="$project_dir/CalibrePlugin/dist"
output_file="$output_dir/WoodWorkShelf.zip"

mkdir -p "$output_dir"
rm -f "$output_file"
cd "$source_dir"
zip -q -r "$output_file" .
echo "$output_file"

