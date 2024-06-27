defmodule DepsPrebuildTest do
  use ExUnit.Case
  # doctest DepsPrebuild

  @tag :tmp_dir
  test "compress and decompress the Jason library", %{tmp_dir: tmp_dir} do
    target_file = Path.join(tmp_dir, "jason")

    DepsPrebuild.pack("_build/test/lib/jason", target_file)

    out_dir = Path.join(tmp_dir, "unpacked")

    DepsPrebuild.unpack(target_file, out_dir)
  end

  @tag :tmp_dir
  test "fetch hex package", %{tmp_dir: tmp_dir} do
    IO.puts("Searching hex for packages...")
    result = DepsPrebuild.search("", 1)
    IO.puts("Searched hex for packages")
    assert {:ok, stuff} = result

    {elixir_path, 0} = System.cmd("asdf", ["where", "elixir"])

    rebar_path =
      elixir_path
      |> String.trim()
      |> Path.join([".mix/**"])
      |> Path.wildcard()
      |> Enum.find(&String.contains?(&1, "rebar3"))
      |> dbg()

    stuff
    |> Enum.map(fn pkg ->
      dbg(pkg)
      assert %{"name" => name, "latest_stable_version" => version} = pkg

      IO.puts("Downloading #{name}...")
      assert {:ok, tarball} = DepsPrebuild.download(name, version)
      IO.puts("Downloaded #{name}")
      pkg_path = Path.join(tmp_dir, "#{name}.tgz")
      unpack_path = Path.join(tmp_dir, "#{name}")
      File.mkdir_p!(unpack_path)
      IO.puts("Writing #{name} tarball...")
      File.write!(pkg_path, tarball)
      IO.puts("Wrote #{name} tarball")

      IO.puts("Unpacking #{name} tarball...")
      assert :ok = DepsPrebuild.unpack(pkg_path, unpack_path)
      IO.puts("Unpacked #{name} tarball")
      # dbg(File.ls!(unpack_path) |> Enum.map(& {&1, File.stat!(Path.join(unpack_path, &1))}))
      # dbg(File.read!(Path.join(unpack_path, "metadata.config")))

      contents_path = Path.join(unpack_path, "contents")
      File.mkdir_p!(contents_path)

      IO.puts("Unpacking #{name} contents...")
      assert :ok = DepsPrebuild.unpack(Path.join(unpack_path, "contents.tar.gz"), contents_path)
      IO.puts("Unpacked #{name} contents")
      assert :ok = DepsPrebuild.unpack(Path.join(unpack_path, "contents.tar.gz"), contents_path)
      IO.inspect(contents_path, label: name)
      files = File.ls!(contents_path)
      project_dir = contents_path

      cond do
        "mix.exs" in files ->
          IO.puts("Getting deps for #{name}")
          assert {_, 0} = System.shell("mix deps.get", cd: project_dir)
          IO.puts("Compiling #{name}")
          assert {_, 0} = System.shell("mix compile", cd: project_dir)

        "rebar.lock" ->
          IO.puts("Compiling #{name}")
          IO.puts(rebar_path)
          assert {_, 0} = System.shell("#{rebar_path} compile", cd: project_dir)
      end

      # dbg(File.ls!(unpack_path))
      # dbg(File.ls!(contents_path))
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
