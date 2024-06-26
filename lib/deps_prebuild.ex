defmodule DepsPrebuild do
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

  def download(package, version) do
    config = :hex_core.default_config()
    case :hex_repo.get_tarball(config, package, version) do
      {:ok, {200, _, tarball}} -> {:ok, tarball}
      {:error, reason} -> {:error, reason}
    end
    

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
