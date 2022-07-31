defmodule Mix.Tasks.Cordial.New do
  @moduledoc ~S"""
  Creates a new Cordial project.

  It expects the path of the project as an argument.

  ```shell
  $ mix cordial.new PATH [--module MODULE] [--app APP]
  ```

  A project at the given PATH will be created.
  The application name and module name will be retrieved
  from the path, unless `--module` or `--app` is given.

  ## Options

    * `--app` - the name of the OTP application
    * `--module` - the name of the base module in the generated skeleton
    * `--verbose` - use verbose output
    * `-v`, `--version` - prints the Phoenix installer version

  ## Installation

  `mix cordial.new` by default prompts you to fetch and install your
  dependencies. You can enable this behaviour by passing the
  `--install` flag or disable it with the `--no-install` flag.

  ## Examples

  ```shell
  $ mix cordial.new hello_world
  ```
  """
  use Mix.Task
  alias Mix.Tasks.Help

  @version Mix.Project.config()[:version]
  @shortdoc "Creates a new Cordial v#{@version} application"

  @switches [
    grcp: :boolean,
    http: :string,
    client: :boolean,
    server: :boolean,
    module: :string,
    prefix: :string,
    proto: :keep,
    verbose: :boolean
  ]

  @aliases [
    p: :proto,
    schema: :proto
  ]

  @impl Mix.Task
  def run(argv)

  def run([version]) when version in ~w(-v --version) do
    Mix.shell().info("Cordial installer v#{@version}")
  end

  def run(argv) do
    elixir_version_check!()
    hex_available_check!()
    rebar_available_check!()

    case parse_opts(argv) do
      {_opts, []} ->
        Help.run(["cordial.new"])

      {opts, [dir | _]} ->
        app = opts |> Keyword.get(:app, dir) |> String.to_atom()
        check_app_name!(app, !!opts[:app])
        check_directory_existence!(dir)

        root_mod = Keyword.get(opts, :module, Macro.camelize(to_string(app)))
        root_mod = Module.concat(Elixir, root_mod)
        check_module_name_validity!(root_mod)
        check_module_name_availability!(root_mod)

        prefix =
          case Keyword.fetch(opts, :prefix) do
            {:ok, p} -> p |> String.split(".") |> Enum.map_join(".", &Macro.camelize/1)
            _ -> Elixir
          end

        check_module_name_validity!(prefix)

        {client?, server?} =
          if Keyword.has_key?(opts, :client) or Keyword.has_key?(opts, :server) do
            {Keyword.get(opts, :client, false), Keyword.get(opts, :server, false)}
          else
            {false, true}
          end

        {http?, grpc?} =
          if Keyword.has_key?(opts, :http) or Keyword.has_key?(opts, :grpc) do
            {Keyword.get(opts, :http, false), Keyword.get(opts, :grpc, false)}
          else
            {true, false}
          end

        config = %{
          http?: http?,
          client?: client?,
          server?: server?,
          grpc?: grpc?,
          verbose?: Keyword.get(opts, :verbose, false),
          prefix: prefix,
          server_dir: server? && if(client?, do: Path.join(dir, "server"), else: dir),
          server_app: server? && if(client?, do: :"#{app}_server", else: app),
          server_module: server? && Module.concat(root_mod, Server),
          client_dir: client? && if(client?, do: Path.join(dir, "client"), else: dir),
          client_app: client? && app,
          client_module: client? && root_mod,
          proto: listify(Keyword.get(opts, :proto, [])) |> Enum.map(&resolve/1),
          services: [],
          resources: %{}
        }

        Cordial.New.create(config)
    end
  end

  defp resolve(scheme)

  defp resolve(scheme = "." <> _) do
    "file://" <> Path.expand(scheme, File.cwd!())
  end

  defp resolve(scheme), do: scheme

  defp parse_opts(argv) do
    case OptionParser.parse(argv, strict: @switches, aliases: @aliases) do
      {opts, argv, []} -> {opts, argv}
      {_opts, _argv, [switch | _]} -> Mix.raise("Invalid option: " <> switch_to_string(switch))
    end
  end

  defp switch_to_string({name, nil}), do: name
  defp switch_to_string({name, val}), do: name <> "=" <> val

  defp listify(value)
  defp listify(values) when is_list(values), do: values
  defp listify(value), do: [value]

  defp check_app_name!(name, from_app_flag) do
    unless to_string(name) =~ Regex.recompile!(~r/^[a-z][\w_]*$/) do
      extra =
        if from_app_flag do
          ""
        else
          ". The application name is inferred from the path, if you'd like to " <>
            "explicitly name the application then use the `--app APP` option."
        end

      Mix.raise(
        "Application name must start with a letter and have only lowercase " <>
          "letters, numbers and underscore, got: #{inspect(name)}" <> extra
      )
    end
  end

  defp check_module_name_validity!(name) do
    unless inspect(name) =~ Regex.recompile!(~r/^[A-Z]\w*(\.[A-Z]\w*)*$/) do
      Mix.raise(
        "Module name must be a valid Elixir alias (for example: Foo.Bar), got: #{inspect(name)}"
      )
    end
  end

  defp check_module_name_availability!(name) do
    [name]
    |> Module.concat()
    |> Module.split()
    |> Enum.reduce([], fn name, acc ->
      mod = Module.concat([Elixir, name | acc])

      if Code.ensure_loaded?(mod) do
        Mix.raise("Module name #{inspect(mod)} is already taken, please choose another name")
      else
        [name | acc]
      end
    end)
  end

  defp check_directory_existence!(path) do
    if File.dir?(path) and
         not Mix.shell().yes?(
           "The directory #{path} already exists. Are you sure you want to continue?"
         ) do
      Mix.raise("Please select another directory for installation.")
    end
  end

  defp elixir_version_check! do
    unless Version.match?(System.version(), "~> 1.12") do
      Mix.raise(
        "Cordial v#{@version} requires at least Elixir v1.12.\n " <>
          "You have #{System.version()}. Please update accordingly"
      )
    end
  end

  defp hex_available_check! do
    unless Code.ensure_loaded?(Hex) do
      Mix.raise("Cordial v#{@version} requires at Hex to be available.")
    end
  end

  defp rebar_available_check! do
    unless Mix.Rebar.rebar_cmd(:rebar3) do
      Mix.raise("Cordial v#{@version} requires at rebar[3] to be available.")
    end
  end
end
