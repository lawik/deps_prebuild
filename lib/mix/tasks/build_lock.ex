defmodule Mix.Tasks.Deps.BuildLock do
  use Mix.Task

  alias DepsPrebuild.Build

  require Logger

  @shortdoc "Make builds for all deps in your lock file"

  @impl true
  def run(_args) do
    dir = "/tmp/deps_build_lock"
    File.rm_rf(dir)
    File.mkdir_p!(dir)

    build = Build.for_current_platform()

    "mix.lock"
    |> Code.eval_file()
    |> elem(0)
    |> Enum.map(fn {dep_name, dep} ->
      IO.puts(dep_name)

      case dep do
        {:hex, name, version, _hash, _, _, _, _} ->
          name = to_string(name)

          build =
            build
            |> Build.set_package_name(name)
            |> Build.set_package_version(version)

          pkg_path = Path.join(dir, "#{name}.tar.gz")
          build = Build.set_hex_package_path(build, pkg_path)

          with {:ok, build} <- DepsPrebuild.download_to(build) do
            Enum.map([:dev, :prod, :test], fn env ->
              env = to_string(env)
              build = Build.set_mix_env(build, env)
              unpack_path = Path.join([dir, env, name])
              File.mkdir_p!(unpack_path)
              build = Build.set_unpacked_dir(build, unpack_path)

              with {:ok, build} <- DepsPrebuild.unpack_and_verify(build),
                   {:ok, build} <- DepsPrebuild.check_package_type(build),
                   {:ok, build} <- DepsPrebuild.build_package(build),
                   {:ok, build} <- DepsPrebuild.extract_build(build),
                   {:ok, build} <- DepsPrebuild.package_build(build) do
                IO.puts("Finished building #{name} @ #{version} for #{env}")
                IO.puts("Build at: #{build.built_dir}")
              end
            end)
          end

        _ ->
          Logger.info("Not building #{dep_name} of type #{elem(dep, 0)}")
      end
    end)
  end

end
