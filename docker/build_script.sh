#!/bin/bash

repository=${1}
category=${2}
package=${3}
version=${4}
id=${5}
use=${6}

atom=${category}/${package}-${version}::${repository}

GENTOO_BUILD_SERVER="$(ip route | awk 'NR==1 {print $3}'):4000"
DB_SERVER="$(ip route | awk 'NR==1 {print $3}')"

function ebuild_to_path()
{
  local v=$(qatom -F '%{PV}-%[PR]' $(echo ${1%.ebuild} | awk -F/ '{print $(NF)}') | sed -e 's/-$//')
  echo $(echo ${1%.ebuild} | awk -F/ '{print $(NF-3)"/"$(NF-2)"/"$(NF-1)}')/${v}
}

function ebuild_to_atom()
{
  local v=$(qatom -F '%{PV}-%[PR]' $(echo ${1%.ebuild} | awk -F/ '{print $(NF)}') | sed -e 's/-$//')
  echo $(echo ${1%.ebuild} | awk -F/ '{print $(NF-2)"/"$(NF-1)}')-${v}
}

function try_download()
{
  local atom=${1}
  echo ${atom}
  local rest_url=$(qatom --format '%{CATEGORY}/%{PN}/%{PV}-%[PR]' ${atom} | sed -e 's/-$//')
  local uses_json=$(equery -q u ${atom} | sed -e 's/\([+-]\)\(.*\)/"\2":\1/' -e 's/-$/false/' -e 's/+$/true/' -e 's/.*/\0,/')
  local uses_json=${uses_json%,}
  local download=$(curl -f -s -H "Accept: application/json" -H "Content-type: application/json" -X GET -d "{\"use\":{${uses_json}}}" ${GENTOO_BUILD_SERVER}/api/1/atoms/gentoo/${rest_url}/builds)
  echo ${download}
  if [ ${?} != "0" ]; then
      return 1
  fi
  local category=$(qatom --format '%{CATEGORY}' ${atom})
  local package=$(qatom --format '%{PN}' ${atom})
  local version=$(qatom -F '%{PV}-%[PR]' ${atom} | sed -e 's/-$//')
  case $(curl -s ${GENTOO_BUILD_SERVER}/api/1/atoms/${download}/status) in
    '{ status: "success" }')
      mkdir -p /usr/portage/packages/${category}
      if curl -f -s -o /usr/portage/packages/${category}/${package}-${version}.tbz2 ${GENTOO_BUILD_SERVER}/api/1/atoms/${download}; then
        return 0
      else
        return 1
      fi;;
    *)
      return 1;;
  esac
  return 1
}

: > /mnt/package/log

mongo --host ${DB_SERVER} gbs --quiet --eval "db.builds.update({repository:'${repository}',category:'${category}',package:'${package}',version:'${version}',id:'${id}'}, {\$set:{start:NumberLong($(date +%s))}})"
mongo --host ${DB_SERVER} gbs --quiet --eval "db.builds.update({repository:'${repository}',category:'${category}',package:'${package}',version:'${version}',id:'${id}'}, {\$set:{status:'compiling'}})"
echo FEATURES=\'ccache\' >> /etc/portage/make.conf
echo CCACHE_SIZE=\'16G\' >> /etc/portage/make.conf

echo \=${atom} ${use} > /etc/portage/package.use
emerge &> /dev/null
eselect news read &> /dev/null
if ! emerge -qp --autounmask-write \=${atom}; then
  emerge -q --autounmask-write \=${atom} | tee -a /mnt/package/log
  yes | etc-update --automode -3 | tee -a /mnt/package/log
fi
ebuilds=(`emerge -pq \=${atom} | sed -e 's/\[[^]]*\]\([^ ]*\)/\1/g' | tr -d ' ' | xargs -I{} equery w {}`)

for ebuild in ${ebuilds[*]}; do
  echo "Try downloading $(ebuild_to_atom ${ebuild})" | tee -a /mnt/package/log
  if try_download $(ebuild_to_atom ${ebuild}); then
      if emerge -K \=$(ebuild_to_atom ${ebuild}); then
        echo "Available cache $(ebuild_to_atom ${ebuild})" | tee -a /mnt/package/log
        continue
      fi
  fi
  echo "N/A cache $(ebuild_to_atom ${ebuild})" | tee -a /mnt/package/log
  rm -rf /var/tmp/ccache
  if [ -d /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache ]; then
    MAKEOPTS='-j8'
  else
    MAKEOPTS='-j8'
    mkdir -p /mnt/ccache/$(ebuild_to_path ${ebuild})
    install -o root -g portage -m 2775 -d /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache
  fi
  ln -s /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache /var/tmp/ccache

  mkdir -p /mnt/log/$(ebuild_to_path ${ebuild})
  : > /mnt/log/$(ebuild_to_path ${ebuild})/log
  echo "\$ ebuild ${ebuild} merge" | tee -a /mnt/package/log
  env MAKEOPTS=${MAKEOPTS} ebuild ${ebuild} merge | tee -a /mnt/package/log /mnt/log/$(ebuild_to_path ${ebuild})/log
  echo "\$ quickpkg \=$(ebuild_to_atom ${ebuild})" | tee -a /mnt/package/log
  quickpkg \=$(ebuild_to_atom ${ebuild}) | tee -a /mnt/package/log
done

if install -m 644 /usr/portage/packages/${category}/${package}-${version}.tbz2 /mnt/package; then
  mongo --host ${DB_SERVER} gbs --quiet --eval "db.builds.update({repository:'${repository}',category:'${category}',package:'${package}',version:'${version}',id:'${id}'}, {\$set:{status:'success'}})"
else
  mongo --host ${DB_SERVER} gbs --quiet --eval "db.builds.update({repository:'${repository}',category:'${category}',package:'${package}',version:'${version}',id:'${id}'}, {\$set:{status:'failed'}})"
fi
mongo --host ${DB_SERVER} gbs --quiet --eval "db.builds.update({repository:'${repository}',category:'${category}',package:'${package}',version:'${version}',id:'${id}'}, {\$set:{end:NumberLong($(date +%s))}})"
