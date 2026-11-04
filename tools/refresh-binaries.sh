#!/usr/bin/env bash
# refresh-binaries.sh — build the Yantra desktop bundles and refresh the release tree
# (<repo>/yantra-os/downloads), or verify that tree is current with --check.
#
# This script lives at <repo>/yantra-os/tools/refresh-binaries.sh, beside
# build-binaries.sh; every path is derived from this script's own location, so it
# never assumes a working directory.  The release tree is ../downloads from tools/.
#
#   refresh-binaries.sh                 build + install the two compressed bundles,
#                                       rewrite SHA256SUMS, BUILD-INFO.txt, README.md
#   refresh-binaries.sh --check         verify only, writes nothing (CI safe)
#   refresh-binaries.sh --help          usage
#
# Only the two compressed bundles are ever committed — never loose binaries or DLL trees.
set -euo pipefail

PROG=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# The builder sits beside this script; ../tools is the same directory in both layouts.
BUILD_SCRIPT="$SCRIPT_DIR/../tools/build-binaries.sh"
LINUX_BUNDLE="yantra-linux-x64.tar.gz"
WINDOWS_BUNDLE="yantra-windows-x64.zip"
BUNDLES=("$LINUX_BUNDLE" "$WINDOWS_BUNDLE")

# Paths that make the bundles stale when they move.  Missing paths are filtered out
# before use, so this list may name directories a tree does not have.
SOURCE_PATHS="render host libs sdk tools protocol yantra-os/apps yantra-os/render yantra-os/host yantra-os/sdk yantra-os/assets yantra-os/store"

MODE="refresh"
ALLOW_DIRTY=0
STAGING=""
STAGING_GIVEN=0
KEEP_STAGING=0
RELEASE_DIR=""

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }
fail() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: refresh-binaries.sh [--refresh] [--allow-dirty] [--staging DIR] [--keep-staging]
       refresh-binaries.sh --check
       refresh-binaries.sh --help

  (default)        build both bundles via ../tools/build-binaries.sh, install them into
                   ../downloads, then rewrite SHA256SUMS, BUILD-INFO.txt and README.md
  --check          verify the release tree only; builds nothing, writes nothing
  --allow-dirty    build even when the git tree has uncommitted changes (records dirty=1)
  --staging DIR    build into DIR instead of a fresh mktemp directory
  --keep-staging   keep the staging directory after a successful build
EOF
}

# ---------------------------------------------------------------- paths and git

detect_release_dir() {
	# Published standalone layout: tools/ and downloads/ are both at the repo top.
	if [ -d "$SCRIPT_DIR/../downloads" ]; then
		printf '%s\n' "$SCRIPT_DIR/../downloads"
	# In-repo layout: tools/ is one level down, downloads/ its sibling under yantra-os/.
	elif [ -d "$SCRIPT_DIR/../../yantra-os/downloads" ]; then
		printf '%s\n' "$SCRIPT_DIR/../../yantra-os/downloads"
	else
		# Not refreshed yet: report ../downloads, and --check will name every missing file.
		printf '%s\n' "$SCRIPT_DIR/../downloads"
	fi
}

repo_root() { git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null; }

rel_to_repo() { realpath --relative-to="$2" "$1" 2>/dev/null || printf '%s\n' "$1"; }

# Existing SOURCE_PATHS only, so a missing directory cannot break the staleness query.
source_paths_existing() { # $1 = repo root
	local p found=""
	for p in $SOURCE_PATHS; do
		[ -e "$1/$p" ] && found="$found $p"
	done
	# A tree whose releases live at its top (no yantra-os/ prefix) still works.
	if [ -z "${found// /}" ]; then
		for p in $SOURCE_PATHS; do
			p=${p#yantra-os/}
			[ -e "$1/$p" ] && found="$found $p"
		done
	fi
	printf '%s\n' "${found# }"
}

# ------------------------------------------------------ reading inside a bundle

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
bytes_of() { stat -c '%s' "$1"; }

# Text of BUILD-INFO.txt inside a tar.gz (contract: top-level entry linux-x64/).
tar_info() {
	local f=$1 name
	# awk must read to the END of the listing: an early `exit` makes tar die of SIGPIPE and,
	# under `set -o pipefail`, the whole pipeline then reads as a failure (this cost me one
	# `--check` that called a perfectly good bundle MISSING).
	name=$(tar -tzf "$f" 2>/dev/null | awk '/(^|\/)BUILD-INFO\.txt$/' | sed -n 1p) || return 1
	[ -n "$name" ] || return 1
	tar -xzOf "$f" "$name" 2>/dev/null
}

# Text of BUILD-INFO.txt inside a zip (contract: top-level entry yantra/).
zip_info() {
	python3 -c 'import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
n = next((x for x in z.namelist() if x.endswith("BUILD-INFO.txt")), None)
if n is None:
    sys.exit(1)
sys.stdout.write(z.read(n).decode("utf-8", "replace"))' "$1"
}

# BUILD-INFO text of a bundle, whichever archive type it is.
bundle_info() { # $1 = bundle path
	case $1 in
	*.tar.gz) tar_info "$1" ;;
	*.zip) zip_info "$1" ;;
	*) return 1 ;;
	esac
}

# One key=value line out of BUILD-INFO text.  A bundle built on Windows may carry
# CRLF line endings, so a trailing \r is stripped before the value is printed.
info_field() { # $1 = text, $2 = key
	printf '%s\n' "$1" | awk -v k="$2" '
		{ line = $0; sub(/\r$/, "", line) }
		index(line, k "=") == 1 { value = substr(line, length(k) + 2); sub(/\r$/, "", value); print value; exit }'
}

# name<TAB>hash pairs out of a SHA256SUMS file (standard "hash  name" format).
sums_pairs() { # $1 = SHA256SUMS path
	awk 'NF >= 2 { name = $2; sub(/^\*/, "", name); sub(/\r$/, "", name); print name "\t" $1 }' "$1"
}

# ---------------------------------------------------------------- check mode

CHECK_PROBLEMS=0
report() { printf '%s\n' "$*"; CHECK_PROBLEMS=$((CHECK_PROBLEMS + 1)); }

run_check() {
	local release_dir="$RELEASE_DIR" root want="" want_subject="" sums="$RELEASE_DIR/SHA256SUMS"
	local have_sums=1 b path exp act info have_commit sha_short

	say "check: release dir $release_dir"

	root=$(repo_root) || fail "check: not a git repository (or git is unavailable): $SCRIPT_DIR"
	[ -n "$root" ] || fail "check: not a git repository: $SCRIPT_DIR"

	for b in SHA256SUMS BUILD-INFO.txt "${BUNDLES[@]}"; do
		if [ ! -f "$release_dir/$b" ]; then
			report "MISSING: $release_dir/$b"
			[ "$b" = "SHA256SUMS" ] && have_sums=0
		fi
	done

	# WANT is the newest commit that touched source code, not merely the checked-out HEAD.
	local paths
	paths=$(source_paths_existing "$root")
	want=$(git -C "$root" rev-list -1 HEAD -- $paths) || want=""
	if [ -z "$want" ]; then
		report "STALE: cannot compute the newest source commit — git rev-list -1 HEAD over SOURCE_PATHS returned nothing"
	else
		want_subject=$(git -C "$root" log -1 --format=%s "$want")
		[ -n "$want_subject" ] || want_subject="(no subject)"
	fi

	for b in "${BUNDLES[@]}"; do
		path="$release_dir/$b"
		[ -f "$path" ] || continue # already reported MISSING above
		act=$(sha256_of "$path")
		sha_short=${act:0:16}
		exp=""
		[ "$have_sums" = 1 ] && exp=$(sums_pairs "$sums" | awk -F'\t' -v n="$b" '$1 == n { print $2; exit }')
		info=$(bundle_info "$path" 2>/dev/null) || info=""
		have_commit=$(info_field "$info" source_commit)

		if [ -z "$exp" ]; then
			report "BADHASH: $b: no sha256 line in SHA256SUMS (file is $act)"
			continue
		fi
		if [ "$exp" != "$act" ]; then
			report "BADHASH: $b: SHA256SUMS says $exp, file is $act"
			continue
		fi
		if [ -z "$have_commit" ]; then
			report "MISSING: $b: no source_commit= inside the bundle's own BUILD-INFO.txt"
			continue
		fi
		if [ -z "$want" ]; then
			continue # the uncomputable WANT was already reported
		fi
		if [ "$have_commit" != "$want" ]; then
			report "STALE: $b: bundle source_commit $have_commit != newest source commit $want ($want_subject)"
			continue
		fi
		say "OK: $b (sha256 $sha_short, source_commit ${have_commit:0:12})"
	done

	if [ "$CHECK_PROBLEMS" -gt 0 ]; then
		if [ "$CHECK_PROBLEMS" = 1 ]; then
			say "check: stale (1 problem)"
		else
			say "check: stale ($CHECK_PROBLEMS problems)"
		fi
		exit 1
	fi
	say "check: fresh (source commit $want $want_subject)"
	exit 0
}

# -------------------------------------------------------------- refresh mode

# 20-line README.md, rewritten from this template on every run.
write_readme() {
	local dir=$1 commit=$2 subject=$3 commit_date=$4 built_utc=$5 build_cmd=$6 refresh_cmd=$7
	local lb=$8 lsha=$9 wb=${10} wsha=${11} head=${12}
	local tmp n
	tmp=$(mktemp)
	{
		printf '# Yantra desktop binaries\n'
		printf '\n'
		printf 'Built from source commit `%s` — %.96s.\n' "$commit" "$subject"
		printf 'Source commit date `%s`; refreshed `%s` UTC from checkout `%s`.\n' "$commit_date" "$built_utc" "${head:0:12}"
		printf 'Build command: `%s`, then `%s` installs the result here.\n' "$build_cmd" "$refresh_cmd"
		printf '\n'
		printf 'The bundle in this repository is the source of truth; the Google Drive copy is a mirror for when GitHub'"'"'s size limit or bandwidth gets in the way — if the mirror dies, the clone still builds.\n'
		printf '\n'
		printf '**Compressed bundles only.** The release tree carries no loose binaries, DLL trees or\n'
		printf 'directories — that is the owner'"'"'s order. Unpack to run.\n'
		printf '\n'
		printf '| File (in this repo) | Bytes | SHA-256 | Built from | Drive mirror |\n'
		printf '| --- | ---: | --- | --- | --- |\n'
		printf '| [%s](%s) | %s | `%s` | `%.12s` | |\n' "$LINUX_BUNDLE" "$LINUX_BUNDLE" "$lb" "$lsha" "$commit"
		printf '| [%s](%s) | %s | `%s` | `%.12s` | |\n' "$WINDOWS_BUNDLE" "$WINDOWS_BUNDLE" "$wb" "$wsha" "$commit"
		printf '\n'
		printf 'Unpack on Linux: `tar -xzf %s && cd linux-x64 && ./run-yantra.sh`; on Windows: unzip and run `yantra\\Yantra.bat`.\n' "$LINUX_BUNDLE"
		printf 'Verify with `sha256sum -c SHA256SUMS`; provenance is in BUILD-INFO.txt and each bundle'"'"'s own copy.\n'
		printf '\n'
		printf 'Windows also needs the Microsoft VC++ 2015-2022 x64 runtime (bundled app-local here); Linux needs glibc >= 2.35.\n'
	} > "$tmp"
	n=$(wc -l < "$tmp")
	if [ "$n" -ne 20 ]; then
		rm -f "$tmp"
		fail "internal: README template produced $n lines, expected 20"
	fi
	chmod 644 "$tmp" # mktemp makes 600; a published README should be world readable
	mv -f "$tmp" "$dir/README.md"
}

run_refresh() {
	local release_dir="$RELEASE_DIR" root commit commit_date commit_subject head_commit dirty dirty_line
	local rel_build rel_refresh build_cmd refresh_cmd rel_release
	local b old_sha prev_sums="" sums="$RELEASE_DIR/SHA256SUMS" paths want=""
	local linux_bytes linux_sha windows_bytes windows_sha win_info carried built_utc
	local changed=0 same=0 new=0 removed=0 extra=""
	declare -A NEW_SHA=() OLD_SHA=() NEW_BYTES=()

	mkdir -p "$release_dir"
	say "release dir: $release_dir"

	root=$(repo_root) || fail "refresh: not a git repository (or git is unavailable): $SCRIPT_DIR"
	[ -n "$root" ] || fail "refresh: not a git repository: $SCRIPT_DIR"
	head_commit=$(git -C "$root" rev-parse HEAD)
	# The record is the newest commit that touched source code, exactly what --check compares
	# against: committing the release tree itself must not make a good build look stale.
	paths=$(source_paths_existing "$root")
	want=$(git -C "$root" rev-list -1 HEAD -- $paths) || want=""
	[ -n "$want" ] || fail "refresh: cannot compute the newest source commit — git rev-list -1 HEAD over SOURCE_PATHS returned nothing"
	commit=$want
	commit_date=$(git -C "$root" log -1 --format=%cI "$commit")
	commit_subject=$(git -C "$root" log -1 --format=%s "$commit")

	# Our own output — the release directory — is not "dirt"; everything else is.
	rel_release=$(rel_to_repo "$release_dir" "$root")
	dirty_line=$(git -C "$root" status --porcelain --untracked-files=normal -- . ":(exclude)$rel_release" || true)
	if [ -n "$dirty_line" ]; then
		if [ "$ALLOW_DIRTY" = 1 ]; then
			say "WARNING: dirty tree (--allow-dirty) — recording dirty=1"
			printf '%s\n' "$dirty_line" | sed 's/^/  /'
			dirty=1
		else
			printf '%s\n' "$dirty_line" | sed 's/^/  /' >&2
			fail "refresh: uncommitted changes outside $rel_release — commit them, or pass --allow-dirty"
		fi
	else
		dirty=0
	fi

	[ -f "$BUILD_SCRIPT" ] || fail "refresh: builder not found: $(realpath -m "$BUILD_SCRIPT")"
	if [ "$STAGING_GIVEN" = 1 ]; then
		mkdir -p "$STAGING"
	else
		STAGING=$(mktemp -d)
	fi
	say "staging dir: $STAGING"
	say "build: bash $BUILD_SCRIPT --out $STAGING"
	bash "$BUILD_SCRIPT" --out "$STAGING" || fail "refresh: build failed: bash $BUILD_SCRIPT --out $STAGING"

	for b in "${BUNDLES[@]}"; do
		[ -f "$STAGING/$b" ] ||
			fail "refresh: builder produced no $b in $STAGING (contract: --out <dir> writes $LINUX_BUNDLE and $WINDOWS_BUNDLE)"
	done

	# The old sums are the only record of what the tree carried before this run.
	if [ -f "$sums" ]; then
		prev_sums="$STAGING/.prev-SHA256SUMS"
		cp "$sums" "$prev_sums"
		while IFS=$'\t' read -r b old_sha; do
			[ -n "${b:-}" ] && OLD_SHA["$b"]=$old_sha
		done < <(sums_pairs "$prev_sums")
	fi

	for b in "${BUNDLES[@]}"; do
		cp -f "$STAGING/$b" "$release_dir/$b"
		NEW_SHA["$b"]=$(sha256_of "$release_dir/$b")
		NEW_BYTES["$b"]=$(bytes_of "$release_dir/$b")
	done
	linux_sha=${NEW_SHA[$LINUX_BUNDLE]}
	linux_bytes=${NEW_BYTES[$LINUX_BUNDLE]}
	windows_sha=${NEW_SHA[$WINDOWS_BUNDLE]}
	windows_bytes=${NEW_BYTES[$WINDOWS_BUNDLE]}

	( cd "$release_dir" && sha256sum "$LINUX_BUNDLE" "$WINDOWS_BUNDLE" > SHA256SUMS )

	built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	rel_build=$(rel_to_repo "$(realpath -m "$BUILD_SCRIPT")" "$root")
	rel_refresh=$(rel_to_repo "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$root")
	build_cmd="bash $rel_build --out <staging-dir>"
	refresh_cmd="bash $rel_refresh"

	win_info=$(bundle_info "$release_dir/$WINDOWS_BUNDLE" 2>/dev/null) || win_info=""
	carried=$(info_field "$win_info" carried)

	{
		printf 'source_commit=%s\n' "$commit"
		printf 'source_commit_date=%s\n' "$commit_date"
		printf 'head_commit=%s\n' "$head_commit"
		printf 'built_utc=%s\n' "$built_utc"
		printf 'build_command=%s\n' "$build_cmd"
		printf 'refresh_command=%s\n' "$refresh_cmd"
		printf 'dirty=%s\n' "$dirty"
		printf 'linux_bytes=%s\n' "$linux_bytes"
		printf 'linux_sha256=%s\n' "$linux_sha"
		printf 'windows_bytes=%s\n' "$windows_bytes"
		printf 'windows_sha256=%s\n' "$windows_sha"
		[ -n "$carried" ] && printf 'carried=%s\n' "$carried"
	} > "$release_dir/BUILD-INFO.txt"

	write_readme "$release_dir" "$commit" "$commit_subject" "$commit_date" "$built_utc" \
		"$build_cmd" "$refresh_cmd" "$linux_bytes" "$linux_sha" "$windows_bytes" "$windows_sha" "$head_commit"

	# Change table against the SHA256SUMS that was there before this run.
	say ""
	say "change table (against the previous SHA256SUMS):"
	printf '  %-8s %-26s %s\n' "STATUS" "BUNDLE" "DETAIL"
	for b in "${BUNDLES[@]}"; do
		old_sha=${OLD_SHA[$b]:-}
		if [ -z "$old_sha" ]; then
			new=$((new + 1))
			printf '  %-8s %-26s %s\n' "NEW" "$b" "${NEW_SHA[$b]}"
		elif [ "$old_sha" = "${NEW_SHA[$b]}" ]; then
			same=$((same + 1))
			printf '  %-8s %-26s %s\n' "SAME" "$b" "${NEW_SHA[$b]}"
		else
			changed=$((changed + 1))
			printf '  %-8s %-26s %s -> %s\n' "CHANGED" "$b" "$old_sha" "${NEW_SHA[$b]}"
		fi
	done
	for b in "${!OLD_SHA[@]}"; do
		case $b in
		"$LINUX_BUNDLE" | "$WINDOWS_BUNDLE") continue ;;
		esac
		if [ ! -f "$release_dir/$b" ]; then
			removed=$((removed + 1))
			printf '  %-8s %-26s %s\n' "REMOVED" "$b" "${OLD_SHA[$b]}"
		fi
	done
	say "refresh: $changed changed, $same same, $new new, $removed removed"
	say "wrote: SHA256SUMS ($(wc -l < "$sums") bundles), BUILD-INFO.txt, README.md ($(wc -l < "$release_dir/README.md") lines)"

	# Loose files are not managed here; say so instead of deleting anyone's work.
	for b in "$release_dir"/* "$release_dir"/.[!.]*; do
		[ -e "$b" ] || continue
		case $(basename "$b") in
		"$LINUX_BUNDLE" | "$WINDOWS_BUNDLE" | SHA256SUMS | BUILD-INFO.txt | README.md) continue ;;
		esac
		extra="$extra $(basename "$b")"
	done
	[ -n "$extra" ] && say "note: unmanaged files in $release_dir:$extra"

	if [ "$KEEP_STAGING" = 1 ] || [ "$STAGING_GIVEN" = 1 ]; then
		say "staging kept: $STAGING"
	else
		rm -rf "$STAGING"
	fi
}

# --------------------------------------------------------------------- drive

while [ $# -gt 0 ]; do
	case $1 in
	--refresh) MODE=refresh ;;
	--check) MODE=check ;;
	-h | --help) MODE=help ;;
	--allow-dirty) ALLOW_DIRTY=1 ;;
	--keep-staging) KEEP_STAGING=1 ;;
	--staging)
		shift
		[ $# -gt 0 ] || die "--staging needs a directory"
		STAGING=$1
		STAGING_GIVEN=1
		;;
	--staging=*)
		STAGING=${1#*=}
		[ -n "$STAGING" ] || die "--staging needs a directory"
		STAGING_GIVEN=1
		;;
	*) die "unknown option: $1 (try --help)" ;;
	esac
	shift
done

RELEASE_DIR=$(realpath -m "$(detect_release_dir)")
BUILD_SCRIPT=$(realpath -m "$BUILD_SCRIPT")

case $MODE in
help)
	usage
	exit 0
	;;
check)
	run_check
	;;
refresh)
	run_refresh
	;;
esac
