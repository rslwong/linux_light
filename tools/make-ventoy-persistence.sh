#!/bin/bash
# Create a persistence file for booting Linux Light from a Ventoy stick.
#
#   tools/make-ventoy-persistence.sh [-s SIZE] [-o FILE]
#   tools/make-ventoy-persistence.sh [-s SIZE] --ventoy MOUNTPOINT
#
#   -s, --size SIZE         file size, e.g. 32G or 8192M (default: PERSISTENCE_SIZE
#                           from settings.conf, 32G)
#   -o, --output FILE       where to create the file
#                           (default: out/<IMAGE_NAME>-persistence.dat)
#   --ventoy MOUNTPOINT     set up a mounted Ventoy drive in one go: copy the ISO
#                           there, create persistence/<IMAGE_NAME>.dat on it and
#                           register both in ventoy/ventoy.json. Run it again
#                           after a new build to update the ISO; an existing
#                           persistence file is kept.
#   -h, --help              show this help
#
# The file is an ext4 filesystem labelled "persistence" that contains a
# persistence.conf with "/ union", which is what live-boot looks for. No root
# access is needed. The Ventoy data partition must be exFAT (or NTFS/ext4):
# FAT32 cannot hold files of 4 GiB or more.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${ROOT}/settings.conf"

usage() {
	sed -n '2,22s/^# \{0,1\}//p' "$0"
}

die() {
	echo "error: $*" >&2
	exit 1
}

SIZE="${PERSISTENCE_SIZE}"
OUTPUT=""
VENTOY=""

while [ $# -gt 0 ]; do
	case "$1" in
		-s|--size) SIZE="${2:?missing size}"; shift 2 ;;
		-o|--output) OUTPUT="${2:?missing file name}"; shift 2 ;;
		--ventoy) VENTOY="${2:?missing mount point}"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 1 ;;
	esac
done

PATH="${PATH}:/usr/sbin:/sbin"
command -v mkfs.ext4 > /dev/null || die "mkfs.ext4 not found (apt install e2fsprogs)"

# 32G, 32GB and 32GiB all mean 32 GiB.
NUM="${SIZE%[bB]}"
NUM="${NUM%i}"
if ! BYTES="$(numfmt --from=iec "${NUM}" 2>/dev/null)" || [ "${BYTES}" -lt $((256 * 1024 * 1024)) ]; then
	die "invalid size '${SIZE}' (use e.g. 32G or 8192M, at least 256M)"
fi

ISO="${ROOT}/out/${IMAGE_NAME}-amd64.iso"
ISO_NAME="$(basename "${ISO}")"
DAT_REL="persistence/${IMAGE_NAME}.dat"

if [ -n "${VENTOY}" ]; then
	[ -d "${VENTOY}" ] || die "${VENTOY} is not a directory (mount the Ventoy drive first)"
	[ -f "${ISO}" ] || die "${ISO} not found, run ./build.sh first"
	OUTPUT="${VENTOY}/${DAT_REL}"
fi
OUTPUT="${OUTPUT:-${ROOT}/out/${IMAGE_NAME}-persistence.dat}"

if [ -e "${OUTPUT}" ] && [ -n "${VENTOY}" ]; then
	echo "Keeping the existing persistence file ${OUTPUT}."
	echo "Note: changes stored there were made on top of the previous image. If the"
	echo "new image misbehaves, copy your files off it and delete that file to start fresh."
elif [ -e "${OUTPUT}" ]; then
	die "${OUTPUT} already exists; delete it first if you really want a new, empty one"
else
	mkdir -p "$(dirname "${OUTPUT}")"

	FREE="$(df --output=avail -B1 "$(dirname "${OUTPUT}")" | tail -n1)"
	[ "${FREE}" -gt "${BYTES}" ] || die "not enough free space for ${SIZE} in $(dirname "${OUTPUT}")"

	STAGING="$(mktemp -d)"
	trap 'rm -rf "${STAGING}"' EXIT
	echo "/ union" > "${STAGING}/persistence.conf"

	echo "Creating ${SIZE} persistence file ${OUTPUT} ..."
	echo "(On exFAT the whole size gets written once, which takes a while: about"
	echo " 18 minutes for 32G on a USB SSD, longer on a slow stick.)"
	truncate -s "${BYTES}" "${OUTPUT}"
	mkfs.ext4 -q -F -L persistence -m 1 -E nodiscard -d "${STAGING}" "${OUTPUT}"
fi

if [ -z "${VENTOY}" ]; then
	cat <<-EOF
	Done. To use it with Ventoy:
	  1. copy ${ISO_NAME} and this file to the Ventoy drive, e.g. the file to /${DAT_REL}
	  2. add this to /ventoy/ventoy.json on the Ventoy drive:
	     {
	       "persistence": [
	         { "image": "/${ISO_NAME}", "backend": "/${DAT_REL}", "autosel": 1 }
	       ]
	     }
	EOF
	exit 0
fi

if [ ! -f "${VENTOY}/${ISO_NAME}" ] || ! cmp -s "${ISO}" "${VENTOY}/${ISO_NAME}"; then
	echo "Copying ${ISO_NAME} to ${VENTOY} ..."
	cp "${ISO}" "${VENTOY}/${ISO_NAME}"
fi

JSON="${VENTOY}/ventoy/ventoy.json"
mkdir -p "${VENTOY}/ventoy"
if command -v python3 > /dev/null; then
	python3 -I - "${JSON}" "/${ISO_NAME}" "/${DAT_REL}" <<-'EOF'
	import json, os, sys
	path, image, backend = sys.argv[1:4]
	conf = {}
	if os.path.exists(path):
	    with open(path) as f:
	        conf = json.load(f)
	entries = [e for e in conf.get("persistence", []) if e.get("image") != image]
	entries.append({"image": image, "backend": backend, "autosel": 1})
	conf["persistence"] = entries
	with open(path, "w") as f:
	    json.dump(conf, f, indent=4)
	    f.write("\n")
	EOF
elif [ ! -e "${JSON}" ]; then
	printf '{\n    "persistence": [\n        { "image": "/%s", "backend": "/%s", "autosel": 1 }\n    ]\n}\n' \
		"${ISO_NAME}" "${DAT_REL}" > "${JSON}"
else
	die "python3 is needed to update the existing ${JSON}; add {\"image\": \"/${ISO_NAME}\", \"backend\": \"/${DAT_REL}\", \"autosel\": 1} to its \"persistence\" list by hand"
fi

sync
echo "Done. Boot ${ISO_NAME} from Ventoy; it uses ${DAT_REL} automatically."
