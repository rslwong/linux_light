#!/bin/bash
# Drives live-build. Runs inside the builder container started by build.sh:
#   /src   this repository (read-only)
#   /build live-build working directory (chroot, binary tree, package cache)
#   /out   finished ISO
#
#   lb-build.sh build    clean build of the ISO (the package cache is kept)
#   lb-build.sh resume   continue an interrupted build from its last stage
#   lb-build.sh clean    remove the build tree, keep the package cache
#   lb-build.sh purge    remove the build tree and the package cache
#   lb-build.sh shell    interactive shell in /build

set -euo pipefail

SRC=/src
WORK=/build
OUT=/out

set -a
. "${SRC}/settings.conf"
set +a

cd "${WORK}"

# A rootless container cannot create device nodes, so debootstrap ends up
# leaving chroot/dev empty. Bind-mount the basic devices from the container
# for as long as live-build works in the chroot. When the build runs as real
# root this just mounts over the nodes debootstrap created.
DEVICES="null zero full random urandom tty"

mount_dev() {
	local dev link
	mkdir -p chroot/dev/pts chroot/dev/shm
	for dev in ${DEVICES}; do
		[ -e "chroot/dev/${dev}" ] || touch "chroot/dev/${dev}"
		mountpoint -q "chroot/dev/${dev}" || mount --bind "/dev/${dev}" "chroot/dev/${dev}"
	done
	mountpoint -q chroot/dev/shm || mount -t tmpfs -o mode=1777,nosuid,nodev shm chroot/dev/shm
	[ -e chroot/dev/ptmx ] || [ -L chroot/dev/ptmx ] || ln -s pts/ptmx chroot/dev/ptmx
	for link in fd:/proc/self/fd stdin:/proc/self/fd/0 stdout:/proc/self/fd/1 stderr:/proc/self/fd/2; do
		[ -L "chroot/dev/${link%%:*}" ] || ln -s "${link#*:}" "chroot/dev/${link%%:*}"
	done
}

# Unmount everything below chroot/: our device binds plus anything live-build
# left behind after a failure.
umount_all() {
	awk -v root="${WORK}/chroot" 'index($2, root) == 1 { print $2 }' /proc/self/mounts \
		| sort -r | while read -r mnt; do umount -l "${mnt}"; done
}

clean_tree() {
	umount_all
	# An interrupted build leaves live-build's lock behind.
	rm -f .lock
	if [ -d config ]; then
		lb clean
	fi
	rm -rf auto config chroot binary .build ./*.iso ./*.packages ./*.contents ./*.files ./*.log
}

# Packages that the installer adds to an installed system (GRUB for UEFI or
# BIOS, lb/pool/*.list) go into a package pool on the ISO, with their
# dependencies, so installing needs no internet. live-build has this feature
# (*.list.binary), but with --build-with-chroot false its chroot has no DNS
# at that point. Runs after the squashfs is built, so the temporary
# resolv.conf never reaches the image.
build_pool() {
	local list cache=/build/pool.cache dist="${DIST}"

	echo "P: Building the package pool for the installer..."
	rm -rf "${cache}" binary/pool binary/dists
	mkdir -p "${cache}/archives/partial"
	cp -a chroot/etc/resolv.conf chroot/etc/resolv.conf.lb-build
	cp /etc/resolv.conf chroot/etc/resolv.conf
	mount --bind "${cache}" chroot/mnt
	for list in "${SRC}"/lb/pool/*.list; do
		grep -v '^\s*#' "${list}" | xargs chroot chroot apt-get -q -y \
			-o Dir::Cache=/mnt -o Dir::State::status=/dev/null \
			-o Debug::NoLocking=true --download-only install
	done
	umount chroot/mnt
	mv chroot/etc/resolv.conf.lb-build chroot/etc/resolv.conf

	mkdir -p "binary/pool/main" "binary/dists/${dist}/main/binary-${ARCH:-amd64}"
	mv "${cache}"/archives/*.deb binary/pool/main/
	rm -rf "${cache}"
	(
		cd binary
		apt-ftparchive packages pool/main > "dists/${dist}/main/binary-${ARCH:-amd64}/Packages"
		gzip -9 -k "dists/${dist}/main/binary-${ARCH:-amd64}/Packages"
		apt-ftparchive \
			-o APT::FTPArchive::Release::Origin="Linux Light" \
			-o APT::FTPArchive::Release::Suite="${dist}" \
			-o APT::FTPArchive::Release::Codename="${dist}" \
			-o APT::FTPArchive::Release::Architectures="${ARCH:-amd64}" \
			-o APT::FTPArchive::Release::Components=main \
			release "dists/${dist}" > /build/Release.tmp
		mv /build/Release.tmp "dists/${dist}/Release"
	)
	echo "P: Package pool: $(ls binary/pool/main | wc -l) packages, $(du -sh binary/pool | cut -f1)"
}

# live-build's GRUB hybrid layout makes the ISO filesystem mountable only
# from the whole disk. live-boot then never looks for a persistence partition
# on the stick it booted from, since it skips the disk holding the live
# medium. So re-master the image the way Ubuntu does: partition 1 is the
# (mountable) ISO filesystem and the EFI system partition is appended as
# partition 2, which leaves room for a persistence partition behind them.
remaster_iso() {
	local iso="${IMAGE_NAME}-amd64.hybrid.iso"
	local cmd=(xorriso -as mkisofs -R -r -J -joliet-long -l -iso-level 3
		-V "${ISO_VOLUME}" -A "Linux Light" -publisher "Linux Light"
		--grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img
		-partition_offset 16 --mbr-force-bootable
		-append_partition 2 0xef binary/boot/grub/efi.img -appended_part_as_gpt
		-iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7
		-c boot/grub/boot.cat
		-b boot/grub/grub_eltorito -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info
		-eltorito-alt-boot -e --interval:appended_partition_2::: -no-emul-boot
		-o "${iso}" binary)

	echo "P: Re-mastering ${iso} with a mountable ISO partition..."
	echo "${cmd[*]}" > binary/.disk/mkisofs
	rm -f "${iso}"
	"${cmd[@]}"
}

publish() {
	local iso="${IMAGE_NAME}-amd64.hybrid.iso"
	local name="${IMAGE_NAME}-amd64"

	[ -f "${iso}" ] || { echo "error: live-build did not produce ${iso}" >&2; exit 1; }
	mkdir -p "${OUT}"
	cp "${iso}" "${OUT}/${name}.iso"
	cp "${IMAGE_NAME}-amd64.packages" "${OUT}/${name}.packages" 2>/dev/null || true
	(cd "${OUT}" && sha256sum "${name}.iso" > "${name}.iso.sha256")
	if [ -n "${OUT_OWNER:-}" ]; then
		chown "${OUT_OWNER}" "${OUT}/${name}".*
	fi
	echo
	echo "Done: out/${name}.iso ($(du -h "${OUT}/${name}.iso" | cut -f1))"
}

run_stages() {
	trap umount_all EXIT
	lb bootstrap
	mount_dev
	lb chroot
	# Before making the squashfs, live-build copies its binary-stage package
	# cache into chroot/var/cache/apt/archives, which with
	# --build-with-chroot false is the image itself. Linux Light uses no
	# such cache (see build_pool), so keep it empty.
	rm -rf cache/packages.binary
	rm -f chroot/var/cache/apt/archives/*.deb
	lb binary
	build_pool
	umount_all
	trap - EXIT
	remaster_iso
	publish
}

case "${1:-build}" in
	build)
		clean_tree
		cp -a "${SRC}/lb/auto" "${SRC}/lb/config" .
		lb config
		"${SRC}/scripts/build-packages.sh" config/packages.chroot
		run_stages
		;;
	resume)
		[ -d config ] || { echo "error: nothing to resume, run a build first" >&2; exit 1; }
		run_stages
		;;
	clean)
		clean_tree
		;;
	purge)
		umount_all
		find "${WORK}" -mindepth 1 -delete
		;;
	shell)
		exec bash
		;;
	*)
		echo "usage: $0 build|resume|clean|purge|shell" >&2
		exit 1
		;;
esac
