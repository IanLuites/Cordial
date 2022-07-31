defmodule Cordial.Definition.Message do
  alias Cordial.Definition.Type

  defmodule Field do
    defstruct [:name, :doc, :type, :index, repeated: false, optional: false, one_of: false]
  end

  @type t :: %__MODULE__{
          doc: String.t(),
          name: String.t(),
          package: String.t() | nil,
          parent: [String.t()],
          fields: [%{name: String.t(), doc: String.t(), type: Cordial.Definition.Type.t()}]
        }
  defstruct [:doc, :name, :fields, :source, package: nil, parent: []]

  @doc false
  def to_proto3(message, opts \\ [])

  def to_proto3(%__MODULE__{name: name, doc: doc, fields: fields, parent: parent}, opts) do
    import Cordial.Definition.Generator

    fields =
      fields
      |> Enum.sort_by(& &1.index)
      |> Enum.map_join("\n", fn field ->
        [
          doc(field.doc, opts),
          "#{Type.proto(field.type)} #{field.name} = #{field.index};"
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")
        |> indent(1)
      end)

    [
      doc(doc, opts),
      "message #{name} {",
      if(n = Keyword.get(opts, :nested), do: n <> "\n"),
      fields,
      "}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> indent(Enum.count(parent))
  end

  def dependencies(resource, filter, root)

  def dependencies(def = %{fields: fields}, filter, root) do
    import Cordial.Definition.Resource

    module = module(def, root)

    # Note: Repeated is often used for circular dependencies.
    #       Since the default is `[]` we do not hard depend.
    #       In this case any repeated fields are not considered required.

    fields
    |> Enum.map(&unless(filter == :compile and &1.repeated, do: Type.module(&1.type, root)))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == module))
  end

  @doc false
  def to_module(definition, opts \\ [])

  def to_module(def = %__MODULE__{fields: fields}, opts) do
    import Cordial.Definition.Resource

    root = Keyword.get(opts, :root, Elixir)
    module = module(def, root)

    defstruct =
      Enum.map(
        fields,
        &{String.to_atom(&1.name), if(&1.repeated, do: [], else: Type.default(&1.type, root))}
      )

    spec =
      Enum.map(
        fields,
        &{String.to_atom(&1.name),
         if(&1.repeated, do: [Type.typespec(&1.type, root)], else: Type.typespec(&1.type, root))}
      )

    doc = """
    #{def.doc}

    ### Definition

    ```proto3
    #{to_proto3(def)}
    ```
    """

    json =
      if Code.ensure_loaded?(Jason) do
        decoders = Enum.map(fields, &decoder(&1, module, root))

        quote do
          def from_json(payload) when is_binary(payload) do
            with {:ok, decode} <- Jason.decode(payload), do: from_json(decode)
          end

          def from_json(var!(payload) = %{}) do
            var!(result) = %{}

            with unquote_splicing(decoders), do: {:ok, struct!(__MODULE__, var!(result))}
          end

          def from_json(_), do: {:error, :invalid_map}

          defimpl Jason.Encoder do
            def encode(value, opts) do
              value
              |> Map.from_struct()
              |> Jason.Encode.map(opts)
            end
          end
        end
      end

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(doc)

        @typedoc @moduledoc
        @type t :: %__MODULE__{unquote_splicing(spec)}

        defstruct unquote(defstruct)

        @behaviour Cordial.Definition

        @doc false
        def default(), do: %__MODULE__{}

        @doc false
        @impl Cordial.Definition
        def __cordial__, do: %{type: :message, definition: unquote(Macro.escape(def))}

        unquote(json)
      end
    end
  end

  defp decoder(field, module, root)

  defp decoder(%{name: name, type: type, repeated: repeated, optional: optional}, module, root) do
    f = String.to_atom(name)

    # CHeck (google.api.field_behavior) = REQUIRED annotation
    not_set =
      if optional do
        value = if repeated, do: [], else: Type.default(type, root)

        quote do
          {:ok, Map.put(var!(result), unquote(f), unquote(value))}
        end
      else
        quote do
          {:error, %{missing: %{field: unquote(f), message: unquote(module)}}}
        end
      end

    {mod, fun} = Type.parser(type, root)

    parser =
      if repeated do
        quote do
          unquote(__MODULE__).repeated_parse(var!(raw), &(unquote(mod).unquote(fun) / 1))
        end
      else
        quote do
          unquote(mod).unquote(fun)(var!(raw))
        end
      end

    quote do
      {:ok, var!(result)} <-
        case Map.fetch(var!(payload), unquote(name)) do
          {:ok, var!(raw)} ->
            with {:ok, value} <- unquote(parser),
                 do: {:ok, Map.put(var!(result), unquote(f), value)}

          :error ->
            unquote(not_set)
        end
    end
  end

  @doc false
  def repeated_parse(elements, parser)
  def repeated_parse(e, parser) when is_list(e), do: repeated_parse(e, parser, [])
  def repeated_parse(_, _), do: {:error, :invalid_repeated_field}

  defp repeated_parse(elements, parser, acc)
  defp repeated_parse([], _parser, acc), do: {:ok, :lists.reverse(acc)}

  defp repeated_parse([h | t], parser, acc) do
    with {:ok, v} <- parser.(h), do: repeated_parse(t, parser, [v | acc])
  end
end
