# gentoo-build-server
## Feture
- Build package remotely
- Build on Docker
- REST API
- Specify version of package
- Specify use flag

# How to Use
### Client
```
# emerge-request localhost:4000 htop
```
### Server
#### Setup
```
$ git clone https:/github.com/otakuto/gentoo-build-server
$ cd gentoo-build-server
# build_container.sh
```
#### Run
```
$ cd gentoo-build-server
# cargo run
```

## Required tools and libs
### Server
- \>=cargo-0.17.0
- \>=rust-1.16.0
- \>=docker-17.05

### Client
- curl
- portage
- gentoolkit

## TODO
- Use kubernetes.
- Use DB.
- Support systemd and other.
- Support multiple compiler.
- Support multiple CFLAGS and CXXFLAGS.
- Support optional ccache.
- Support multiple arch.
- Support multiple OS.
- Support multiple libc.
- emerge-request without local repo.
- Specify version of dependency package.
- Support file search.
- Improve cache.
- Web client.
- View build log in real time.
