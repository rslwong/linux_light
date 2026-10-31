#!/bin/bash
# Build the Linux Light live ISO.
#
#   ./build.sh [build]   build out/<name>-amd64.iso (downloaded packages are cached)
#   ./build.sh resume    continue an interrupted build where it stopped
#   ./build.sh clean     remove the build tree, keep the package cache
#   ./build.sh purge     remove the build tree and the package cache
#   ./build.sh shell     shell inside the build container, for debugging
#
# live-build needs root, so it runs inside a privileged podman (or docker)
# container. With rootless podman no root access on the host is needed.
# Settings live in settings.conf; any of them can be overridden from the
# environment, e.g.  LIVE_KEYBOARD=de ./build.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="linux-light-builder"
ENGINE="${ENGINE:-$(command -v podman || command -v docker || true)}"

usage() {
	sed -n '2,13s/^# \{0,1\}//p' "$0"
}

ACTION="${1:-build}"
case "${ACTION}" in
	build|resume|clean|purge|shell) ;;
	-h|--help|help) usage; exit 0 ;;
	*) usage >&2; exit 1 ;;
esac

if [ -z "${ENGINE}" ]; then
	echo "error: podman or docker is required (apt install podman)" >&2
	exit 1
fi

. "${ROOT}/settings.conf"
ENV_ARGS=()
for var in DIST MIRROR SECURITY_MIRROR IMAGE_NAME ISO_VOLUME LIVE_HOSTNAME \
		LIVE_USERNAME LIVE_LOCALE LIVE_KEYBOARD LIVE_TIMEZONE PERSISTENCE_SIZE; do
	ENV_ARGS+=(--env "${var}=${!var}")
done
# Rootful docker writes the ISO as root; hand it back to the calling user.
if [ "$(basename "${ENGINE}")" = "docker" ] && [ "$(id -u)" -ne 0 ]; then
	ENV_ARGS+=(--env "OUT_OWNER=$(id -u):$(id -g)")
fi

mkdir -p "${ROOT}/build" "${ROOT}/out"

# Cheap when nothing changed: every layer comes from the cache.
"${ENGINE}" build --quiet --tag "${IMAGE}" --file "${ROOT}/Containerfile" "${ROOT}" > /dev/null

TTY_ARGS=()
if [ -t 0 ] && [ -t 1 ]; then
	TTY_ARGS=(--interactive --tty)
fi

run() {
	"${ENGINE}" run --rm "${TTY_ARGS[@]}" --privileged \
		--volume "${ROOT}:/src:ro" \
		--volume "${ROOT}/build:/build" \
		--volume "${ROOT}/out:/out" \
		"${ENV_ARGS[@]}" \
		"${IMAGE}" /src/scripts/lb-build.sh "${ACTION}"
}

case "${ACTION}" in
	build|resume)
		echo "Building ${IMAGE_NAME} (Debian ${DIST}) with $(basename "${ENGINE}"); log: out/build.log"
		run 2>&1 | tee "${ROOT}/out/build.log"
		;;
	*)
		run
		;;
esac
