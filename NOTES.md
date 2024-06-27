- Maintain online listing of known-weird packages and their version ranges so the tool can update that listing and know to build bad-package 1.2.3 from scratch instead ever relying on the built one
- Probably build with Docker for the Linuxes, use asdf with nerves-toolchain for the Nerves cross-compile probably?
- Ways to detect NIF and Port use potentially? Libraries without NIFs and Ports should be "pure" meaning the compiled .beam files should work on ANY system.
- Throw out `consolidated` before packing the build. Protocols should be reconsolidated.
- It can be worth building packages for specific processors. Pi Zero has this concern.

Docker:
docker create --name dummy IMAGE_NAME
docker cp dummy:/path/to/file /dest/to/file
docker rm -f dummy

MacOS:
- Probably easiest to do on a Mac, rent an ARM Mac Mini to start

Windows:
- can probably be cross-compiled on Linux which would make ops easier, Docker and all that
- nmake usage means visual studio for windows builds