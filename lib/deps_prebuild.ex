defmodule DepsPrebuild do
  alias DepsPrebuild.Build
  require Logger

  @gcc_version "v13.2.0"

  # No musl is not a problem for us. We are using the nerves cross-compilation tool-chains
  @oses [
    # :windows,
    :macos
    # :linux
  ]
  @architectures [:x86_64, :armv5, :armv6, :armv7, :aarch64]
  @arch_and_os [
    windows: [:x86_64],
    macos: [:aarch64],
    linux: @architectures
  ]

  @libcs [
    :gnu,
    :musl
  ]
  @mix_envs [:prod, :dev, :test]

  @sample_packages %{
                     # Plain Elixir package
                     jason: "1.4.3",
                     # Elixir package with C/C++ NIF, precompiled
                     evision: "0.2.7",
                     # Elixir package with Rustler NIF, precompiled
                     explorer: "0.8.3",
                     # Erlang with NIF
                     jiffy: "1.1.2",
                     # Plain Erlang package
                     telemetry: "1.2.1",
                     # Plain Erlang package, with plugins
                     hex_core: "0.10.3",
                     # Tricky ones with good spread of usage
                     comeonin: "5.4.0",
                     bcrypt_elixir: "3.1.0",
                     circuits_uart: "1.5.2"
                   }
                   |> Enum.map(fn {n, v} ->
                     %{"name" => to_string(n), "latest_stable_version" => v}
                   end)

  def combinations do
    os_arch_combos =
      @arch_and_os |> Enum.map(fn {_os, arches} -> Enum.count(arches) end) |> Enum.sum()

    os_arch_combos * Enum.count(@libcs) * Enum.count(@mix_envs)
  end

  def build_matrix(
        elixir_versions,
        otp_versions,
        arches,
        oses,
        gcc_versions,
        libcs,
        mix_envs
      ) do
    for elixir_version <- elixir_versions,
        otp_version <- otp_versions,
        arch <- arches,
        os <- oses,
        gcc_version <- gcc_versions,
        libc <- libcs,
        mix_env <- mix_envs,
        into: %{} do
      {"#{mix_env}-elixir-#{elixir_version}-otp-#{otp_version}-#{os}-#{arch}-#{libc}-gcc-#{gcc_version}",
       new(elixir_version, otp_version, gcc_version, arch, os, libc, mix_env)}
    end
  end

  def pack(dir, archive_name) do
    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.map(&to_charlist/1)
    |> then(fn filenames ->
      :erl_tar.create("#{archive_name}.tar.gz", filenames, [:compressed])
    end)
  end

  def unpack(archive_path, new_dir) do
    File.mkdir_p!(new_dir)

    :erl_tar.extract(archive_path, [{:cwd, new_dir}, :compressed])
  end

  def search(search, page, sort \\ "recent_downloads") do
    query_string = :hex_api.encode_query_string(search: search, page: page, sort: sort)
    config = :hex_core.default_config()

    path =
      config
      |> :hex_api.build_repository_path(["packages"])
      |> :hex_api.join_path_segments()

    url = <<path::binary, "?", query_string::binary>>

    case :hex_api.get(config, url) do
      {:ok, {_status, _headers, body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  def new(elixir_version, otp_version, gcc_version, arch, os, libc, mix_env) do
    Build.new()
    |> Build.set_elixir_version(elixir_version)
    |> Build.set_otp_version(otp_version)
    |> Build.set_gcc_version(gcc_version)
    |> Build.set_arch(arch)
    |> Build.set_os(os)
    |> Build.set_libc(libc)
    |> Build.set_mix_env(mix_env)
  end

  def reset_base_dir(%Build{} = b, base_dir) do
    b = Build.set_base_dir(b, base_dir)
    File.rm_rf(base_dir)
    File.mkdir_p!(base_dir)
    b
  end

  def with_package(%Build{} = b, package_name, package_version) do
    b
    |> Build.set_package_name(package_name)
    |> Build.set_package_version(package_version)
  end

  def download_and_build(%Build{package_name: name, package_version: version} = build) do
    with {:ok, build} <- download_to(build),
         {:ok, build} <- unpack_and_verify(build),
         {:ok, build} <- check_package_type(build),
         {:ok, build} <- build_package(build),
         {:ok, build} <- extract_build(build),
         {:ok, build} <- package_build(build) do
      IO.puts("Finished building #{name} @ #{version}")
      IO.puts("Build at: #{build.built_dir}")
      {:ok, build}
    else
      {:skip, reason} ->
        IO.puts("Skipping package #{name} @ #{version}, unusual setup: #{reason}")

      e ->
        dbg(e)
        raise "failed"
    end
  end

  def mac do
    # {:ok, results} = search("", 1)
    dir = "/tmp/mac"
    File.rm_rf(dir)
    File.mkdir_p!(dir)

    build =
      Build.new()
      |> Build.set_elixir_version("1.17.1")
      |> Build.set_otp_version("26.2.5.1")
      |> Build.set_gcc_version(@gcc_version)
      |> Build.set_arch(:aarch64)
      |> Build.set_os(:macos)
      |> Build.set_libc(:gnu)
      |> Build.set_mix_env(:prod)

    # results
    @sample_packages
    |> Enum.with_index()
    |> Enum.map(fn {package, index} ->
      %{"name" => name, "latest_stable_version" => version} = package

      build =
        build
        |> Build.set_package_name(name)
        |> Build.set_package_version(version)

      IO.puts("Trying to download and build #{name} @ #{version}...")
      pkg_path = Path.join(dir, "#{name}.tar.gz")
      build = Build.set_hex_package_path(build, pkg_path)
      unpack_path = Path.join(dir, name)
      build = Build.set_unpacked_dir(build, unpack_path)
      File.mkdir_p!(unpack_path)

      with {:ok, build} <- download_to(build),
           {:ok, build} <- unpack_and_verify(build),
           {:ok, build} <- check_package_type(build),
           {:ok, build} <- build_package(build),
           {:ok, build} <- extract_build(build),
           {:ok, build} <- package_build(build) do
        IO.puts("Finished building #{name} @ #{version}")
        IO.puts("Build at: #{build.built_dir}")
        IO.puts("Done ##{index + 1}")
        :ok
      else
        {:skip, reason} ->
          IO.puts("Skipping package #{name} @ #{version}, unusual setup: #{reason}")

        e ->
          dbg(e)
          raise "failed"
      end
    end)
  end

  def p1 do
    {:ok, results} = search("", 1)
    dir = "/tmp/p1"
    File.rm_rf(dir)
    File.mkdir_p!(dir)

    build =
      Build.new()
      |> Build.set_elixir_version("1.17.1")
      |> Build.set_otp_version("26.2.5.1")
      |> Build.set_gcc_version(@gcc_version)
      |> Build.set_arch(:x86_64)
      |> Build.set_os(:linux)
      |> Build.set_libc(:gnu)
      |> Build.set_mix_env(:prod)

    results
    # |> Enum.take(5)
    |> Enum.with_index()
    |> Enum.map(fn {package, index} ->
      %{"name" => name, "latest_stable_version" => version} = package

      build =
        build
        |> Build.set_package_name(name)
        |> Build.set_package_version(version)

      IO.puts("Trying to download and build #{name} @ #{version}...")
      pkg_path = Path.join(dir, "#{name}.tar.gz")
      build = Build.set_hex_package_path(build, pkg_path)
      unpack_path = Path.join(dir, name)
      build = Build.set_unpacked_dir(build, unpack_path)
      File.mkdir_p!(unpack_path)

      with {:ok, build} <- download_to(build) |> dbg(),
           {:ok, build} <- unpack_and_verify(build) |> dbg(),
           {:ok, build} <- check_package_type(build) |> dbg(),
           {:ok, build} <- build_package(build),
           {:ok, build} <- extract_build(build),
           {:ok, build} <- package_build(build) do
        IO.puts("Finished building #{name} @ #{version}")
        IO.puts("Build at: #{build.built_dir}")
        IO.puts("Done ##{index + 1}")
        :ok
      else
        {:skip, reason} ->
          IO.puts("Skipping package #{name} @ #{version}, unusual setup: #{reason}")

        e ->
          dbg(e)
          raise "failed"
      end
    end)
  end

  def download(package, version) do
    config = :hex_core.default_config()

    case :hex_repo.get_tarball(config, package, version) do
      {:ok, {200, _, tarball}} -> {:ok, tarball}
      {:error, reason} -> {:error, reason}
    end
  end

  def download_to(%Build{package_name: name, package_version: version, base_dir: dir} = b) do
    pkg_path = Path.join(dir, "#{name}.tar.gz")
    b = Build.set_hex_package_path(b, pkg_path)
    unpack_path = Path.join(dir, name)
    b = Build.set_unpacked_dir(b, unpack_path)
    File.mkdir_p!(unpack_path)

    with {:ok, tarball} <- download(name, version) do
      File.write(b.hex_package_path, tarball)
      {:ok, b}
    end
  end

  def unpack_and_verify(%Build{} = b) do
    with :ok <- unpack(b.hex_package_path, b.unpacked_dir) do
      if hash_fileset(b.unpacked_dir) == File.read!(Path.join(b.unpacked_dir, "CHECKSUM")) do
        with {:ok, contents_dir} <- unpack_contents(b.unpacked_dir) do
          {:ok, Build.set_contents_dir(b, contents_dir)}
        end
      else
        {:error, :contents_checksum_failed}
      end
    end
  end

  defp unpack_contents(from_dir) do
    to_dir = Path.join(from_dir, "contents")
    File.mkdir_p!(to_dir)

    with :ok <- unpack(Path.join(from_dir, "contents.tar.gz"), to_dir) do
      {:ok, to_dir}
    end
  end

  def check_package_type(%Build{} = b) do
    with {:ok, files} <- File.ls(b.contents_dir) do
      cond do
        "mix.exs" in files ->
          {:ok, Build.set_package_type(b, :elixir)}

        "rebar.config" in files ->
          {:ok, Build.set_package_type(b, :erlang)}

        "rebar.lock" in files ->
          {:ok, Build.set_package_type(b, :erlang)}

        "erlang.mk" in files ->
          {:ok, Build.set_package_type(b, :erlang)}

        true ->
          dbg(files)
          {:error, :no_project_file}
      end
    end
  end

  # docker create --name dummy IMAGE_NAME
  # docker cp dummy:/path/to/file /dest/to/file
  # docker rm -f dummy
  def build_package(%Build{os: :linux, package_type: :elixir} = b) do
    id = "d#{System.unique_integer([:positive])}"
    built_dir = Path.join(b.unpacked_dir, "_build")
    b = Build.set_built_dir(b, built_dir)

    with :ok <- docker_build(b, "docker/Dockerfile-elixir", id),
         :ok <- docker_create(id),
         :ok <- docker_cp(id, built_dir),
         :ok <- docker_rm(id) do
      {:ok, b}
    end
  end

  def build_package(%Build{os: :linux, package_type: :erlang} = b) do
    id = "d#{System.unique_integer([:positive])}"
    built_dir = Path.join(b.unpacked_dir, "_build")
    b = Build.set_built_dir(b, built_dir)

    with :ok <- docker_build(b, "docker/Dockerfile-erlang", id),
         :ok <- docker_create(id),
         :ok <- docker_cp(id, built_dir),
         :ok <- docker_rm(id) do
      {:ok, b}
    end
  end

  # @mac_nerves_toolchain "v13.2.0-aarch64-nerves-macos-gnu"
  def build_package(%Build{os: :macos, package_type: :elixir} = b) do
    # id = "d#{System.unique_integer([:positive])}"
    built_dir = Path.join(b.unpacked_dir, "_build")
    b = Build.set_built_dir(b, built_dir)

    Logger.info("Building package #{b.package_name} @ #{b.package_version} in #{b.contents_dir}")
    prepare_asdf(b.contents_dir, b.elixir_version, b.otp_version)

    with {:ok, b} <- build_elixir(b) do
      {:ok, b}
    end
  end

  def build_package(%Build{os: :macos, package_type: :erlang} = b) do
    # id = "d#{System.unique_integer([:positive])}"
    built_dir = Path.join(b.unpacked_dir, "_build")
    b = Build.set_built_dir(b, built_dir)

    with {:ok, b} <- build_erlang(b) do
      {:ok, b}
    end
  end

  def extract_build(%Build{built_dir: base} = b) do
    entries =
      base
      |> Path.join("/**/#{b.package_name}")
      |> Path.wildcard()
      |> dbg()

    case entries do
      [artifact_dir] ->
        b = Build.set_artifact_dir(b, artifact_dir)
        # Remove any consolidated protocols, the rest should be okay
        File.rm_rf(Path.join(artifact_dir, "consolidated"))
        {:ok, b}

      [] ->
        Logger.error("Found no artifact folders.")
        {:skip, :artifacts_not_found}

      artifacts ->
        Logger.warning(
          "Skipping unusual package. Found multiple artifact folders: #{inspect(artifacts)}"
        )

        {:skip, :multiple_artifacts}
    end
  end

  def package_build(%Build{} = b) do
    built_package_path = Path.join(b.unpacked_dir, Build.tag(b))

    case pack(b.artifact_dir, built_package_path) do
      :ok ->
        b = Build.set_built_package_path(b, built_package_path)
        {:ok, b}

      {:error, reason} ->
        {:error, {:package_build_failed, reason}}
    end
  end

  def docker_build(%Build{} = b, dockerfile, id) do
    args =
      [
        "build",
        "-f",
        dockerfile,
        "--tag",
        "#{id}-image",
        "--progress=plain",
        "--build-arg",
        "GITHUB_API_TOKEN=#{System.get_env("GITHUB_API_TOKEN")}"
      ] ++
        Build.docker_build_args(b) ++
        [
          b.contents_dir
        ]

    IO.puts("docker #{Enum.join(args, " ")}")

    case System.cmd("docker", args) do
      {_, 0} ->
        :ok

      {out, status} ->
        Logger.error("Failed during docker build with status #{status}: #{out}")
        {:error, {:docker_build_failed, status}}
    end
  end

  def docker_create(id) do
    case System.cmd("docker", ["create", "--name", "#{id}-container", "#{id}-image"]) do
      {_, 0} ->
        :ok

      {out, status} ->
        Logger.error("Failed during docker create with status #{status}: #{out}")
        {:error, {:docker_create_fail, status}}
    end
  end

  def docker_cp(id, built_dir) do
    case System.cmd("docker", ["cp", "#{id}-container:/build/_build", built_dir]) do
      {_, 0} ->
        :ok

      {out, status} ->
        Logger.error("Failed during docker cp with status #{status}: #{out}")
        {:error, {:docker_create_fail, status}}
    end
  end

  def docker_rm(id) do
    case System.cmd("docker", ["rm", "#{id}-container"]) do
      {_, 0} ->
        :ok

      {out, status} ->
        Logger.error("Failed during docker rm with status #{status}: #{out}")
        {:error, {:docker_create_fail, status}}
    end
  end

  def prepare_asdf(project_dir, elixir_version, erlang_version) do
    File.write(
      Path.join(project_dir, ".tool-versions"),
      """
      elixir #{elixir_version}
      erlang #{erlang_version}
      """
    )
  end

  def build_elixir(%Build{} = b) do
    built_dir = Path.join(b.contents_dir, "_build")
    b = Build.set_built_dir(b, built_dir)

    with {:asdf, {_, 0}} <- {:asdf, System.cmd("asdf", ["install"], cd: b.contents_dir)},
         {:deps, {_, 0}} <- {:deps, System.cmd("mix", ["deps.get"], cd: b.contents_dir)},
         {:compile, {_, 0}} <- {:compile, System.cmd("mix", ["compile"], cd: b.contents_dir)} do
      {:ok, b}
    else
      {:asdf, {out, status}} ->
        Logger.error("Running 'asdf install' failed with status #{status}: #{out}")
        {:error, {:asdf_install, status}}

      {:deps, {out, status}} ->
        Logger.error("Running 'mix deps.get' failed with status #{status}: #{out}")
        {:error, {:mix_deps_get, status}}

      {:compile, {out, status}} ->
        Logger.error("Running 'mix compile' failed with status #{status}: #{out}")
        {:error, {:mix_compile, status}}
    end
  end

  def build_erlang(%Build{} = b) do
    built_dir = Path.join(b.contents_dir, "_build")
    b = Build.set_built_dir(b, built_dir)

    case find_rebar_via_asdf() do
      rebar_path when is_binary(rebar_path) ->
        case System.cmd(rebar_path, ["compile"], cd: b.contents_dir) do
          {_, 0} ->
            {:ok, b}

          {out, status} ->
            Logger.error("Running '#{rebar_path} compile' failed with status #{status}: #{out}")
            {:error, {:rebar_compile, status}}
        end

      nil ->
        {:error, :rebar_not_found}
    end
  end

  def hash_fileset(path) do
    binary =
      for filename <- ["VERSION", "metadata.config", "contents.tar.gz"], into: <<>> do
        path
        |> Path.join(filename)
        |> File.read!()
      end

    :sha256 |> :crypto.hash(binary) |> Base.encode16() |> String.upcase()
  end

  def find_rebar_via_asdf() do
    # Ensure installed if not already
    System.cmd("mix", ["local.rebar", "--if-missing", "--force"])
    {elixir_path, 0} = System.cmd("asdf", ["where", "elixir"])

    elixir_path
    |> String.trim()
    |> Path.join([".mix/**"])
    |> Path.wildcard()
    |> Enum.find(&String.contains?(&1, "rebar3"))
  end

  #   search(Config, Query, SearchParams) when
  #     is_map(Config) and is_binary(Query) and is_list(SearchParams)
  # ->
  #     QueryString = hex_api:encode_query_string([{search, Query} | SearchParams]),
  #     Path = hex_api:join_path_segments(hex_api:build_repository_path(Config, ["packages"])),
  #     PathQuery = <<Path/binary, "?", QueryString/binary>>,
  #     hex_api:get(Config, PathQuery).

  # def tar(dir) do
  #   dir
  #   |> Path.join("**")
  #   |> Path.wildcard()
  #   |> then(fn filenames ->
  #     :erl_tar.create("")
  # end

  # def untar(filepath, new_dir) do

  # end

  # def compress_stream(stream) do
  #   # zst =
  #   #   ExZstd.cstream_new()
  #   #   |> ExZstd.cstream_init()
  #   stream
  #   |> StreamGzip.gzip()
  #   #|> Stream.map(fn chunk ->
  #     # {:ok, compressed} = ExZstd.stream_compress(zst, chunk)
  #   #  compressed
  #   #end)
  # end

  # def decompress_stream(stream) do
  #   # zst =
  #   #   ExZstd.dstream_new()
  #   #   |> ExZstd.dstream_init()

  #   stream
  #   #|> Stream.map(fn chunk ->
  #     # {:ok, decompressed} = ExZstd.stream_decompress(zst, chunk)
  #   #  decompressed
  #   #end)
  #   |> StreamGzip.gunzip()
  # end
end
