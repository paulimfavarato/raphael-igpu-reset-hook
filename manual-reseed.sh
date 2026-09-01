#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: sudo $0 --gpu DDDD:BB:SS.F [--audio DDDD:BB:SS.F] [--settle SECONDS]" >&2
}

gpu=''
audio=''
settle=10
while (($#)); do
  case $1 in
    --gpu) gpu=${2:-}; shift 2 ;;
    --audio) audio=${2:-}; shift 2 ;;
    --settle) settle=${2:-}; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 || -z $gpu ]]; then
  usage
  exit 2
fi

readonly bdf_pattern='^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$'
if [[ ! $gpu =~ $bdf_pattern ]]; then
  echo "Invalid GPU address: $gpu" >&2
  exit 2
fi
if [[ -n $audio && ! $audio =~ $bdf_pattern ]]; then
  echo "Invalid audio address: $audio" >&2
  exit 2
fi
if [[ ! $settle =~ ^[0-9]+$ ]] || (( settle < 1 || settle > 60 )); then
  echo "--settle must be an integer from 1 to 60." >&2
  exit 2
fi

temporary=$(mktemp /etc/raphael-igpu-reset.manual.XXXXXX)
cleanup() {
  [[ ! -e $temporary ]] || unlink "$temporary"
}
trap cleanup EXIT

printf "GPU_BDF='%s'\nAUDIO_BDF='%s'\nSETTLE_SECONDS='%s'\n" \
  "$gpu" "$audio" "$settle" >"$temporary"

if [[ -e /etc/raphael-igpu-reset.conf ]]; then
  echo "Refusing to replace the installed configuration for a manual test." >&2
  exit 1
fi

install -m 0600 "$temporary" /etc/raphael-igpu-reset.conf
trap 'unlink /etc/raphael-igpu-reset.conf 2>/dev/null || true; cleanup' EXIT

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
"$script_dir/reseed"

unlink /etc/raphael-igpu-reset.conf
trap cleanup EXIT
echo "PASS: manual reset completed"
