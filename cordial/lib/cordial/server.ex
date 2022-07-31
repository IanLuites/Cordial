defmodule Cordial.Server do
  alias __MODULE__.Config

  defmacro __using__(opts \\ [])

  defmacro __using__(opts) do
    Module.register_attribute(__CALLER__.module, :cordial_services, accumulate: true)
    Module.put_attribute(__CALLER__.module, :cordial_opts, opts)

    quote do
      @before_compile unquote(__MODULE__)
      import unquote(__MODULE__), only: [service: 1]
    end
  end

  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :cordial_opts, [])
    services = env.module |> Module.get_attribute(:cordial_services, []) |> Map.new()
    config = Config.from_opts(env.module, [{:services, services} | opts])

    quote location: :keep do
      @behaviour Cordial.Definition

      unquote(if Config.http?(config), do: apply(Cordial.HTTP.Router, :generate, [config]))

      @doc false
      @impl Cordial.Definition
      def __cordial__, do: %{type: :server, services: unquote(Macro.escape(services))}

      def child_spec(opts \\ []) do
        {id, opts} = Keyword.pop(opts, :id, __MODULE__)

        %{
          id: id,
          type: :supervisor,
          start: {__MODULE__, :start_link, [opts]}
        }
      end

      def start_link(opts \\ []) do
        {name, var!(opts)} = Keyword.pop(opts, :name, __MODULE__)
        _ = var!(opts)

        [
          unquote(if Config.http?(config), do: apply(Cordial.HTTP.Router, :child_spec, [config]))
        ]
        |> Enum.reject(&is_nil/1)
        |> Supervisor.start_link(strategy: :one_for_one, name: name)
      end
    end
  end

  defmacro service(module) do
    module = Macro.expand(module, __CALLER__)
    {:ok, services} = Cordial.services(module)

    missing =
      services
      |> Enum.map(&{&1, missing_callbacks(&1, module)})
      |> Enum.reject(&match?({_, []}, &1))

    unless Enum.empty?(missing) do
      details =
        missing
        |> Enum.flat_map(fn {service, functions} ->
          Enum.map(functions, fn {f, a} -> "  #{f}/#{a} from #{inspect(service)}" end)
        end)
        |> Enum.join("\n")

      description =
        "#{inspect(module)} service is incomplete.\n\nThe following implementations are missing:\n\n#{details}\n"

      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: description
    end

    Module.put_attribute(__CALLER__.module, :cordial_services, {module, services})

    quote do
      require unquote(module)
    end
  end

  @spec missing_callbacks(service :: module, implementation :: module) :: [
          {atom, non_neg_integer()}
        ]
  defp missing_callbacks(service, implementation)

  defp missing_callbacks(service, m) do
    :callbacks
    |> service.behaviour_info()
    |> Enum.reject(fn {f, a} -> :erlang.function_exported(m, f, a) end)
  end
end
