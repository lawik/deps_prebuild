defmodule DepsPrebuild.NifDetectorTest do
  use ExUnit.Case, async: true

  alias DepsPrebuild.NifDetector

  @tag :tmp_dir
  test "detects pure package (no native code)", %{tmp_dir: tmp_dir} do
    # Create a minimal Elixir package with no NIFs
    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule Pure.MixProject do
      use Mix.Project
      def project, do: [app: :pure, version: "1.0.0"]
    end
    """)

    File.mkdir_p!(Path.join(tmp_dir, "lib"))

    File.write!(Path.join([tmp_dir, "lib", "pure.ex"]), """
    defmodule Pure do
      def hello, do: :world
    end
    """)

    assert :pure = NifDetector.detect(tmp_dir)
  end

  @tag :tmp_dir
  test "detects NIF via c_src directory", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "c_src"))
    File.write!(Path.join([tmp_dir, "c_src", "nif.c"]), "// nif code")

    assert {:native, reasons} = NifDetector.detect(tmp_dir)
    assert :c_src_dir in reasons
  end

  @tag :tmp_dir
  test "detects NIF via erlang:load_nif call", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "lib"))

    File.write!(Path.join([tmp_dir, "lib", "nif_mod.ex"]), """
    defmodule NifMod do
      @on_load :load_nif
      def load_nif do
        :erlang.load_nif(:code.priv_dir(:nif_mod) ++ ~c"/nif_mod", 0)
      end
    end
    """)

    assert {:native, reasons} = NifDetector.detect(tmp_dir)
    assert :nif_call in reasons
  end

  @tag :tmp_dir
  test "detects NIF via Makefile", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "Makefile"), "all:\n\tgcc -o nif.so nif.c")

    assert {:native, reasons} = NifDetector.detect(tmp_dir)
    assert :makefile in reasons
  end

  @tag :tmp_dir
  test "detects native compiler in mix.exs (elixir_make)", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule Native.MixProject do
      use Mix.Project
      def project do
        [app: :native, version: "1.0.0", compilers: [:elixir_make] ++ Mix.compilers()]
      end
    end
    """)

    assert {:native, reasons} = NifDetector.detect(tmp_dir)
    assert :native_compiler in reasons
  end

  @tag :tmp_dir
  test "detects native compiler in mix.exs (rustler)", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule Native.MixProject do
      use Mix.Project
      def project do
        [app: :native, version: "1.0.0", deps: [{:rustler, "~> 0.30"}]]
      end
    end
    """)

    assert {:native, reasons} = NifDetector.detect(tmp_dir)
    assert :native_compiler in reasons
  end

  @tag :tmp_dir
  test "detects Port.open usage", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "lib"))

    File.write!(Path.join([tmp_dir, "lib", "port_mod.ex"]), """
    defmodule PortMod do
      def start do
        Port.open({:spawn, "echo hello"}, [:binary])
      end
    end
    """)

    assert {:native, reasons} = NifDetector.detect(tmp_dir)
    assert :port_call in reasons
  end

  @tag :tmp_dir
  test "detects CMakeLists.txt", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "CMakeLists.txt"), "cmake_minimum_required(VERSION 3.0)")

    assert {:native, reasons} = NifDetector.detect(tmp_dir)
    assert :makefile in reasons
  end
end
