defmodule DepsPrebuildTest do
  use ExUnit.Case
  # doctest DepsPrebuild

  @tag :tmp_dir
  test "create new project, compare prebuilds with regular", %{tmp_dir: tmp_dir} do
    p1 = Path.join(tmp_dir, "p1")
    p2 = Path.join(tmp_dir, "p2")
    File.cp_r!("test/fixtures/sample_project", p1)
    File.cp_r!("test/fixtures/sample_project", p2)
    dbg(p1)
    assert {_, 0} = System.cmd("mix", ["deps.get"], cd: p1)
    assert {_, 0} = System.cmd("mix", ["deps.compile"], cd: p1)

    prebuild_dir = Path.join(tmp_dir, "prebuild")

    build =
      DepsPrebuild.new(
        "1.17.1",
        "26.2.5.1",
        "v13.2.0",
        :aarch64,
        :macos,
        :gnu,
        :dev
      )
      |> DepsPrebuild.reset_base_dir(prebuild_dir)

    p2
    |> Path.join("mix.lock")
    |> Code.eval_file()
    |> Enum.map(fn {package_name, dep} ->
      version = elem(dep, 2)

      build =
        build
        |> DepsPrebuild.with_package(package_name, version)
        |> DepsPrebuild.download_and_build()

      built_dep_path = Path.join(p2, "_build/#{build.mix_env}/lib/#{package_name}")
      File.cp_r!(build.built_dir, built_dep_path)
    end)

    assert {_, 0} = System.cmd("mix", ["deps.get"], cd: p2)

    # Compare 'em
    p1_paths = Path.wildcard(Path.join(p1, "/**"))
    p2_paths = Path.wildcard(Path.join(p1, "/**"))

    refute Enum.any?(p1_paths, fn p1_path ->
             if p1_path not in p2_paths do
               dbg(p1_path)
               true
             else
               false
             end
           end)

    refute Enum.any?(p2_paths, fn p2_path ->
             if p2_path not in p1_paths do
               dbg(p2_path)
               true
             else
               false
             end
           end)
  end

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
    |> Enum.take(1)
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
