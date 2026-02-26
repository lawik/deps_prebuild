defmodule DepsPrebuild.NifDetector do
  @moduledoc """
  Detects whether a package contains NIFs that require native compilation.

  Packages without NIFs produce pure BEAM bytecode that is portable across
  all architectures. These only need to be built once per Elixir/OTP version
  and mix_env, not per-architecture.

  Packages with NIFs compile native C/Rust code and need platform-specific
  builds for each architecture/os/libc combination.

  Note: Port.open/open_port usage is NOT a native compilation indicator.
  Ports spawn external programs at runtime but don't affect compilation.
  Similarly, a Makefile alone isn't an indicator - many Erlang packages
  use erlang.mk which has a Makefile for compiling .erl files, not C code.
  """

  @doc """
  Checks a package's unpacked contents directory for NIF indicators.

  Returns:
    - `:pure` - no native code detected, BEAM files are portable
    - `{:native, reasons}` - native code detected, with list of reasons
  """
  def detect(contents_dir) do
    reasons =
      []
      |> check_c_src(contents_dir)
      |> check_nif_calls(contents_dir)
      |> check_native_compiler(contents_dir)

    case reasons do
      [] -> :pure
      reasons -> {:native, Enum.uniq(reasons)}
    end
  end

  # c_src/ directory is the conventional location for NIF C/C++ code
  defp check_c_src(reasons, contents_dir) do
    if File.dir?(Path.join(contents_dir, "c_src")) do
      [:c_src_dir | reasons]
    else
      reasons
    end
  end

  # Scan Elixir/Erlang source for :erlang.load_nif or erlang:load_nif
  defp check_nif_calls(reasons, contents_dir) do
    nif_patterns = [
      ~r/:erlang\.load_nif/,
      ~r/erlang:load_nif/
    ]

    source_files = find_source_files(contents_dir)

    has_nif =
      Enum.any?(source_files, fn file ->
        content = File.read!(file)
        Enum.any?(nif_patterns, &Regex.match?(&1, content))
      end)

    if has_nif do
      [:nif_call | reasons]
    else
      reasons
    end
  end

  # Check mix.exs for native compilation tools
  defp check_native_compiler(reasons, contents_dir) do
    mix_exs = Path.join(contents_dir, "mix.exs")

    if File.exists?(mix_exs) do
      content = File.read!(mix_exs)

      native_compilers = [
        ~r/:elixir_make/,
        ~r/:rustler/,
        ~r/:zigler/,
        ~r/:cmake/,
        ~r/compilers:.*:elixir_make/
      ]

      has_native_compiler = Enum.any?(native_compilers, &Regex.match?(&1, content))

      if has_native_compiler do
        [:native_compiler | reasons]
      else
        reasons
      end
    else
      reasons
    end
  end

  defp find_source_files(dir) do
    Path.join([dir, "**", "*.{ex,erl,exs}"])
    |> Path.wildcard()
  end
end
