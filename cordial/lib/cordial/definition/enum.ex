defmodule Cordial.Definition.Enum do
  @type t :: %__MODULE__{
          doc: String.t(),
          name: String.t(),
          package: String.t() | nil,
          parent: [String.t()],
          values: %{required(String.t()) => non_neg_integer}
        }
  defstruct [:doc, :name, :values, :source, parent: [], package: nil]

  @doc false
  def to_proto3(enum, opts \\ [])

  def to_proto3(%__MODULE__{name: name, doc: doc, values: values, parent: parent}, opts) do
    import Cordial.Definition.Generator

    values =
      values
      |> Enum.sort_by(& &1.value, :asc)
      |> Enum.map_join("\n", fn %{name: k, value: v} ->
        "  #{k} = #{v};"
      end)

    [
      doc(doc, opts),
      "enum #{name} {",
      Keyword.get(opts, :nested),
      values,
      "}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> indent(Enum.count(parent))
  end

  def dependencies(resource, filter, root)
  def dependencies(_, _, _), do: []

  @doc false
  def to_module(definition, opts \\ [])

  def to_module(def = %__MODULE__{values: values}, opts) do
    import Cordial.Definition.Resource

    root = Keyword.get(opts, :root, Elixir)
    module = module(def, root)

    lookup =
      Map.new(values, fn %{name: k, value: v} ->
        {k |> String.downcase() |> String.to_atom(), v}
      end)

    reverse = Map.new(lookup, fn {k, v} -> {v, k} end)
    types = lookup |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.reduce(&{:|, [], [&1, &2]})

    doc = """
    #{def.doc}

    ### Definition

    ```proto3
    #{to_proto3(def)}
    ```
    """

    json =
      if Code.ensure_loaded?(Jason) do
        parser =
          lookup
          |> Map.keys()
          |> Map.new(&{to_string(&1), &1})
          |> Map.merge(reverse)
          |> Enum.flat_map(fn {k, v} -> [{k, v}, {inspect(k), v}] end)
          |> Map.new()

        quote do
          def from_json(payload) do
            clean = if is_binary(payload), do: String.downcase(payload), else: payload

            with :error <- Map.fetch(unquote(Macro.escape(parser)), clean),
                 do: {:error, :invalid_enum}
          end
        end
      end

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(doc)

        @typedoc @moduledoc
        @type t :: unquote(types)

        @behaviour Cordial.Definition

        @doc false
        def default(), do: unquote(reverse[0])

        @doc false
        @impl Cordial.Definition
        def __cordial__, do: %{type: :enum, definition: unquote(Macro.escape(def))}

        unquote(json)
      end
    end
  end
end
