# Raphael iGPU reset hook for libvirt

Experimental workaround for AMD Raphael iGPU passthrough guests that work on
the first start after a host reboot, but produce a white/corrupted physical
display and AMD-Vi `IO_PAGE_FAULT` events on later guest starts.

The hook temporarily binds the iGPU to the host `amdgpu` driver before QEMU
starts. Removing it from `amdgpu` triggers a `MODE2 reset`; the helper then
returns the device to `vfio-pci` and allows libvirt to continue.

## Tested configuration

- AMD Ryzen 9 7950X3D Raphael iGPU (`1002:164e`)
- Raphael HDMI audio (`1002:1640`)
- MSI MAG X670E TOMAHAWK WIFI
- Arch Linux, kernel 7.1.9
- libvirt 12.6.0 / QEMU 11.1.0
- Windows 11 guest with the AMD display driver

This is not a universal AMD reset fix. Probing or resetting a passed-through
GPU can freeze or reboot the host. Keep a recovery path and test manually
before installing the hook.

The helper intentionally refuses GPUs other than `1002:164e` and, when an
audio function is configured, expects `1002:1640`.

## Symptom and verification

The failure reproduced on the second guest start in the same host uptime.
Windows reported the Radeon as healthy, but the physical output was white and
the host logged events similar to:

```text
vfio-pci 0000:17:00.0: AMD-Vi: Event logged [IO_PAGE_FAULT ...]
```

Check the current host boot with:

```bash
sudo journalctl -k -b --no-pager |
  grep -E '17:00.0.*IO_PAGE_FAULT|IO_PAGE_FAULT.*17:00.0'
```

Replace `17:00.0` with your iGPU address.

## Requirements

- The iGPU must already work in the guest on a cold host boot.
- The iGPU must be bound to `vfio-pci` before the VM starts.
- The host must have the `amdgpu` module available.
- The VM must use the system libvirt connection.
- Bash, util-linux (`flock`), systemd/udev and libvirt.

This project does **not** configure IOMMU, extract or redistribute firmware,
modify guest XML, or install Windows drivers.

Firmware binaries are executable, checksum-protected and platform-specific.
Editing identifiers to “sanitize” a VBIOS/GOP can corrupt it, and the AMD/MSI
blobs do not come with a clear redistribution license. Extract and validate
firmware from the target machine instead of downloading someone else's ROM.

## Manual test first

Identify the PCI addresses:

```bash
lspci -nnk | grep -A3 -E 'VGA|Display|Audio'
```

With the guest fully shut down, run:

```bash
sudo ./manual-reseed.sh --gpu 0000:17:00.0
```

Start the guest again and confirm both the physical output and absence of new
IOMMU faults. Repeat the manual cycle at least twice before installing.

## Install

Keep the guest shut down, then run:

```bash
sudo ./install.sh \
  --vm windows11 \
  --gpu 0000:17:00.0 \
  --audio 0000:17:00.1
```

The audio address is optional. When provided, the helper verifies that it is
also in `vfio-pci`, but does not rebind it.

Restart the libvirt daemon after all guests are shut down:

```bash
sudo systemctl restart libvirtd.service
```

On distributions using modular daemons, restart `virtqemud.service` instead.
The next start of the configured VM should take roughly 10 seconds longer.

## Logs

```bash
sudo ls -lt /var/log/raphael-igpu-reset/
sudo tail -100 /var/log/raphael-igpu-reset/hook-*.log
```

A successful run ends with:

```text
PASS: preventive reset completed
```

## Uninstall

With the guest shut down:

```bash
sudo ./uninstall.sh
sudo systemctl restart libvirtd.service
```

Logs are preserved.

## How it is wired

The installer creates:

```text
/etc/raphael-igpu-reset.conf
/etc/libvirt/hooks/qemu.d/50-raphael-igpu-reset
/usr/local/libexec/raphael-igpu-reset/reseed
```

The hook filters libvirt's `guest prepare begin` arguments. It never calls
`virsh` from inside the hook. A failed reset returns a non-zero status so
libvirt refuses to start QEMU with an uncertain GPU state.

## Important limitations

- Never force-stop a guest while the physical GPU is active.
- Do not use this on the GPU driving the host desktop.
- PCI addresses are machine-specific.
- A host reboot remains the recovery path if the GPU probe/reset hangs.
- ROM/VBIOS/GOP files are intentionally excluded.

## Related reports and prior work

- [Issue #135](https://github.com/isc30/ryzen-gpu-passthrough-proxmox/issues/135)
  is the closest reported case: Raphael on an X3D CPU, virt-manager/KVM,
  Windows 11, first boot working and second boot glitching with AMD-Vi
  `IO_PAGE_FAULT` events.
- [Issue #131](https://github.com/isc30/ryzen-gpu-passthrough-proxmox/issues/131)
  is important prior work: its Proxmox hook cycles a Ryzen 7 7700 Raphael iGPU
  between `amdgpu` and `vfio-pci`. This project adapts that general mechanism
  for an early-VFIO host and performs the complete reseed immediately before
  QEMU, with validation, locking, logs and rollback.
- [Discussion #2](https://github.com/isc30/ryzen-gpu-passthrough-proxmox/discussions/2)
  previously observed that the original `amdgpu` driver appears to help reset
  and includes a 7950X3D report.
- [Issue #112](https://github.com/isc30/ryzen-gpu-passthrough-proxmox/issues/112)
  reports success after removing iGPU audio on different hardware. That
  hypothesis was tested here with a combined VBIOS/GOP ROM and did not fix the
  7950X3D second-start fault.

Technical references:

- [libvirt QEMU hooks](https://www.libvirt.org/hooks.html)
- [Linux driver binding](https://docs.kernel.org/driver-api/driver-model/binding.html)
- [Linux AMDGPU MODE2 reset implementation](https://github.com/torvalds/linux/blob/786262be6048deab760f68c8acc2c85607165894/drivers/gpu/drm/amd/amdgpu/nv.c#L394-L475)

## License

MIT. See [LICENSE](LICENSE).
