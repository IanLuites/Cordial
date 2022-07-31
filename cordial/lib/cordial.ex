defmodule Cordial do
  @moduledoc """
  Documentation for `Cordial`.
  """
  @path Path.join(Mix.Project.build_path(), "cordial")

  @module_types ~S"""
  The following types are available:

    - `:service`, a service definition. Useable as behaviour.
    - `:message`, a message definition. Useable as struct.
    - `:service_impl`, module implementing one or more services.
    - `:client`, a Cordial client.
    - `:server`, a Cordial server.
  """

  @typedoc """
  Cordial module types.

  #{@module_types}
  """
  @type type :: :service | :message | :service_impl | :client | :server

  @doc """
  Determine module Cordial type.

  #{@module_types}

  ## Example

  Determine type of a given module:
  ```elixir
  iex> Cordial.type(Helloworld.Greeter)
  :service

  iex> Cordial.type(Helloworld.HelloReply)
  :message

  iex> Cordial.type(Example.Greeter)
  :service_impl

  iex> Cordial.type(Example.Server)
  :server
  ```

  Returns `false` if module does not exist or is not a Cordial module:
  ```elixir
  iex> Cordial.type(MyFakeModule)
  false

  iex> Cordial.type(Enum)
  false

  iex> Cordial.type(534)
  false
  ```
  """
  @spec type(module :: module) :: Cordial.type() | false
  def type(module)

  def type(module) do
    cond do
      not module?(module) -> false
      :erlang.function_exported(module, :__cordial__, 0) -> module.__cordial__().type
      Enum.any?(behaviours(module), &service?/1) -> :service_impl
      :none_cordial -> false
    end
  end

  @doc ~S"""
  Check whether a given module is a service.

  ## Example

  Test for service.
  ```elixir
  iex> Cordial.service?(Helloworld.Greeter)
  true

  iex> Cordial.service?(Helloworld.HelloReply)
  false
  ```
  """
  @spec service?(service :: module) :: boolean
  def service?(service)
  def service?(service), do: type(service) == :service

  @doc ~S"""
  List all services for a given service implementation or server.

  ## Example

  Return error if not a server or service implementation:
  ```elixir
  iex> Cordial.services(Helloworld.HelloReply)
  {:error, :invalid_module}

  iex> Cordial.services(FakeModule)
  {:error, :invalid_module}
  ```
  """
  @spec services(service_or_server :: module) :: {:ok, [module]} | {:error, :invalid_module}
  def services(service_or_server)

  def services(module) do
    result =
      if module?(module) do
        if :erlang.function_exported(module, :__cordial__, 0) do
          info = module.__cordial__()
          if info.type == :server, do: {:ok, Enum.flat_map(info.services, &elem(&1, 1))}
        else
          services = module |> behaviours() |> Enum.filter(&service?/1)

          unless Enum.empty?(services), do: {:ok, services}
        end
      end

    result || {:error, :invalid_module}
  end

  @spec behaviours(module :: module) :: [module]
  defp behaviours(module) do
    :attributes
    |> module.__info__()
    |> Enum.filter(&match?({:behaviour, _}, &1))
    |> Enum.flat_map(&elem(&1, 1))
  end

  @spec module?(module :: any) :: boolean()
  defp module?(module) do
    is_atom(module) and match?({:module, _}, Code.ensure_compiled(module)) and
      Code.ensure_loaded?(module)
  end

  @doc false
  @spec directory(:crates | :schemas) :: Path.t()
  def directory(type)

  def directory(type) do
    path = Path.join(@path, to_string(type))
    File.mkdir_p!(path)

    path
  end
end
