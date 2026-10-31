#!/bin/bash
# Rebuilds Debian source packages with local patches. Runs inside the builder
# container (see lb-build.sh).
#
#   build-packages.sh DEST
#
# For every directory /src/packages/<source package>/, fetch that package's
# source from the archive, add the *.patch files there to debian/patches,
# build it, and copy the resulting runtime .debs to DEST (live-build's
# config/packages.chroot: live-build installs every package found there, so
# -dev and -dbgsym packages are left out). The version gets a "+linuxlight1"
# suffix so apt prefers it over Debian's.

set -euo pipefail

DEST="$(realpath "${1:?usage: $0 DEST}")"
WORK=/build/packages

mkdir -p "${DEST}"
apt-get update -qq

for dir in /src/packages/*/; do
	[ -d "${dir}" ] || continue
	src="$(basename "${dir}")"
	echo "P: Building ${src} with local patches..."

	rm -rf "${WORK:?}/${src}"
	mkdir -p "${WORK}/${src}"
	cd "${WORK}/${src}"
	apt-get source -qq "${src}"
	cd "$(find . -mindepth 1 -maxdepth 1 -type d | head -n1)"

	mkdir -p debian/patches
	patches=""
	for patch in "${dir}"*.patch; do
		cp "${patch}" debian/patches/
		basename "${patch}" >> debian/patches/series
		patches="${patches} $(basename "${patch}")"
	done

	version="$(dpkg-parsechangelog -S Version)+linuxlight1"
	{
		printf '%s (%s) %s; urgency=medium\n\n' "${src}" "${version}" "$(dpkg-parsechangelog -S Distribution)"
		printf '  * Linux Light: add%s\n\n' "${patches}"
		printf ' -- Linux Light <linux-light@localhost>  %s\n\n' "$(date -R)"
		cat debian/changelog
	} > debian/changelog.new
	mv debian/changelog.new debian/changelog

	dpkg-buildpackage -b -us -uc
	find .. -maxdepth 1 -name "*.deb" ! -name "*-dbgsym_*" ! -name "*-dev_*" -exec cp {} "${DEST}/" \;
done
