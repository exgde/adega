#!/bin/sh
# Gera a entrada de um runtime para o runtimes.json (calcula sha256 e tamanho).
#
# Uso:
#   scripts/manifest-entry.sh <arquivo.tar.xz> <url-publica> <id> "<nome>" <versão> "<wineRoot>"
#
# Exemplo:
#   scripts/manifest-entry.sh wine-11.0.tar.xz \
#     https://github.com/voce/adega-runtimes/releases/download/v11.0/wine-11.0.tar.xz \
#     wine-11.0 "Wine 11.0" 11.0 "wine"
set -eu

if [ "$#" -ne 6 ]; then
  sed -n '2,11p' "$0"
  exit 1
fi

file=$1; url=$2; id=$3; name=$4; version=$5; root=$6

if command -v shasum >/dev/null 2>&1; then
  sha=$(shasum -a 256 "$file" | cut -d' ' -f1)
else
  sha=$(sha256sum "$file" | cut -d' ' -f1)
fi
size=$(wc -c < "$file" | tr -d ' ')

cat <<JSON
{
  "id": "$id",
  "displayName": "$name",
  "version": "$version",
  "url": "$url",
  "sha256": "$sha",
  "size": $size,
  "wineRoot": "$root"
}
JSON
