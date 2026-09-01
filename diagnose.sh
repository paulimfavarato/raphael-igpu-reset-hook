#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $0 --gpu DDDD:BB:SS.F [--audio DDDD:BB:SS.F]" >&2
}

gpu=''
audio=''
while (($#)); do
  case $1 in
    --gpu) gpu=${2:-}; shift 2 ;;
    --audio) audio=${2:-}; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

readonly bdf_pattern='^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$'
if [[ -z $gpu || ! $gpu =~ $bdf_pattern || ( -n $audio && ! $audio =~ $bdf_pattern ) ]]; then
  usage
  exit 2
fi

show_device() {
  local label=$1 bdf=$2 path=/sys/bus/pci/devices/$2
  if [[ ! -e $path ]]; then
    printf '%s: %s not found\n' "$label" "$bdf"
    return
  fi

  vendor=$(<"$path/vendor")
  device_id=$(<"$path/device")
  driver=none
  [[ ! -L $path/driver ]] || driver=$(basename "$(readlink -f "$path/driver")")
  reset_method=none
  [[ ! -r $path/reset_method ]] || reset_method=$(<"$path/reset_method")
  iommu_group=none
  [[ ! -L $path/iommu_group ]] || iommu_group=$(basename "$(readlink -f "$path/iommu_group")")

  printf '%s: bdf=%s id=%s:%s driver=%s reset_method=%s iommu_group=%s\n' \
    "$label" "$bdf" "${vendor#0x}" "${device_id#0x}" "$driver" "$reset_method" "$iommu_group"
}

show_device GPU "$gpu"
[[ -z $audio ]] || show_device AUDIO "$audio"

faults=$(journalctl -k -b --no-pager 2>/dev/null |
  grep -Ec "$gpu.*IO_PAGE_FAULT|IO_PAGE_FAULT.*$gpu" || true)
printf 'iommu_faults_this_host_boot=%s\n' "${faults:-0}"
