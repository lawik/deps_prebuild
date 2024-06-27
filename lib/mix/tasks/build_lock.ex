defmodule Mix.Tasks.Deps.BuildLock do
    use Mix.Task

    alias DepsPrebuild.Build

    require Logger

    @gcc_version "v13.2.0"
    @shortdoc "Make builds for all deps in your lock file"
  
    @impl true
    def run(_args) do
      dir = "/tmp/deps_build_lock"
      File.rm_rf(dir)
      File.mkdir_p!(dir)
      elixir_version = System.version() |> major_minor()
      otp_version = get_otp_version() |> major()
      build =
        Build.new()
        |> Build.set_elixir_version(elixir_version)
        |> Build.set_otp_version(otp_version)
        |> Build.set_gcc_version(@gcc_version)
        |> Build.set_arch(get_arch())
        |> Build.set_os(get_os())
        |> Build.set_libc(:gnu)

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
            with {:ok, build} <- DepsPrebuild.download_to(build) |> dbg() do

              Enum.map([:dev, :prod, :test], fn env ->
                env = to_string(env)
                build = Build.set_mix_env(build, env)
                unpack_path = Path.join([dir, env, name])
                File.mkdir_p!(unpack_path)
                build = Build.set_unpacked_dir(build, unpack_path)
                with {:ok, build} <- DepsPrebuild.unpack_and_verify(build) |> dbg(),
                     {:ok, build} <- DepsPrebuild.check_package_type(build) |> dbg(),
                     {:ok, build} <- DepsPrebuild.build_package(build) |> dbg(),
                     {:ok, build} <- DepsPrebuild.extract_build(build) |> dbg(),
                     {:ok, build} <- DepsPrebuild.package_build(build) |> dbg() do
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

    defp get_os do
      case :os.type() do
        {:unix, :linux} -> :linux
        {:unix, :darwin} -> :macos
        {:win32, :nt} -> :windows
      end
    end

    defp get_arch do
      case :erlang.system_info(:system_architecture) |> to_string() do
        "x86_64" <> _ -> :x86_64
      end
    end
    
    

    defp get_otp_version do
      [:code.root_dir(), "releases", :erlang.system_info(:otp_release), "OTP_VERSION"] 
      |> Path.join() 
      |> File.read!() 
      |> String.trim()
    end

    defp major_minor(version) do
      [major | [minor | _]] = String.split(version, ".")
      "#{major}.#{minor}"
    end

    def major(version) do
      [major | _] = String.split(version, ".")
      major
    end
    
    
    
end