defmodule DepsPrebuildTest do
  use ExUnit.Case
  #doctest DepsPrebuild

  @tag :tmp_dir
  test "compress and decompress the Jason library", %{tmp_dir: tmp_dir} do
    target_file = Path.join(tmp_dir, "jason")

    DepsPrebuild.pack("_build/test/lib/jason", target_file)

    out_dir = Path.join(tmp_dir, "unpacked")

    DepsPrebuild.unpack(target_file, out_dir)
  end
  
  # @tag :tmp_dir
  # test "compress and decompress file streaming", %{tmp_dir: tmp_dir} do
  #   data = File.read!("mix.exs")
  #   filepath = Path.join(tmp_dir, "hello.txt")

  #   filepath
  #   |> File.write!(data)

  #   to_filepath = Path.join(tmp_dir, "hello.zst")

  #   filepath
  #   |> File.stream!([], 2048)
  #   |> DepsPrebuild.compress_stream()
  #   |> Stream.into(File.stream!(to_filepath))
  #   |> Stream.run()

  #   compressed = File.read!(to_filepath)
  #   assert data != compressed

  #   new_filepath = Path.join(tmp_dir, "hello-again.txt")

  #   to_filepath
  #   |> File.stream!([], 2048)
  #   |> DepsPrebuild.decompress_stream()
  #   |> Stream.into(File.stream!(new_filepath))
  #   |> Stream.run()

  #   uncompressed = File.read!(new_filepath)
  #   assert data == uncompressed
  # end
end
