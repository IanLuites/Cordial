defmodule Cordial.Definition.Resource do
  @spec to_module(resource :: Cordial.Definition.resource(), root :: module) :: term
  def to_module(resource, root)
  def to_module(resource = %type{}, root), do: type.to_module(resource, root: root)

  @spec dependencies(
          resource :: Cordial.Definition.resource(),
          filter :: :compile | :runtime,
          root :: module
        ) :: [module]
  def dependencies(resource, filter, root)
  def dependencies(r = %type{}, filter, root), do: type.dependencies(r, filter, root)

  @spec selector(resource :: Cordial.Definition.resource()) :: [String.t()]
  def selector(resource) do
    [
      resource |> Map.get(:package) |> Kernel.||("") |> String.split(".", trim: true),
      resource |> Map.get(:parent, []),
      resource |> Map.get(:name, [])
    ]
    |> List.flatten()
  end

  @spec module(
          resource :: Cordial.Definition.resource() | Cordial.Definition.Type.t(),
          root :: module
        ) :: module
  def module(resource, root \\ Elixir) do
    case resource do
      %{package: p, parent: parent, name: n} when p != nil ->
        iolist_to_module([root, p, parent, n])

      %{package: p, name: n} when p != nil ->
        iolist_to_module([root, p, n])

      %{parent: parent, name: n} ->
        iolist_to_module([root, parent, n])

      %{name: n} ->
        iolist_to_module([root, n])

      {:type, _relative, absolute} ->
        iolist_to_module([root, absolute])
    end
  end

  defp iolist_to_module(components) do
    components |> components() |> List.flatten() |> Module.concat()
  end

  def components(component)
  def components(Elixir), do: Elixir
  def components("Elixir"), do: Elixir
  def components(c) when is_list(c), do: Enum.map(c, &components/1)
  def components(c) when is_atom(c), do: Module.split(c)
  def components(c) when is_binary(c), do: c |> String.split(".") |> Enum.map(&format/1)

  defp format(name), do: Macro.camelize(name)
end
