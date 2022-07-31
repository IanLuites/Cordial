defmodule Cordial.New.Template do
  @moduledoc ~S"""

  """

  @templates Path.expand("../../../priv/templates", __DIR__)
  @doc @moduledoc
  defmacro __using__(opts \\ []) do
    template = Keyword.fetch!(opts, :template)
    path = Path.join(@templates, template)
    files = index(path)

    templates =
      files
      |> Enum.sort(fn
        %{type: type, name: a}, %{type: type, name: b} -> String.length(a) <= String.length(b)
        %{type: type}, _ -> type == :dir
      end)
      |> Enum.map(& &1.name)

    quote do
      def render(target, var!(assigns)) when is_list(var!(assigns)) do
        Enum.each(unquote(templates), &render(&1, target, var!(assigns)))
      end

      unquote(Enum.map(files, &renderer/1))

      defp module({:type, _, path}, root),
        do: Module.concat([root | path |> String.split(".") |> Enum.map(&Macro.camelize/1)])

      defp module(a, b) do
        IO.inspect({a, b})
        X
      end

      @spec filename(module | String.t()) :: String.t()
      defp filename(module) when is_atom(module), do: module |> dirs() |> List.last()
      defp filename(module), do: module |> String.split(".") |> List.last() |> Macro.underscore()

      @spec lib(module) :: Path.join()
      defp lib(module), do: Path.join(["lib" | module |> dirs() |> Enum.slice(0..-2)])

      @spec dirs(module) :: [String.t()]
      defp dirs(module), do: module |> Module.split() |> Enum.map(&Macro.underscore/1)
    end
  end

  defp renderer(entry)

  defp renderer(%{type: :dir, absolute: absolute, name: name}) do
    out = if eex?(name), do: EEx.compile_string(name), else: name

    quote do
      @external_resource unquote(absolute)
      defp render(unquote(name), target, var!(assigns)) when is_list(var!(assigns)) do
        File.mkdir_p!(Path.join(target, unquote(out)))
      end
    end
  end

  defp renderer(%{type: :file, absolute: absolute, name: name}) do
    data = File.read!(absolute)

    out = if eex?(name), do: EEx.compile_string(name), else: name
    template = if eex?(data), do: EEx.compile_string(data), else: data

    quote do
      @external_resource unquote(absolute)
      defp render(unquote(name), target, var!(assigns)) when is_list(var!(assigns)) do
        File.write!(Path.join(target, unquote(out)), unquote(template))
      end
    end
  end

  @spec eex?(binary) :: boolean
  defp eex?(data), do: data =~ ~r/<%=/

  @spec ls!(Path.t()) :: [Path.t()]
  defp ls!(dir), do: dir |> File.ls!() |> Enum.map(&Path.join(dir, &1))

  @spec index(Path.t()) :: [%{type: :dir | :file, absolute: Path.t(), name: Path.t()}]
  defp index(root), do: index(ls!(root), root, [])

  @spec index([Path.t()], Path.t(), [%{type: :dir | :file, absolute: Path.t(), name: Path.t()}]) ::
          [%{type: :dir | :file, absolute: Path.t(), name: Path.t()}]
  defp index(todo, root, acc)
  defp index([], _root, acc), do: acc

  defp index([h | t], root, acc) do
    if File.dir?(h) do
      index(t ++ ls!(h), root, [
        %{type: :dir, absolute: h, name: String.trim_leading(h, root <> "/")} | acc
      ])
    else
      index(t, root, [
        %{type: :file, absolute: h, name: String.trim_leading(h, root <> "/")} | acc
      ])
    end
  end
end
