#!/bin/bash
repository=$1
category=$2
package=$3
version=$4
id=$5
use=$6
atom=${category}/${package}-${version}::${repository}
atom_path=${repository}/${category}/${package}/${version}/${id}

mkdir -p ${atom_path}
echo progress > ${atom_path}/status
: > ${atom_path}/log

cname=${repository}_${category}_${package}_${version}_${id}
cid=$(docker run --rm -v /usr/portage/distfiles:/usr/portage/distfiles -v /var/db/repos/gentoo:/var/db/repos/gentoo:ro -d -i -t --name ${cname} gentoo:gbs)

docker exec ${cid} sh -c "echo ${category}/${package}::${repository} ${use} > /etc/portage/package.use" | tee -a ${atom_path}/log
docker exec ${cid} emerge -v --buildpkg --autounmask-write '='${atom} | tee -a ${atom_path}/log
if [[ ${PIPESTATUS[0]} != 0 ]]; then
	docker exec ${cid} sh -c 'yes | etc-update --automode -3' | tee -a ${atom_path}/log
	docker exec ${cid} emerge -v --buildpkg --autounmask-write '='${atom} | tee -a ${atom_path}/log
fi
if docker cp ${cid}:/usr/portage/packages/${category}/${package}-${version}.tbz2 ${atom_path}; then
	echo success > ${atom_path}/status
else
	echo failed > ${atom_path}/status
fi
docker kill ${cid}
