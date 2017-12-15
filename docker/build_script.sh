#!/bin/bash

repository=${1}
category=${2}
package=${3}
version=${4}
use=${5}

atom=${category}/${package}-${version}::${repository}


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

: > /mnt/package/log

echo compiling > /mnt/package/status
echo FEATURES=\'ccache\' >> /etc/portage/make.conf
echo CCACHE_SIZE=\'16G\' >> /etc/portage/make.conf

echo \=${atom} ${use} > /etc/portage/package.use
emerge &> /dev/null
eselect news read &> /dev/null
if ! emerge -qp --autounmask-write \=${atom}; then
  emerge -q --autounmask-write \=${atom} | tee -a /mnt/package/log
  yes | etc-update --automode -3 | tee -a /mnt/package/log
fi
ebuilds=(`emerge -pq \=${atom} | sed -e 's/\[.*\]//g' | tr -d ' ' | xargs -I{} equery w {}`)

for ebuild in ${ebuilds[*]}; do
  rm -rf /var/tmp/ccache
  if [ -d /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache ]; then
    MAKEOPTS='-j8'
  else
    MAKEOPTS='-j8'
    mkdir -p /mnt/ccache/$(ebuild_to_path ${ebuild})
    install -o root -g portage -m 2775 -d /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache
  fi
  ln -s /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache /var/tmp/ccache
  echo "\$ ebuild ${ebuild} merge" >> /mnt/package/log
  env MAKEOPTS=${MAKEOPTS} ebuild ${ebuild} merge | tee -a /mnt/package/log
  echo "\$ quickpkg \=$(ebuild_to_atom ${ebuild})" >> /mnt/package/log
  quickpkg \=$(ebuild_to_atom ${ebuild}) | tee -a /mnt/package/log
done

if install -m 644 /usr/portage/packages/${category}/${package}-${version}.tbz2 /mnt/package; then
  echo success > /mnt/package/status
else
  echo failed > /mnt/package/status
fi
