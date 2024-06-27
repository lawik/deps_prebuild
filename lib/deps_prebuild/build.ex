defmodule DepsPrebuild.Build do
  defstruct package_name: nil,
            package_version: nil,
            package_type: nil,
            elixir_version: nil,
            otp_version: nil,
            arch: nil,
            os: nil,
            gcc_version: nil,
            libc: nil,
            mix_env: nil,
            hex_package_path: nil,
            unpacked_dir: nil,
            contents_dir: nil,
            built_dir: nil

  alias __MODULE__, as: B

  def new() do
    %B{}
  end

  def set_package_name(%B{} = b, package_name) do
    %B{b | package_name: package_name}
  end

  def set_package_version(%B{} = b, package_version) do
    %B{b | package_version: package_version}
  end

  def set_package_type(%B{} = b, package_type) do
    %B{b | package_type: package_type}
  end

  def set_elixir_version(%B{} = b, elixir_version) do
    %B{b | elixir_version: elixir_version}
  end

  def set_otp_version(%B{} = b, otp_version) do
    %B{b | otp_version: otp_version}
  end

  def set_arch(%B{} = b, arch) do
    %B{b | arch: arch}
  end

  def set_os(%B{} = b, os) do
    %B{b | os: os}
  end

  def set_gcc_version(%B{} = b, gcc_version) do
    %B{b | gcc_version: gcc_version}
  end

  def set_libc(%B{} = b, libc) do
    %B{b | libc: libc}
  end

  def set_mix_env(%B{} = b, mix_env) do
    %B{b | mix_env: mix_env}
  end

  def set_hex_package_path(%B{} = b, hex_package_path) do
    %B{b | hex_package_path: hex_package_path}
  end

  def set_unpacked_dir(%B{} = b, unpacked_dir) do
    %B{b | unpacked_dir: unpacked_dir}
  end

  def set_contents_dir(%B{} = b, contents_dir) do
    %B{b | contents_dir: contents_dir}
  end

  def set_built_dir(%B{} = b, built_dir) do
    %B{b | built_dir: built_dir}
  end

  def docker_build_args(%B{} = b) do
    [
      "--build-arg",
      "ELIXIR_VERSION=#{b.elixir_version}",
      "--build-arg",
      "OTP_VERSION=#{b.otp_version}",
      "--build-arg",
      "ARCH=#{b.arch}",
      "--build-arg",
      "GCC_VERSION=#{b.gcc_version}",
      "--build-arg",
      "LIBC=#{b.libc}",
      "--build-arg",
      "MIX_ENV=#{b.mix_env}"
    ]
  end

  def tag(%B{} = b) do
    "#{b.package_name}-#{b.package_version}-#{b.mix_env}-elixir-#{b.elixir_version}-otp-#{b.otp_version}-#{b.os}-#{b.arch}-#{b.libc}"
  end
end
