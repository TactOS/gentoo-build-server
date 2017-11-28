docker build docker -t gentoo:gbs
cid=$(docker run --rm -v /usr/portage/distfiles:/usr/portage/distfiles -v /var/db/repos/gentoo:/var/db/repos/gentoo:ro -d -i -t gentoo:gbs)
docker exec ${cid} emerge ccache
docker exec ${cid} emerge gentoolkit
docker commit ${cid} gentoo:gbs
