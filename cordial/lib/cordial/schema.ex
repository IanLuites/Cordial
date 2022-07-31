defmodule Cordial.Schema do
  @moduledoc ~S"""
  Protobuf schema collection.
  """
  alias Cordial.Definition.Resource

  @doc @moduledoc
  defmacro __using__(opts \\ [])

  defmacro __using__(opts) do
    root = opts |> Keyword.get(:root, __CALLER__.module) |> Macro.expand(__CALLER__)
    Module.put_attribute(__CALLER__.module, :cordial_root, root)

    dir = opts |> Keyword.get(:dir, "priv") |> Macro.expand(__CALLER__)
    Module.put_attribute(__CALLER__.module, :cordial_schema_dir, dir)

    Module.register_attribute(__CALLER__.module, :cordial_schema, accumulate: true)

    quote do
      @before_compile unquote(__MODULE__)
      import unquote(__MODULE__),
        only: [
          import_schema: 1,
          import_schema: 2,
          message: 2,
          rpc: 1,
          rpc: 2,
          rpc: 3
        ]
    end
  end

  defmacro __before_compile__(env) do
    opts = [
      cwd: Module.get_attribute(__CALLER__.module, :cordial_schema_dir)
    ]

    root = Module.get_attribute(__CALLER__.module, :cordial_root, Elixir)

    case env.module
         |> Module.get_attribute(:cordial_schema, [])
         |> Cordial.Definition.load_all(opts)
         |> select(type: :service)
         |> Enum.map(&{&1, Resource.module(&1, root), Resource.dependencies(&1, :compile, root)})
         |> dependency_sort() do
      {:ok, resources} ->
        defines =
          quote do
            @doc false
            @spec resources :: [module]
            def resources, do: unquote(Enum.map(resources, &elem(&1, 1)))
          end

        [
          defines
          | Enum.flat_map(resources, fn {v = %t{}, _, _} ->
              external_resources =
                if t == Cordial.Definition.Package do
                  Enum.map(v.sources, fn %{local: local} ->
                    quote do
                      @external_resource unquote(local)
                    end
                  end)
                else
                  []
                end

              [Resource.to_module(v, root) | external_resources]
            end)
        ]

      {:error, failed, succeeded} ->
        errors =
          failed
          |> Enum.group_by(&elem(&1, 0).source)
          |> Enum.map_join("\n", fn {source, e} ->
            "  #{source}:\n" <>
              Enum.map_join(e, "\n", fn {_, %{module: module, requires: requires}} ->
                deps =
                  Enum.map_join(requires, "\n", fn mod ->
                    color =
                      if dependency_loaded?(mod, succeeded),
                        do: IO.ANSI.green(),
                        else: IO.ANSI.red()

                    "       - #{color}#{inspect(mod)}#{IO.ANSI.reset()}"
                  end)

                ~s"""
                    Failed to compile: #{inspect(module)}
                    Dependencies:
                #{deps}
                """
              end)
          end)

        description = ~s"""
        [Cordial] Failed to compile schemas, because of invalid dependencies.

        #{errors}
        """

        IO.puts(description)
        raise CompileError, file: env.file, description: description
    end
  end

  defp select(resources, filter) do
    f =
      case filter[:type] do
        :service -> &match?(%Cordial.Definition.Service{}, &1)
      end

    available = Map.new(resources, &{Resource.module(&1, Elixir), &1})

    resources
    |> Enum.filter(f)
    |> grab_deps(available)
  end

  defp grab_deps(grab, available, selected \\ []) do
    selected = Enum.uniq(selected ++ grab)

    case grab
         |> Enum.flat_map(fn r ->
           r
           |> Resource.dependencies(:runtime, Elixir)
           |> Enum.map(&Map.get(available, &1))
           |> Enum.reject(&(is_nil(&1) or &1 in selected))
         end)
         |> Enum.uniq() do
      [] -> selected
      more -> grab_deps(more, available, selected)
    end
  end

  defp dependency_sort(load, acc \\ []) do
    {retry, loaded} =
      Enum.reduce(load, {[], acc}, fn dep, {fail, success} ->
        if dependencies_satisfied?(dep, success) do
          {fail, [dep | success]}
        else
          {[dep | fail], success}
        end
      end)

    cond do
      Enum.empty?(retry) -> {:ok, :lists.reverse(loaded)}
      Enum.count(retry) < Enum.count(load) -> dependency_sort(retry, loaded)
      :deadlock -> {:error, retry, loaded}
    end
  end

  defp dependency_loaded?(dependency, loaded)

  defp dependency_loaded?(mod, loaded),
    do: Enum.any?(loaded, fn {_, m, _} -> m == mod end)

  defp dependencies_satisfied?(dependency, loaded)

  defp dependencies_satisfied?({_, _, deps}, loaded) do
    Enum.all?(deps, &dependency_loaded?(&1, loaded))
  end

  ### Macro Based ###
  defmacro message(_, _), do: nil
  defmacro rpc(_, _ \\ nil, _ \\ nil), do: nil

  ### File Based ###
  defmacro import_schema(schema, opts \\ []) do
    schema = Macro.expand(schema, __CALLER__)
    Module.put_attribute(__CALLER__.module, :cordial_schema, {schema, opts})
  end
end
