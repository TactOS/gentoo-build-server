#!/bin/bash
GBS_DIR=/var/lib/gbs

repository=$1
category=$2
package=$3
version=$4
id=$5
use=$6
atom=${category}/${package}-${version}::${repository}
atom_path=${repository}/${category}/${package}/${version}
id_path=${GBS_DIR}/packages/${repository}/${category}/${package}/${version}/${id}


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

mkdir -p ${id_path}
: > ${id_path}/log

cname=${repository}_${category}_${package}_${version}_${id}

echo compiling > ${id_path}/status
cid=$(docker run --rm -v ${GBS_DIR}/distfiles:/usr/portage/distfiles -v ${GBS_DIR}/repos:/var/db/repos:ro -v ${GBS_DIR}/ccache:/mnt/ccache --cap-add=SYS_PTRACE -idt --name ${cname} gentoo:gbs)
docker exec ${cid} sh -c "echo FEATURES=\'ccache\' >> /etc/portage/make.conf"
docker exec ${cid} sh -c "echo CCACHE_SIZE=\'16G\' >> /etc/portage/make.conf"

docker exec ${cid} sh -c "echo ${category}/${package}::${repository} ${use} > /etc/portage/package.use"
docker exec ${cid} emerge &> /dev/null
docker exec ${cid} eselect news read &> /dev/null
if ! docker exec ${cid} emerge -qp --autounmask-write \=${atom}; then
  docker exec ${cid} emerge -q --autounmask-write \=${atom} | tee -a ${id_path}/log
  docker exec ${cid} sh -c 'yes | etc-update --automode -3' | tee -a ${id_path}/log
fi
ebuilds=(`docker exec ${cid} sh -c "emerge -pq \=${atom} | sed -e 's/\[.*\]//g' | tr -d ' ' | xargs -I{} equery w {}"`)

for ebuild in ${ebuilds[*]}; do
  docker exec ${cid} rm -rf /var/tmp/ccache
  if docker exec ${cid} [ -d /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache ]; then
    MAKEOPTS='-j1'
  else
    MAKEOPTS='-j8'
    docker exec ${cid} mkdir -p /mnt/ccache/$(ebuild_to_path ${ebuild})
    docker exec ${cid} install -o root -g portage -m 2775 -d /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache
  fi
  docker exec ${cid} ln -s /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache /var/tmp/ccache
  echo "\$ ebuild ${ebuild} merge" >> ${id_path}/log
  docker exec ${cid} env MAKEOPTS=${MAKEOPTS} ebuild ${ebuild} merge | tee -a ${id_path}/log
  echo "\$ quickpkg \=$(ebuild_to_atom ${ebuild})" >> ${id_path}/log
  docker exec ${cid} quickpkg \=$(ebuild_to_atom ${ebuild}) | tee -a ${id_path}/log
done

if docker cp ${cid}:/usr/portage/packages/${category}/${package}-${version}.tbz2 ${id_path}; then
  echo success > ${id_path}/status
else
  echo failed > ${id_path}/status
fi
docker kill ${cid}
