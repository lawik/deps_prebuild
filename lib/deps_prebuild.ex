defmodule DepsPrebuild do
  alias DepsPrebuild.Build
  require Logger

  @gcc_version "v13.2.0"

  # No musl is not a problem for us. We are using the nerves cross-compilation tool-chains
  @oses [
    # :windows,
    # :macos,
    :linux
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

  @dh_namespace "hexpm"
  @dh_repo "elixir"
  @dh_page_size 100

  def docker_hub_find_tag(prefix) do
    "https://hub.docker.com/v2/namespaces/#{@dh_namespace}/repositories/#{@dh_repo}/tags?page=1&page_size=100"
    |> docker_hub_find(prefix)
  end

  defp docker_hub_find(url, prefix) do
    with {:ok, %{body: %{"results" => results}} = meta} <- Req.get(url) do
      find =
        Enum.find(results, fn %{"name" => name} ->
          String.starts_with?(name, prefix)
        end)

      case find do
        %{"name" => name} ->
          {:ok, name}

        nil ->
          if meta["next"] do
            docker_hub_find(meta["next"], prefix)
          else
            {:error, :no_match}
          end
      end
    end
  end

  def combinations do
    os_arch_combos =
      @arch_and_os |> Enum.map(fn {_os, arches} -> Enum.count(arches) end) |> Enum.sum()

    os_arch_combos * Enum.count(@libcs) * Enum.count(@mix_envs)
  end

  def pack(dir, archive_name) do
    files =
      dir
      |> Path.join("**")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(fn abs_path ->
        rel_path = Path.relative_to(abs_path, dir)
        {to_charlist(rel_path), to_charlist(abs_path)}
      end)

    :erl_tar.create("#{archive_name}.tar.gz", files, [:compressed])
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

      with {:ok, build} <- download_to(build),
           {:ok, build} <- unpack_and_verify(build),
           {:ok, build} <- check_package_type(build),
           build = detect_native(build),
           {:ok, build} <- build_package(build),
           {:ok, build} <- extract_build(build),
           {:ok, build} <- package_build(build) do
        native_label = if build.native, do: " (native: #{inspect(build.native_reasons)})", else: " (pure)"
        IO.puts("Finished building #{name} @ #{version}#{native_label}")
        IO.puts("Build at: #{build.built_dir}")
        IO.puts("Done ##{index + 1}")
        :ok
      else
        {:skip, reason} ->
          IO.puts("Skipping package #{name} @ #{version}, unusual setup: #{reason}")

        e ->
          Logger.error("Build failed for #{name} @ #{version}: #{inspect(e)}")
          {:error, e}
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

  def download_to(%Build{} = b) do
    with {:ok, tarball} <- download(b.package_name, b.package_version) do
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
          Logger.warning("Unrecognized package layout, files: #{inspect(files)}")
          {:error, :no_project_file}
      end
    end
  end

  def detect_native(%Build{} = b) do
    case DepsPrebuild.NifDetector.detect(b.contents_dir) do
      :pure ->
        %Build{b | native: false, native_reasons: []}

      {:native, reasons} ->
        %Build{b | native: true, native_reasons: reasons}
    end
  end

  def build_package(%Build{package_type: :elixir} = b) do
    dockerfile = if b.native, do: "docker/Dockerfile-elixir", else: "docker/Dockerfile-elixir-pure"
    do_docker_build(b, dockerfile)
  end

  def build_package(%Build{package_type: :erlang} = b) do
    dockerfile = if b.native, do: "docker/Dockerfile-erlang", else: "docker/Dockerfile-erlang-pure"
    do_docker_build(b, dockerfile)
  end

  defp do_docker_build(b, dockerfile) do
    id = "d#{System.unique_integer([:positive])}"
    built_dir = Path.join(b.unpacked_dir, "_build")
    b = Build.set_built_dir(b, built_dir)

    with :ok <- docker_build(b, dockerfile, id),
         :ok <- docker_create(id),
         :ok <- docker_cp(id, built_dir),
         :ok <- docker_rm(id),
         :ok <- docker_rmi(id) do
      {:ok, b}
    end
  end

  def extract_build(%Build{built_dir: base} = b) do
    entries =
      base
      |> Path.join("/**/#{b.package_name}")
      |> Path.wildcard()

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
    token_args =
      case System.get_env("GITHUB_API_TOKEN") do
        nil -> []
        token -> ["--build-arg", "GITHUB_API_TOKEN=#{token}"]
      end

    args =
      [
        "build",
        "-f",
        dockerfile,
        "--tag",
        "#{id}-image",
        "--progress=plain"
      ] ++
        token_args ++
        Build.docker_build_args(b) ++
        [
          b.contents_dir
        ]

    # Log command without secrets
    safe_args = Enum.map(args, fn
      "GITHUB_API_TOKEN=" <> _ -> "GITHUB_API_TOKEN=***"
      arg -> arg
    end)

    IO.puts("docker #{Enum.join(safe_args, " ")}")

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
        {:error, {:docker_cp_failed, status}}
    end
  end

  def docker_rm(id) do
    case System.cmd("docker", ["rm", "#{id}-container"]) do
      {_, 0} ->
        :ok

      {out, status} ->
        Logger.error("Failed during docker rm with status #{status}: #{out}")
        {:error, {:docker_rm_failed, status}}
    end
  end

  def docker_rmi(id) do
    case System.cmd("docker", ["rmi", "#{id}-image"]) do
      {_, 0} ->
        :ok

      {out, _status} ->
        Logger.warning("Failed to remove docker image #{id}-image: #{out}")
        # Non-fatal - image cleanup is best-effort
        :ok
    end
  end

  def build_elixir(project_dir) do
    with {:deps, {_, 0}} <- {:deps, System.cmd("mix", ["deps.get"], cd: project_dir)},
         {:compile, {_, 0}} <- {:compile, System.cmd("mix", ["compile"], cd: project_dir)} do
      :ok
    else
      {:deps, {out, status}} ->
        Logger.error("Running 'mix deps.get' failed with status #{status}: #{out}")
        {:error, {:mix_deps_get, status}}

      {:compile, {out, status}} ->
        Logger.error("Running 'mix compile' failed with status #{status}: #{out}")
        {:error, {:mix_compile, status}}
    end
  end

  def build_erlang(project_dir) do
    case find_rebar_via_asdf() do
      rebar_path when is_binary(rebar_path) ->
        case System.cmd(rebar_path, ["compile"], cd: project_dir) do
          {_, 0} ->
            :ok

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
end
