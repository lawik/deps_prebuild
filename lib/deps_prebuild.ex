defmodule DepsPrebuild do
  require Logger

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
    |> dbg()
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
    File.mkdir_p!(dir)
    IO.inspect(Enum.count(results), label: "results")
    # Enum.map(results, fn package ->
    #   %{"name" => name, "latest_stable_version" => version} = package
    #   IO.puts("Trying to download and build #{name} @ #{version}...")
    #   pkg_path = Path.join(dir, "#{name}.tar.gz")
    #   unpack_path = Path.join(dir, name)
    #   File.mkdir_p!(unpack_path)
    #   with :ok <- download_to(name, version, pkg_path) |> dbg(),
    #        {:ok, contents_dir} <- unpack_and_verify(pkg_path, unpack_path) |> dbg(),
    #        :ok <- build_package(contents_dir) |> dbg() do
    #     IO.puts("Finished building #{name} @ #{version}")
    #     :ok
    #   else
    #     e ->
    #       dbg(e)
    #       raise "failed"
    #   end
      
    # end)
  end
  

  def download(package, version) do
    config = :hex_core.default_config()

    case :hex_repo.get_tarball(config, package, version) do
      {:ok, {200, _, tarball}} -> {:ok, tarball}
      {:error, reason} -> {:error, reason}
    end
  end

  def download_to(package, version, filepath) do
    with {:ok, tarball} <- download(package, version) do
      File.write(filepath, tarball)
    end
  end

  def unpack_and_verify(filepath, target_dir) do
    with :ok <- unpack(filepath, target_dir) do
      if hash_fileset(target_dir) == File.read!(Path.join(target_dir, "CHECKSUM")) do
        with {:ok, contents_dir} <- unpack_contents(target_dir) do
          {:ok, contents_dir}
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

  def build_package(contents_dir) do
    with {:ok, files} <- File.ls(contents_dir) do
      cond do
        "mix.exs" in files ->
          build_elixir(contents_dir)
        "rebar.config" in files ->
          build_erlang(contents_dir)
        "rebar.lock" in files ->
          build_erlang(contents_dir)
        "erlang.mk" in files ->
          build_erlang(contents_dir)
        true ->
          dbg(files)
          {:error, :no_project_file}
      end
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
    |> Enum.find(& String.contains?(&1, "rebar3"))
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
