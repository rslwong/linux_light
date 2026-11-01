#!/bin/bash
# Try Linux Light in a QEMU virtual machine, booted as a USB stick.
#
#   tools/test-vm.sh [options] [IMAGE] [-- extra qemu arguments]
#
#   IMAGE                   ISO, or a disk image made by tools/make-usb.sh
#                           (default: out/<IMAGE_NAME>-amd64.iso)
#   --bios                  legacy BIOS boot instead of UEFI
#   --secure-boot           UEFI with Secure Boot enforced (Microsoft keys)
#   --persistence FILE      attach FILE as a second disk, e.g. a file made by
#                           tools/make-ventoy-persistence.sh
#   --disk FILE             attach FILE as the computer's internal disk, to try
#                           the installer on (created as a 20 GB qcow2 if missing)
#   --no-stick              boot without the stick, e.g. the system installed
#                           on --disk
#   --memory MB             RAM size (default: 4096)
#   -h, --help              show this help
#
# Needs qemu-system-x86 and ovmf (apt install qemu-system-x86 ovmf).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${ROOT}/settings.conf"

usage() {
	sed -n '2,19s/^# \{0,1\}//p' "$0"
}

die() {
	echo "error: $*" >&2
	exit 1
}

FIRMWARE=uefi
PERSISTENCE=""
DISK=""
STICK=1
MEMORY=4096
IMAGE="${ROOT}/out/${IMAGE_NAME}-amd64.iso"
EXTRA=()

while [ $# -gt 0 ]; do
	case "$1" in
		--bios) FIRMWARE=bios; shift ;;
		--secure-boot) FIRMWARE=secure; shift ;;
		--persistence) PERSISTENCE="${2:?missing file}"; shift 2 ;;
		--disk) DISK="${2:?missing file}"; shift 2 ;;
		--no-stick) STICK=0; shift ;;
		--memory) MEMORY="${2:?missing size}"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		--) shift; EXTRA=("$@"); break ;;
		-*) usage >&2; exit 1 ;;
		*) IMAGE="$1"; shift ;;
	esac
done

if [ "${STICK}" = 1 ]; then
	[ -f "${IMAGE}" ] || die "${IMAGE} not found"
elif [ -z "${DISK}" ]; then
	die "--no-stick needs --disk"
fi
command -v qemu-system-x86_64 > /dev/null || die "qemu-system-x86_64 not found (apt install qemu-system-x86)"

# Sound goes to the host's PulseAudio/PipeWire when there is one.
AUDIO=none
if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pulse/native" ]; then
	AUDIO=pa
fi

ARGS=(-machine q35 -m "${MEMORY}" -smp 2 -vga virtio
	-device qemu-xhci,id=xhci -device usb-tablet,bus=xhci.0
	-nic user,model=virtio-net-pci
	-audiodev "${AUDIO},id=snd0" -device intel-hda -device hda-duplex,audiodev=snd0)

if [ -w /dev/kvm ]; then
	ARGS+=(-accel kvm -cpu host)
else
	echo "warning: /dev/kvm not usable, the VM will be slow" >&2
fi

if [ "${STICK}" = 1 ]; then
	case "${IMAGE}" in
		*.iso) ARGS+=(-drive "if=none,id=stick,format=raw,readonly=on,file=${IMAGE}") ;;
		*) ARGS+=(-drive "if=none,id=stick,format=raw,file=${IMAGE}") ;;
	esac
	ARGS+=(-device usb-storage,bus=xhci.0,drive=stick,bootindex=0)
fi

if [ -n "${DISK}" ]; then
	if [ ! -e "${DISK}" ]; then
		command -v qemu-img > /dev/null || die "qemu-img not found (apt install qemu-utils)"
		qemu-img create -q -f qcow2 "${DISK}" 20G
	fi
	case "${DISK}" in
		*.qcow2) ARGS+=(-drive "if=virtio,format=qcow2,file=${DISK}") ;;
		*) ARGS+=(-drive "if=virtio,format=raw,file=${DISK}") ;;
	esac
fi

if [ -n "${PERSISTENCE}" ]; then
	[ -f "${PERSISTENCE}" ] || die "${PERSISTENCE} not found"
	ARGS+=(-drive "if=virtio,format=raw,file=${PERSISTENCE}")
fi

if [ "${FIRMWARE}" != bios ]; then
	if [ "${FIRMWARE}" = secure ]; then
		CODE=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
		VARS=/usr/share/OVMF/OVMF_VARS_4M.ms.fd
		ARGS=("${ARGS[@]/#q35/q35,smm=on}" -global driver=cfi.pflash01,property=secure,value=on)
	else
		CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
		VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
	fi
	[ -f "${CODE}" ] || die "${CODE} not found (apt install ovmf)"
	VARS_COPY="$(mktemp --suffix=.fd)"
	trap 'rm -f "${VARS_COPY}"' EXIT
	cp "${VARS}" "${VARS_COPY}"
	ARGS+=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=${CODE}"
		-drive "if=pflash,format=raw,unit=1,file=${VARS_COPY}")
fi

qemu-system-x86_64 "${ARGS[@]}" "${EXTRA[@]}"
