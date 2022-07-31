defmodule Cordial.Definition do
  @moduledoc ~S"""
  Protocol buffer definitions.
  """

  @doc false
  @callback __cordial__ :: %{
              required(:type) => Cordial.Definition.Type.t(),
              required(:root) => module(),
              optional(:definition) => struct(),
              optional(:services) => %{required(module) => [module]}
            }

  @type resource ::
          Cordial.Definition.Message.t()
          | Cordial.Definition.Service.t()
          | Cordial.Definition.Enum.t()

  @type source ::
          Cordial.Definition.Source.t()
          | URI.t()
          | String.t()
          | {source :: Cordial.Definition.Source.t() | URI.t() | String.t(), opts :: Keyword.t()}

  ### Reading ###

  @spec load(source :: Cordial.Definition.source(), opts :: Keyword.t()) ::
          [term]
  def load(source, opts \\ []), do: load_all([source], opts)

  @spec load_all(
          sources :: [Cordial.Definition.Source.t() | URI.t() | String.t()],
          opts :: Keyword.t()
        ) ::
          [term]
  def load_all(sources, opts \\ [])
  def load_all([], _), do: []

  def load_all(sources, opts) do
    [{h, h_opts} | t] = Enum.map(sources, &prep_source(&1, opts))

    base = __MODULE__.Parser.load(h, h_opts)
    Enum.reduce(t, base, fn {s, o}, acc -> __MODULE__.Parser.load(acc, s, o) end).resources
  end

  @spec prep_source(source(), Keyword.t()) ::
          {source :: Cordial.Definition.Source.t() | URI.t() | String.t(), opts :: Keyword.t()}
  defp prep_source({source, source_opts}, opts), do: {source, Keyword.merge(opts, source_opts)}
  defp prep_source(source, opts), do: {source, opts}

  ### Writing ###

  @order [
    Cordial.Definition.Package,
    Cordial.Definition.Service,
    Cordial.Definition.Message,
    Cordial.Definition.Enum
  ]

  @spec to_proto3(resource, opts :: []) :: [%{path: Path.t(), content: binary}]
  def to_proto3(resources, opts \\ [])

  def to_proto3(resources, opts) do
    resources = gath_deps(resources)

    encoding_opts = [
      annotations: Keyword.get(opts, :annotations, false),
      doc: Keyword.get(opts, :doc, false),
      options: Keyword.get(opts, :options, false)
    ]

    resources =
      case Keyword.fetch(opts, :filter) do
        :error -> resources
        {:ok, filter} -> Enum.filter(resources, filter)
      end

    resources
    |> Enum.group_by(fn
      %{package: p} -> p
      %Cordial.Definition.Package{name: p} -> p
    end)
    |> Enum.map(fn {package, items} ->
      content =
        items
        |> Enum.group_by(&(&1 |> Map.get(:parent, []) |> length()))
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.map(&elem(&1, 1))
        |> Enum.reduce(%{}, fn items, children ->
          items
          |> Enum.sort_by(fn %t{} -> Enum.find_index(@order, &(&1 == t)) end)
          |> Enum.reduce(%{}, fn item = %type{}, acc ->
            p = Map.get(item, :parent, [])
            n = {:nested, Map.get(children, p ++ [item.name])}
            v = type.to_proto3(item, [n | encoding_opts])

            Map.update(acc, p, v, &(&1 <> "\n\n" <> v))
          end)
        end)
        |> Map.values()
        |> Enum.join("\n\n")

      remote = remote_packages(items, package)

      pkg = if package, do: "package #{package};\n\n", else: ""

      header =
        if Enum.empty?(remote),
          do: "",
          else: Enum.map_join(remote, "", &"import #{inspect(package_file(&1))};\n") <> "\n"

      %{
        package: package,
        path: package_file(package),
        content: "syntax = \"proto3\";\n\n" <> pkg <> header <> content,
        resources: items
      }
    end)
  end

  defp package_file(package)
  defp package_file(nil), do: "_.proto"

  defp package_file(package),
    do: package |> String.split(".") |> Path.join() |> Kernel.<>(".proto")

  defp remote_packages(resources, package) do
    resources
    |> Enum.flat_map(fn
      %Cordial.Definition.Package{} ->
        []

      %Cordial.Definition.Enum{} ->
        []

      %Cordial.Definition.Message{fields: f} ->
        Enum.map(f, & &1.type)

      %Cordial.Definition.Service{functions: functions} ->
        functions
        |> Enum.flat_map(fn %{argument: a, return: r} -> [a, r] end)
        |> Enum.map(& &1.type)
    end)
    |> Enum.map(fn type ->
      m = Cordial.Definition.Type.module(type, Elixir)

      if m, do: m.__cordial__().definition.package
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == package))
    |> Enum.uniq()
  end

  defp gath_deps(resources, loaded \\ [], result \\ [])
  defp gath_deps([], _, result), do: result

  defp gath_deps([h | t], loaded, result) do
    alias Cordial.Definition.Resource

    {mod, def} =
      if is_atom(h) do
        {h, h.__cordial__().definition}
      else
        {h, Resource.module(h)}
      end

    load =
      def
      |> Resource.dependencies(:runtime, Elixir)
      |> Enum.reject(&(&1 == mod or &1 in loaded or &1 in t))

    gath_deps(t ++ load, [mod | loaded], [def | result])
  end
end
