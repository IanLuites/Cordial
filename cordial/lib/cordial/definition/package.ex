defmodule Cordial.Definition.Package do
  @type t :: %__MODULE__{
          doc: String.t(),
          name: String.t(),
          options: [{String.t(), String.t() | number | boolean()}]
        }
  defstruct [:name, :doc, :options, sources: []]

  @doc false
  def to_proto3(package, opts \\ [])

  def to_proto3(%__MODULE__{name: name, doc: doc, options: options}, opts) do
    import Cordial.Definition.Generator

    [
      if Keyword.get(opts, :options) and not Enum.empty?(options) do
        options
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map_join("", fn {k, v} -> "option #{k} = #{inspect(v)};\n" end)
      end,
      doc(doc, opts),
      "package #{name};"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def dependencies(resource, filter, root)
  def dependencies(_, _, _), do: []

  @doc false
  def to_module(definition, opts \\ [])

  def to_module(def = %__MODULE__{name: _name, doc: doc, options: _options}, opts) do
    import Cordial.Definition.Resource
    root = Keyword.get(opts, :root, Elixir)
    mod = module(def, root)

    quote do
      defmodule unquote(mod) do
        @moduledoc unquote(doc)

        @behaviour Cordial.Definition

        @doc false
        @impl Cordial.Definition
        def __cordial__, do: %{type: :package, definition: unquote(Macro.escape(def))}
      end
    end
  end
end
