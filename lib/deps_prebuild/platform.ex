defmodule DepsPrebuild.Platform do
  @moduledoc """
  Detects the current platform: OS, architecture, OTP version.
  """

  def os do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:win32, :nt} -> :windows
    end
  end

  def arch do
    :erlang.system_info(:system_architecture)
    |> to_string()
    |> parse_arch()
  end

  defp parse_arch("x86_64" <> _), do: :x86_64
  defp parse_arch("aarch64" <> _), do: :aarch64
  defp parse_arch("arm" <> rest) do
    cond do
      String.contains?(rest, "v7") -> :armv7
      String.contains?(rest, "v6") -> :armv6
      true -> :armv5
    end
  end

  def otp_version do
    [:code.root_dir(), "releases", :erlang.system_info(:otp_release), "OTP_VERSION"]
    |> Path.join()
    |> File.read!()
    |> String.trim()
  end

  def libc do
    case os() do
      :linux -> detect_linux_libc()
      _ -> nil
    end
  end

  defp detect_linux_libc do
    case System.cmd("ldd", ["--version"], stderr_to_stdout: true) do
      {output, _} ->
        if String.contains?(output, "musl") do
          :musl
        else
          :gnu
        end
    end
  rescue
    _ -> :gnu
  end
end
