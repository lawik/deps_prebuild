# TODO

## Done

### Fix Cross-Compilation in Docker
- [x] Parameterize toolchain download to use `ARCH` and `LIBC` build args
- [x] Fix ENV block cascading (Docker can't reference vars in same block)
- [x] Fix `CROSSCOMPILE` typo (`{$GCC_PREFIX}` -> `${GCC_PREFIX}`)
- [x] Remove `ABI` arg duplication (now uses `LIBC` consistently)
- [x] Remove dead commented-out code and placeholder env vars
- [ ] Verify toolchain env vars actually get sourced during `mix compile`
  (the /etc/profile.d/ approach may not work in non-login Docker RUN shells)
- [ ] Get one package (e.g. `jason`) cross-compiling for aarch64 successfully

### Code Cleanup
- [x] Remove all `dbg()` calls throughout the codebase
- [x] Fix `docker_cp` and `docker_rm` returning wrong error atom `:docker_create_fail`
- [x] Fix `docker_hub_find_tag` not passing `prefix` to `docker_hub_find`
- [x] Remove dead commented-out code (tar/untar/compress experiments)
- [x] Replace `dbg(e)` crash with `Logger.error` in `p1()` error handler

### Platform Detection
- [x] Extract `DepsPrebuild.Platform` module (os/arch/otp_version/libc)
- [x] Fix `get_arch` to handle aarch64, armv7, armv6, armv5 (was x86_64 only)
- [x] Add libc detection (musl vs gnu via `ldd --version`)
- [x] Add `Build.for_current_platform/0` convenience constructor
- [x] Simplify `build_lock.ex` to use `Build.for_current_platform`

### NIF / Port Detection
- [x] `NifDetector` module scanning for c_src/, Makefiles, CMakeLists.txt
- [x] Scan for `:erlang.load_nif` / `erlang:load_nif` / `erl_nif.h`
- [x] Scan for `Port.open` / `open_port` usage
- [x] Detect native compilers in mix.exs (elixir_make, rustler, zigler, cmake)
- [x] Build struct tracks `native` / `native_reasons` fields
- [x] Integrated into build pipeline after `check_package_type`
- [x] Test suite with 8 tests covering all detection paths

### Separate Build Paths
- [x] Lightweight `Dockerfile-elixir-pure` and `Dockerfile-erlang-pure` (no toolchain)
- [x] Build pipeline selects Dockerfile based on NIF detection
- [x] Pure builds skip ARCH/GCC_VERSION/LIBC docker args
- [x] Extracted duplicate docker flow into `do_docker_build/2`

---

## Up Next

### 1. End-to-End Build Verification

The build pipeline exists but hasn't been proven end-to-end. There are
likely issues that will surface when actually running Docker builds.

- [ ] Test `mix deps.build_lock` against a simple project
- [ ] Verify the `/etc/profile.d/toolchain.sh` approach works in Docker RUN
  (may need to `source` it explicitly or use a different env setup)
- [ ] Verify the artifact can be unpacked and used in a consuming project
- [ ] Test a native package build (e.g. `jason_native` or `comeonin`)
- [ ] Test a pure package build (e.g. `jason`)

### 2. Unused Code Cleanup

Remaining compiler warnings from pre-existing code:

- [ ] `@oses` module attribute unused in `deps_prebuild.ex` (superseded by Platform)
- [ ] `@dh_page_size` module attribute unused
- [ ] `to_app_names/1` unused in `get_build.ex`
- [ ] `major_minor/1` and `major/1` unused in `build_lock.ex` (now in Platform)
- [ ] Decide: keep `get_build.ex` or rewrite from scratch (it's mostly copied
  Mix.Dep.Fetcher internals that don't actually fetch pre-builds)

### 3. Artifact Storage

Builds go nowhere right now. Need a place to store and serve them.

- [ ] Choose storage backend (S3, GitHub Releases, or custom)
- [ ] Upload step after successful build
- [ ] Index/manifest of available pre-built artifacts (package, version, platform)
- [ ] Deduplication - don't rebuild what's already stored

### 4. Web Dashboard

A Phoenix LiveView dashboard showing build status across the Hex.pm ecosystem.

- [ ] Pull package list from Hex.pm (already have `search/3` for this)
- [ ] Track build attempts and outcomes per package/version/platform
- [ ] Show pass/fail/skip status for each package
- [ ] Filter by architecture, libc, mix_env, Elixir/OTP version
- [ ] Show NIF/Port detection results (pure vs native)
- [ ] Flag "weird packages" that need manual attention
- [ ] Show build logs for failed packages
- [ ] Coverage overview: % of top-N packages pre-built per platform

### 5. Mix Task: Fetch Pre-Builds (eventually a separate package)

A `mix deps.get_prebuilt` task that consumers install to fetch pre-compiled
deps instead of compiling from source. Lives in this repo for now but should
eventually be extracted into its own Hex package.

- [ ] Design the protocol: how does the task discover available pre-builds?
  - Needs to know: package name, version, current Elixir/OTP, target arch/os/libc, mix_env
  - Query the artifact index/manifest from storage
- [ ] Download matching pre-built artifact
- [ ] Unpack into the project's `_build/{env}/lib/{package}` directory
- [ ] Fallback to normal `mix deps.compile` if no pre-build is available
- [ ] Handle version matching (exact Elixir/OTP match? major.minor match?)
- [ ] Integrate with `mix deps.get` flow or run as a post-step
- [ ] Eventually: extract to its own repo/hex package (e.g. `prebuilt` or `hex_prebuilt`)
- [ ] Decide: rewrite `get_build.ex` from scratch vs adapting current code
  (current code is copied Mix internals and doesn't actually fetch pre-builds)

### 6. CI/CD Automation

- [ ] GitHub Actions workflow to build packages on push/schedule
- [ ] Matrix strategy across architectures (can use QEMU for ARM)
- [ ] Scheduled runs to pick up new Hex package versions
- [ ] Upload artifacts to storage after successful builds

### 7. Expand Platform Support

- [ ] macOS aarch64 (needs ARM Mac runner or cross-compilation approach)
- [ ] Windows x86_64 (cross-compile from Linux with nmake/Visual Studio tools)
- [ ] Alpine/musl builds (test with musl toolchain variant)

### 8. Weird Package Tracking

Some packages produce bad pre-builds due to compile-time configuration,
code generation, or other unusual setups.

- [ ] Maintain a known-weird-packages list with version ranges
- [ ] Auto-detect common patterns that break pre-builds
  - Compile-time config reading (Application.compile_env)
  - Code generation that embeds host-specific paths
  - Packages that shell out during compilation
- [ ] Surface these on the dashboard
- [ ] Consumer mix task should skip pre-builds for flagged packages

### 9. Docker Optimization

- [ ] Cache the toolchain download layer (it's large and slow)
- [ ] Consider multi-stage builds to reduce final image size
- [ ] Investigate if the profile.d approach works or if we need
  explicit `source /etc/profile.d/toolchain.sh &&` in RUN commands
- [ ] Test builds with Alpine base image (smaller, musl-based)

### 10. Documentation

- [ ] Fill in README.md with project description and usage
- [ ] Document the build tag format and what each segment means
- [ ] Document how to run builds locally
- [ ] Document the consumer mix task (once it exists)
