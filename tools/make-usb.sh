#!/bin/bash
# Write Linux Light to a USB stick and add a persistence partition after it.
#
#   sudo tools/make-usb.sh [-s SIZE] [-i ISO] [-y] DEVICE
#
#   DEVICE              the whole USB disk, e.g. /dev/sdb (not a partition such as
#                       /dev/sdb1). A regular file name creates a disk image instead,
#                       which needs no root and can be written to a stick later with dd.
#   -s, --size SIZE     persistence size: 32G, 8192M, ... or "max" for all the space
#                       left on the stick (default: PERSISTENCE_SIZE from
#                       settings.conf, 32G)
#   -i, --iso ISO       image to write (default: out/<IMAGE_NAME>-amd64.iso)
#   -y, --yes           do not ask for confirmation
#   -h, --help          show this help
#
# EVERYTHING ON DEVICE IS DESTROYED.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${ROOT}/settings.conf"
PATH="${PATH}:/usr/sbin:/sbin"

usage() {
	sed -n '2,17s/^# \{0,1\}//p' "$0"
}

die() {
	echo "error: $*" >&2
	exit 1
}

SIZE="${PERSISTENCE_SIZE}"
ISO="${ROOT}/out/${IMAGE_NAME}-amd64.iso"
YES=false
TARGET=""

while [ $# -gt 0 ]; do
	case "$1" in
		-s|--size) SIZE="${2:?missing size}"; shift 2 ;;
		-i|--iso) ISO="${2:?missing ISO}"; shift 2 ;;
		-y|--yes) YES=true; shift ;;
		-h|--help) usage; exit 0 ;;
		-*) usage >&2; exit 1 ;;
		*) [ -z "${TARGET}" ] || { usage >&2; exit 1; }; TARGET="$1"; shift ;;
	esac
done

[ -n "${TARGET}" ] || { usage >&2; exit 1; }
[ -f "${ISO}" ] || die "${ISO} not found, run ./build.sh first"
for tool in sfdisk mkfs.ext4 blkid; do
	command -v "${tool}" > /dev/null || die "${tool} not found (apt install fdisk e2fsprogs util-linux)"
done

MiB=$((1024 * 1024))
ISO_BYTES="$(stat -c %s "${ISO}")"
# The persistence partition starts on the first MiB boundary after the ISO.
START=$(( (ISO_BYTES + MiB - 1) / MiB * MiB ))

if [ "${SIZE}" = "max" ]; then
	PERSIST_BYTES=""
else
	# 32G, 32GB and 32GiB all mean 32 GiB.
	NUM="${SIZE%[bB]}"
	NUM="${NUM%i}"
	PERSIST_BYTES="$(numfmt --from=iec "${NUM}" 2>/dev/null)" || die "invalid size '${SIZE}'"
	PERSIST_BYTES=$(( PERSIST_BYTES / MiB * MiB ))
	[ "${PERSIST_BYTES}" -ge $((256 * MiB)) ] || die "persistence size must be at least 256M"
fi

if [ -b "${TARGET}" ]; then
	[ "$(id -u)" -eq 0 ] || die "writing to ${TARGET} needs root: sudo $0 ..."
	[ "$(lsblk -dno TYPE "${TARGET}")" = "disk" ] \
		|| die "${TARGET} is not a whole disk; give the disk (e.g. /dev/sdb), not a partition"
	# Refuse disks that hold the running system: system mount points or swap.
	for part in $(lsblk -lnpo NAME "${TARGET}"); do
		for mnt in $(findmnt -rno TARGET --source "${part}"); do
			case "${mnt}" in
				/|/boot|/boot/*|/home|/usr|/var|/opt|/srv|/run/live/*)
					die "${TARGET} holds the running system (${part} is mounted on ${mnt})" ;;
			esac
		done
		if swapon --show=NAME --noheadings | grep -qx "${part}"; then
			die "${TARGET} holds the running system (${part} is in use as swap)"
		fi
	done
	DEV_BYTES="$(blockdev --getsize64 "${TARGET}")"
	DESCRIPTION="$(lsblk -dno VENDOR,MODEL,SIZE,TRAN "${TARGET}" | tr -s ' ')"
	[ "$(lsblk -dno RM "${TARGET}")" = "1" ] || [ "$(lsblk -dno TRAN "${TARGET}")" = "usb" ] \
		|| DESCRIPTION="${DESCRIPTION}  ** NOT A REMOVABLE/USB DISK **"
else
	[ ! -e "${TARGET}" ] || [ -f "${TARGET}" ] || die "${TARGET} is neither a block device nor a regular file"
	[ -n "${PERSIST_BYTES}" ] || die "\"max\" only works for real disks; give a size for image files"
	DEV_BYTES=$(( START + PERSIST_BYTES + MiB ))
	DESCRIPTION="disk image file, $(numfmt --to=iec "${DEV_BYTES}")"
fi

# The last MiB stays unused so a GPT backup header can never overlap.
AVAIL=$(( (DEV_BYTES - START) / MiB * MiB - MiB ))
if [ -z "${PERSIST_BYTES}" ]; then
	PERSIST_BYTES="${AVAIL}"
fi
if [ "${AVAIL}" -lt $((256 * MiB)) ]; then
	die "${TARGET} is too small for the $(numfmt --to=iec "${ISO_BYTES}") image plus persistence"
fi
if [ "${PERSIST_BYTES}" -gt "${AVAIL}" ]; then
	die "not enough space: ${TARGET} has $(numfmt --to=iec "${AVAIL}") left after the image, $(numfmt --to=iec "${PERSIST_BYTES}") requested (try -s max)"
fi

echo "Target:      ${TARGET} (${DESCRIPTION})"
echo "Image:       ${ISO} ($(numfmt --to=iec "${ISO_BYTES}"))"
echo "Persistence: $(numfmt --to=iec "${PERSIST_BYTES}") ext4 partition labelled \"persistence\""
if ! ${YES}; then
	if [ -e "${TARGET}" ]; then
		echo
		echo "ALL DATA ON ${TARGET} WILL BE LOST."
	fi
	read -r -p "Type YES to continue: " answer
	[ "${answer}" = "YES" ] || die "aborted"
fi

if [ -b "${TARGET}" ]; then
	for part in $(lsblk -lnpo NAME "${TARGET}"); do
		if findmnt -rno TARGET --source "${part}" > /dev/null; then
			echo "Unmounting ${part}"
			umount "${part}"
		fi
	done
	# Clear old partition tables, including a GPT backup at the end of the disk.
	wipefs --all --quiet "${TARGET}"
	dd if=/dev/zero of="${TARGET}" bs=1M count=1 oflag=seek_bytes seek=$(( DEV_BYTES - MiB )) conv=fsync status=none
else
	rm -f "${TARGET}"
	truncate -s "${DEV_BYTES}" "${TARGET}"
fi

echo "Writing image ..."
dd if="${ISO}" of="${TARGET}" bs=4M conv=notrunc,fsync status=progress

echo "Adding persistence partition ..."
LABEL_TYPE="$(sfdisk --dump "${TARGET}" 2>/dev/null | sed -n 's/^label: //p')"
if [ "${LABEL_TYPE}" = "gpt" ]; then
	# The hybrid image's GPT ends with the image; move its backup to the end of the disk.
	sfdisk --quiet --relocate gpt-bak-std "${TARGET}"
fi
echo "start=$(( START / 512 )), size=$(( PERSIST_BYTES / 512 )), type=L" \
	| sfdisk --quiet --no-reread --no-tell-kernel --append "${TARGET}"

# Create the filesystem through an offset into the whole disk, so it works the
# same for image files and does not depend on the kernel re-reading the table.
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT
echo "/ union" > "${STAGING}/persistence.conf"
mkfs.ext4 -q -F -L persistence -m 1 -E "offset=${START},nodiscard" -d "${STAGING}" \
	"${TARGET}" "$(( PERSIST_BYTES / 1024 ))k"

if [ -b "${TARGET}" ]; then
	partx --update "${TARGET}" 2>/dev/null || blockdev --rereadpt "${TARGET}" 2>/dev/null || true
fi
sync

blkid -p -O "${START}" "${TARGET}" | grep -q 'LABEL="persistence"' \
	|| die "persistence filesystem not found after writing; the stick may be faulty"

echo "Done. Boot from ${TARGET}; the default menu entry uses the persistence partition."
