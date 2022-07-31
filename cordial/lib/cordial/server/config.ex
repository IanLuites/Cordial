defmodule Cordial.Server.Config do
  @moduledoc ~S"""
  Cordial server configuration.
  """
  require Logger

  # Potentially move this to the dedicated dependencies themselves.
  # For now it is a nice way to share code and keep config in one place.
  # Dependency split mostly to keep footprint lower by splitting deps of deps.
  @defaults %{
    grpc: %{
      module: GRPC,
      port: 50_051
    },
    http: %{
      module: HTTP,
      port: 3_000,
      expose: :all
    }
  }

  @check %{
    grpc: Cordial.GRPC,
    http: Cordial.HTTP
  }

  @dependency %{
    grpc: :cordial_grpc,
    http: :cordial_http
  }

  @type grpc_opt :: {:module, module} | {:port, pos_integer()}

  @type http_expose :: :all | :annotated_only
  @type http_opt :: {:module, module} | {:port, pos_integer()} | {:expose, http_expose()}

  @type opt :: {:grpc, false | true | [grpc_opt()]} | {:http, false | true | [http_opt()]}

  @typedoc @moduledoc
  @opaque t :: %__MODULE__{
            module: module(),
            grpc: false | %{module: module(), port: pos_integer()},
            http: false | %{module: module(), port: pos_integer(), expose: http_expose()},
            services: [module()]
          }
  defstruct [:module, grpc: false, http: false, services: []]

  @doc ~S"""
  Create a config for the given server with given opts.

  ## Example

  ```elixir
  iex> _config = from_opts(Example, web: false, grpc: [port: 8080])
  ```
  """
  @spec from_opts(server :: module, opts :: [opt]) :: Cordial.Server.Config.t()
  def from_opts(server, opts \\ [])

  def from_opts(server, opts) do
    %__MODULE__{
      module: server,
      grpc: parse(server, :grpc, "gRPC", opts),
      http: parse(server, :http, "HTTP", opts),
      services: Keyword.get(opts, :services, [])
    }
  end

  @doc ~S"""
  Confirm HTTP server support is enabled or not.

  ## Example

  Disabled by default:
  ```elixir
  iex> config = from_opts(Example)
  iex> http?(config)
  false
  ```

  Or overridable:
  ```elixir
  iex> config = from_opts(Example, http: false)
  iex> http?(config)
  false
  ```

  can be enabled:
  ```elixir
  iex> config = from_opts(Example, http: true)
  iex> http?(config)
  true

  iex> config = from_opts(Example, http: [])
  iex> http?(config)
  true

  iex> config = from_opts(Example, http: [port: 4000])
  iex> http?(config)
  true
  ```
  """
  @spec http?(config :: Cordial.Server.Config.t()) :: boolean()
  def http?(config)
  def http?(%{http: %{port: _}}), do: support_enabled?(:http)
  def http?(_), do: false

  @doc ~S"""
  Confirm gRPC server support is enabled or not.

  ## Example

  Disabled by default:
  ```elixir
  iex> config = from_opts(Example)
  iex> grpc?(config)
  false
  ```

  Or overridable:
  ```elixir
  iex> config = from_opts(Example, grpc: false)
  iex> grpc?(config)
  false
  ```

  can be enabled:
  ```elixir
  iex> config = from_opts(Example, grpc: true)
  iex> grpc?(config)
  true

  iex> config = from_opts(Example, grpc: [])
  iex> grpc?(config)
  true

  iex> config = from_opts(Example, grpc: [port: 8080])
  iex> grpc?(config)
  true
  ```
  """
  @spec grpc?(config :: Cordial.Server.Config.t()) :: boolean()
  def grpc?(config)
  def grpc?(%{grpc: %{port: _}}), do: support_enabled?(:grpc)
  def grpc?(_), do: false

  ### Helpers ###

  defp parse(server, functionality, name, opts) do
    defaults = @defaults[functionality]

    # credo:disable-for-lines:2
    result =
      with opts when is_list(opts) <- Keyword.get(opts, functionality, false) do
        {port, opts} = Keyword.pop(opts, :port, defaults.port)
        {module, opts} = Keyword.pop(opts, :module, Module.concat(server, defaults.module))
        {specific, opts} = functionality_config(functionality, defaults, opts)

        unless Enum.empty?(opts),
          do: warn(server, "Unknown #{name} options: #{inspect(opts)}", opts: opts)

        Map.merge(specific, %{module: module, port: port})
      else
        true -> defaults |> Map.update!(:module, &Module.concat(server, &1))
        false -> false
        other -> warn(server, "Unknown #{name} options: #{inspect(other)}", opts: other) && false
      end

    if result && not support_enabled?(functionality), do: missing(server, functionality, name)

    result
  end

  defp functionality_config(functionality, defaults, opts)

  defp functionality_config(:http, defaults, opts) do
    {expose, opts} = Keyword.pop(opts, :expose, defaults.expose)

    {%{expose: expose}, opts}
  end

  defp functionality_config(_, defaults, opts), do: {defaults, opts}

  defp support_enabled?(functionality), do: Code.ensure_loaded?(@check[functionality])

  defp missing(server, functionality, name) do
    dependency = @dependency[functionality]

    warn(server, ~s|Enabled #{name}, but #{inspect(dependency)} is missing.

  Please add the following to your dependencies:

    {#{inspect(dependency)}, ">= 0.0.0"}

  Or disable #{name} by setting and or passing as server option:

    #{functionality}: false
|)
  end

  defp warn(server, message, metadata \\ []) do
    Logger.warn("[Cordial][Server][#{inspect(server)}] " <> message, metadata)
  end
end
