#!/usr/bin/env bash
set -eux

SITE_TOP="$(pwd)/_site"
POOL_TOP="${SITE_TOP}/pool"
DIST_TOP="${SITE_TOP}/dists"

# turn off gpg ever asking anything
export GPG_TTY=""

# from https://github.com/terminate-notice/terminate-notice.github.io/blob/main/.github/scripts/build_repos.sh
generate_hashes() {
  HASH_TYPE="$1"
  HASH_COMMAND="$2"
  echo "${HASH_TYPE}:"
  find "${COMPONENTS:-main}" -type f | while read -r file
  do
    echo " $(${HASH_COMMAND} "$file" | cut -d" " -f1) $(wc -c "$file")"
  done
}

grep -v '^#' < .github/config/repositories.txt | while IFS= read -r repo ; do
  version="${repo#*-}" ; distro="${repo%-*}"
  grep -v '^#' < .github/config/releases.txt | while IFS= read -r release ; do
    tag="${release#*:}" repo="${release%:*}" ;
    releasejson="/tmp/${release}.json"
    assetfile="${repo}-${distro}-${version}.zip" ; assetpath="/tmp/${assetfile}"
    debout="${POOL_TOP}/${distro}-${version}"
    [[ -e "${releasejson}" ]] || curl -L -o "${releasejson}" "https://api.github.com/repos/arrjay/${repo}/releases/tags/${tag}"
    asset_url="$(jq -r '.assets[] | select(.name=="'"${assetfile}"'").url' < "${releasejson}")"
    [[ -n "${asset_url}" ]] && curl -L -H 'Accept: application/octet-stream' -o "${assetpath}" "${asset_url}"
    mkdir -p "${debout}"
    [[ -e "${assetpath}" ]] && bsdtar xf "${assetpath}" -C "${debout}" || true
  done
done

for ent in "${POOL_TOP}"/* ; do
  distdir="${DIST_TOP}/${ent##*-}"
  for bin in all amd64 ; do
    mkdir -p "${distdir}/main/binary-${bin}"
    pushd "${SITE_TOP}" >/dev/null 2>&1
      dpkg-scanpackages -a "${bin}" "${ent#"${SITE_TOP}/"}/" > "${distdir}/main/binary-${bin}/Packages"
    popd >/dev/null 2>&1
    gzip -9 > "${distdir}/main/binary-${bin}/Packages.gz" < "${distdir}/main/binary-${bin}/Packages"
    bzip2 -9 > "${distdir}/main/binary-${bin}/Packages.bz2" < "${distdir}/main/binary-${bin}/Packages"
    xz -9 > "${distdir}/main/binary-${bin}/Packages.xz" < "${distdir}/main/binary-${bin}/Packages"
    zstd > "${distdir}/main/binary-${bin}/Packages.zst" < "${distdir}/main/binary-${bin}/Packages"
    lz4 -9 > "${distdir}/main/binary-${bin}/Pazkages.lz4" < "${distdir}/main/binary-${bin}/Packages"
  done
  {
    printf '%s: %s\n' \
      Suite releases \
      Components main \
      Codename "${ent##*-}" \
      Date "$(date -Ru)"
      pushd "${distdir}" >/dev/null 2>&1
      generate_hashes MD5Sum md5sum
      generate_hashes SHA1 sha1sum
      generate_hashes SHA256 sha256sum
      popd >/dev/null 2>&1
  } > "${distdir}/Release"
  gpg --detach-sign --armor --sign > "${distdir}/Release.gpg" < "${distdir}/Release"
  gpg --detach-sign --armor --sign --clearsign > "${distdir}/InRelease" < "${distdir}/Release"
done
