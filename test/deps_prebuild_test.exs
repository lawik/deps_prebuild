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

  @tag :tmp_dir
  test "fetch hex package", %{tmp_dir: tmp_dir} do
    result = DepsPrebuild.search("", 1)
    assert {:ok, stuff} = result
    
    stuff
    |> Enum.map(fn pkg ->
      assert %{"name" => name, "latest_stable_version" => version} = pkg

      assert {:ok, tarball} = DepsPrebuild.download(name, version)
      pkg_path = Path.join(tmp_dir, "pkg.tgz")
      unpack_path = Path.join(tmp_dir, "pkg")
      File.mkdir_p!(unpack_path)
      File.write!(pkg_path, tarball)

      assert :ok = DepsPrebuild.unpack(pkg_path, unpack_path)
      dbg(File.ls!(unpack_path) |> Enum.map(& {&1, File.stat!(Path.join(unpack_path, &1))}))
      #dbg(File.read!(Path.join(unpack_path, "metadata.config")))

      contents_path = Path.join(unpack_path, "contents")
      File.mkdir_p!(contents_path)

      assert :ok = DepsPrebuild.unpack(Path.join(unpack_path, "contents.tar.gz"), contents_path)
      dbg(contents_path)
      dbg(File.ls!(unpack_path))
      dbg(File.ls!(contents_path))

      mix_dir = contents_path
      IO.puts("Getting deps for #{name}")
      assert {_, 0} = System.shell("mix deps.get", cd: mix_dir)
      IO.puts("Compiling #{name}")
      assert {_, 0} = System.shell("mix compile", cd: mix_dir)
    end)
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
