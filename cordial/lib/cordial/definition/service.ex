defmodule Cordial.Definition.Service do
  alias Cordial.Definition.Type

  defmodule Function do
    defstruct [
      :doc,
      :name,
      :argument,
      :return,
      :options
    ]
  end

  defstruct [:doc, :name, :functions, :source, package: nil]

  @doc false
  def to_proto3(service, opts \\ [])

  def to_proto3(%__MODULE__{name: name, doc: doc, functions: functions}, opts) do
    import Cordial.Definition.Generator

    functions =
      Enum.map_join(functions, "\n", fn %{name: n, argument: argument, return: return} ->
        arg_stream = if argument.stream, do: "stream "
        return_stream = if return.stream, do: "stream "

        arg = Type.proto(argument.type)
        return = Type.proto(return.type)

        [
          doc(doc, opts),
          "rpc #{n} (#{arg_stream}#{arg}) returns (#{return_stream}#{return});"
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")
        |> indent(1)
      end)

    [
      doc(doc, opts),
      "service #{name} {\n#{functions}\n}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def dependencies(resource, filter, root)

  def dependencies(_def = %{functions: functions}, _filter, root) do
    functions
    |> Enum.flat_map(fn %{argument: %{type: argument}, return: %{type: return}} ->
      [
        Type.module(argument, root),
        Type.module(return, root)
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc false
  def to_module(definition, opts \\ [])

  def to_module(def = %__MODULE__{functions: functions}, opts) do
    import Cordial.Definition.Resource

    root = Keyword.get(opts, :root, Elixir)
    module = module(def, root)

    callbacks =
      Enum.map(functions, fn %{name: name, doc: doc, argument: argument, return: return} ->
        identifier = name |> Macro.underscore() |> String.to_atom()
        argument = Type.typespec(argument.type, root)
        return = Type.typespec(return.type, root)

        quote do
          @doc unquote(doc)
          @callback unquote(identifier)(unquote(argument)) :: {:ok, unquote(return)}
        end
      end)

    doc = """
    #{def.doc}

    ### Definition

    ```proto3
    #{to_proto3(def)}
    ```
    """

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(doc)

        unquote(callbacks)

        @behaviour Cordial.Definition

        @doc false
        @impl Cordial.Definition
        def __cordial__, do: %{type: :service, definition: unquote(Macro.escape(def))}
      end
    end
  end
end
