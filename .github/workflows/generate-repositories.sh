#!/usr/bin/env bash
set -eux

DEB_TOP="_site/deb"

grep -v '^#' < .github/config/repositories.txt | while IFS= read -r repo ; do
  version="${repo#*-}" ; distro="${repo%-*}"
  grep -v '^#' < .github/config/releases.txt | while IFS= read -r release ; do
    tag="${release#*:}" repo="${release%:*}" ;
    releasejson="/tmp/${release}.json"
    assetfile="${repo}-${distro}-${version}.zip" ; assetpath="/tmp/${assetfile}"
    debout="${DEB_TOP}/pool/${distro}-${version}"
    [[ -e "${releasejson}" ]] || curl -L -o "${releasejson}" "https://api.github.com/repos/arrjay/${repo}/releases/tags/${tag}"
    asset_url="$(jq -r '.assets[] | select(.name=="'"${assetfile}"'").url' < "${releasejson}")"
    [[ -e "${assetpath}" ]] || curl -L -H 'Accept: application/octet-stream' -o "${assetpath}" "${asset_url}"
    mkdir -p "${debout}"
    bsdtar xf "${assetpath}" -C "${debout}"
  done
done

for ent in "${DEB_TOP}/pool"/* ; do
  distdir="${DEB_TOP}/${ent##*/}"
  mkdir -p "${distdir}"
  dpkg-scanpackages "${ent}/" > "${distdir}/Packages"
  gzip -9 > "${distdir}/Packages.gz" < "${distdir}/Packages"
  bzip2 -9 > "${distdir}/Packages.bz2" < "${distdir}/Packages"
  {
    printf '%s: %s\n' \
      Suite releases \
      Codename "${ent##*-}" \
      Components main \
      Date "$(date -Ru)"
  } > "${distdir}/Release"
done
