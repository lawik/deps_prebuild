defmodule DepsPrebuild do
  def pack(dir, archive_name) do
    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.map(&to_charlist/1)
    |> then(fn filenames -> 
      :erl_tar.create("#{archive_name}.tar.gz", filenames, compressed: true)
    end)
  end

  def unpack(archive_path, new_dir) do
    File.mkdir_p!(new_dir)

    :erl_tar.extract(archive_path, cwd: new_dir, compressed: true)
  end
  
  
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
