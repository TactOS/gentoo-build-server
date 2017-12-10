#!/bin/bash
repository=$1
category=$2
package=$3
version=$4
id=$5
use=$6
atom=${category}/${package}-${version}::${repository}
atom_path=${repository}/${category}/${package}/${version}
id_path=${repository}/${category}/${package}/${version}/${id}

function create_ccache_dir()
{
  #TODO copy from old ccache
  mkdir -p ${1}/ccache
}

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

create_ccache_dir gbs/ccache/${atom_path}

mkdir -p ${id_path}
: > ${id_path}/log


cname=${repository}_${category}_${package}_${version}_${id}
cid=$(docker run --rm -v /usr/portage/distfiles:/usr/portage/distfiles -v /var/db/repos/gentoo:/var/db/repos/gentoo:ro -d -i -t --name ${cname}_0 gentoo:gbs)

echo waiting > ${id_path}/status

echo compiling > ${id_path}/status
docker exec ${cid} sh -c "echo ${category}/${package}::${repository} ${use} > /etc/portage/package.use" | tee -a ${id_path}/log
docker exec ${cid} emerge &> /dev/null
docker exec ${cid} eselect news read &> /dev/null
if ! docker exec ${cid} emerge -qp --autounmask-write \=${atom}; then
  docker exec ${cid} emerge -q --autounmask-write \=${atom} | tee -a ${id_path}/log
  docker exec ${cid} sh -c 'yes | etc-update --automode -3' | tee -a ${id_path}/log
fi
ebuilds=(`docker exec ${cid} sh -c "emerge -pq \=${atom} | sed -e 's/\[.*\]//g' | tr -d ' ' | xargs -I{} equery w {}"`)
for ebuild in ${ebuilds[*]}; do
  create_ccache_dir gbs/ccache/$(ebuild_to_path ${ebuild})
done
docker kill ${cid}

ccache_mount=
for ebuild in ${ebuilds[*]}; do
  ccache_mount+=" -v /home/user/work/git/gentoo-build-server/gbs/ccache/$(ebuild_to_path ${ebuild})/ccache:/mnt/ccache/$(ebuild_to_path ${ebuild})/ccache"
done
cid=$(docker run --rm -v /usr/portage/distfiles:/usr/portage/distfiles -v /var/db/repos/gentoo:/var/db/repos/gentoo:ro ${ccache_mount} -d -i -t --name ${cname}_1 gentoo:gbs)
docker exec ${cid} sh -c "echo FEATURES=\'ccache\' >> /etc/portage/make.conf"
docker exec ${cid} sh -c "echo CCACHE_SIZE=\'16G\' >> /etc/portage/make.conf"

docker exec ${cid} sh -c "echo ${category}/${package}::${repository} ${use} > /etc/portage/package.use" | tee -a ${id_path}/log
docker exec ${cid} emerge &> /dev/null
docker exec ${cid} eselect news read &> /dev/null
if ! docker exec ${cid} emerge -qp --autounmask-write \=${atom}; then
  docker exec ${cid} emerge -q --autounmask-write \=${atom} | tee -a ${id_path}/log
  docker exec ${cid} sh -c 'yes | etc-update --automode -3' | tee -a ${id_path}/log
fi

for ebuild in ${ebuilds[*]}; do
  docker exec ${cid} rm -rf /var/tmp/ccache
  docker exec ${cid} ln -s /mnt/ccache/$(ebuild_to_path ${ebuild})/ccache /var/tmp/
  docker exec ${cid} chown portage:portage /var/tmp/ccache
  docker exec ${cid} ebuild ${ebuild} merge | tee -a ${id_path}/log
  docker exec ${cid} quickpkg \=$(ebuild_to_atom ${ebuild}) | tee -a ${id_path}/log
done

if docker cp ${cid}:/usr/portage/packages/${category}/${package}-${version}.tbz2 ${id_path}; then
  echo success > ${id_path}/status
else
  echo failed > ${id_path}/status
fi
docker kill ${cid}
