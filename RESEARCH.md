# deps_prebuild - Research Notes

## What This Project Is

A tool to pre-build Elixir/Erlang Hex packages so consumers can skip compilation.
The goal: faster installs and fewer issues from compiling complex dependencies.

## Current State: Early Prototype

The core build pipeline exists but is incomplete. Recent git history shows active
work fighting Docker and toolchain integration. The project is functional enough
to attempt builds but has significant gaps before it's production-ready.

## What Exists

### Build Pipeline (mostly working)

The core flow in `lib/deps_prebuild.ex` does:

1. **Download** package tarball from Hex via `hex_core`
2. **Unpack & verify** checksum against `CHECKSUM` file
3. **Detect package type** - Elixir (`mix.exs`) vs Erlang (`rebar.config`/`rebar.lock`/`erlang.mk`)
4. **Docker build** - builds inside a Docker container with Nerves toolchain
5. **Extract artifacts** via `docker create` + `docker cp` + `docker rm`
6. **Strip consolidated protocols** (need to be reconsolidated by consumer)
7. **Package** final `.tar.gz` with a descriptive tag name

### Build Context (`lib/deps_prebuild/build.ex`)

A `Build` struct tracks all parameters for a build:
- Package name, version, type
- Elixir/OTP/GCC versions
- Architecture, OS, libc, mix_env
- File paths through the pipeline

Tag format: `{name}-{version}-{env}-elixir-{elixir}-otp-{otp}-{os}-{arch}-{libc}`

### Docker Images (`docker/`)

Two Dockerfiles (Elixir and Erlang), nearly identical:
- Base image: `hexpm/elixir:{version}-erlang-{otp}-ubuntu-jammy`
- Installs build tools
- Clones and downloads Nerves cross-compilation toolchain
- Sets up cross-compilation environment variables (CC, CXX, LD, AR, etc.)
- Copies package source and runs `mix deps.get, compile` or `rebar3 compile`

### Mix Tasks

- **`mix deps.build_lock`** (`lib/mix/tasks/build_lock.ex`) - Reads `mix.lock`, iterates hex deps, builds each for dev/prod/test environments
- **`mix deps.get_built`** (`lib/mix/tasks/get_build.ex`) - Intended to replace `mix deps.get` by fetching pre-compiled packages instead. Currently a heavily-modified copy of Mix.Dep.Fetcher internals.

### Target Matrix

| Dimension | Values |
|-----------|--------|
| OS | Linux (macOS and Windows planned but commented out) |
| Architecture | x86_64, armv5, armv6, armv7, aarch64 |
| Libc | gnu, musl |
| Mix env | dev, prod, test |

Theoretical max: 5 arch x 2 libc x 3 env = **30 combinations per package version per Elixir/OTP pair**.

## What's Missing / Incomplete

### Critical Gaps

1. **Toolchain not actually wired up** - Both Dockerfiles have the comment
   `# TODO: actually use the toolchain y'all` (line 71). The Nerves toolchain
   is downloaded and env vars are set, but the toolchain version is hardcoded
   to `v13.2.0-x86_64-nerves-linux-gnu` regardless of the `ARCH` build arg.
   Cross-compilation isn't actually happening yet.

2. **No artifact storage/CDN** - Packages are built locally. There's no upload
   step, no S3/CDN/Hex-compatible registry, no way for consumers to actually
   fetch pre-built artifacts.

3. **`mix deps.get_built` is a stub** - It copies internal Mix.Dep.Fetcher/
   Converger code and runs the standard `scm.checkout` flow. It doesn't
   actually fetch pre-built packages - it just reimplements `mix deps.get`.
   The key piece (replacing checkout with a pre-built artifact download) isn't there.

4. **No CI/CD** - No GitHub Actions, no automation. Everything runs manually.

5. **No NIF/Port detection** - NOTES.md flags this as important. Packages with
   NIFs produce platform-specific machine code and need special handling.
   Pure BEAM packages are portable. No detection exists yet.

### Secondary Gaps

6. **Docker arch parameterization broken** - The toolchain download is hardcoded
   to `x86_64-nerves-linux-gnu`. Needs to use the `ARCH` and `LIBC` args to
   select the right toolchain for cross-compilation.

7. **`get_arch` only handles x86_64** - In `build_lock.ex:82`, the arch
   detection pattern-matches `"x86_64" <> _` and has no clauses for ARM.

8. **Error tuple inconsistency** - `docker_cp` and `docker_rm` both return
   `{:error, {:docker_create_fail, status}}` instead of their own error atoms.

9. **Debug calls left in** - Multiple `|> dbg()` calls throughout the codebase.

10. **No versioning/caching strategy** - No way to check if a pre-built
    artifact already exists before rebuilding. Every run builds from scratch.

11. **macOS/Windows** - Code has the structure for them (the `@arch_and_os`
    keyword list), but no implementation. macOS would need a Mac runner.
    Windows may be cross-compilable from Linux.

12. **"Weird package" tracking** - NOTES.md mentions maintaining a list of
    packages known to produce bad pre-builds. Not implemented.

13. **README** - Contains only boilerplate, not filled in.

## Architecture Decisions Made

- **Docker-based builds** - Good isolation, reproducible environments
- **Nerves toolchains** - Leverages existing ARM cross-compilation infrastructure
- **hexpm base images** - Established, well-maintained Elixir Docker images
- **Per-package builds** - Each Hex package built individually (not whole projects)
- **Tag naming** - Captures full build matrix in the artifact name

## Suggested Priority Order

1. Wire up the toolchain in Docker (make cross-compilation actually work)
2. Get a single end-to-end build working for one package on one platform
3. Add artifact storage (S3, GitHub Releases, or a Hex-compatible repo)
4. Implement the consumer side (`mix deps.get_built` actually fetching artifacts)
5. Add NIF/Port detection
6. CI/CD automation
7. Expand platform coverage
