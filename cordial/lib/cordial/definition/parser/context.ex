defmodule Cordial.Definition.Parser.Context do
  @type opt :: {:cwd, Path.t()}
  @type opts :: [opt]

  @type t :: %__MODULE__{}
  defstruct cwd: nil,
            current: :global,
            root_dir: nil,
            doc: [],
            scope: [],
            resources: [],
            buffer: [],
            context: [],
            current_source: nil,
            sources: []

  @spec new(opts :: Cordial.Definition.Parser.Context.opts()) ::
          Cordial.Definition.Parser.Context.t()
  def new(opts \\ []) do
    cwd = Keyword.get_lazy(opts, :cwd, &File.cwd!/0)

    %__MODULE__{
      cwd: cwd,
      root_dir: cwd
    }
  end

  @spec doc(atom | %{:doc => list, optional(any) => any}) :: binary
  def doc(ctx), do: ctx.doc |> :lists.reverse() |> Enum.join("\n")
  def doc_reset(ctx), do: %{ctx | doc: []}

  def doc_push(ctx, doc)
  def doc_push(ctx = %{doc: doc}, d), do: %{ctx | doc: [d | doc]}

  def parent(%{scope: scope}) do
    scope
    |> Enum.filter(&(elem(&1, 0) == :message))
    |> Enum.map(&elem(&1, 1))
    |> :lists.reverse()
  end

  def scope_push(ctx, type, name)

  def scope_push(ctx = %{scope: scope, buffer: buffer}, type, name) do
    %{ctx | scope: [{type, name, buffer} | scope], current: type, buffer: []}
  end

  def scope_pop(ctx)

  def scope_pop(ctx = %{scope: [{_, _, buffer} | left], buffer: buffer_left}) do
    current =
      case left do
        [{type, _, _} | _] -> type
        _ -> :global
      end

    %{ctx | scope: left, current: current, doc: [], buffer: buffer ++ buffer_left}
  end

  def add(ctx, resource)

  def add(ctx = %{resources: r}, resource), do: %{ctx | resources: [resource | r]}

  def resource(ctx, generator), do: buffer_consume(ctx, &add(&1, generator.(&2)))

  def buffer(ctx, generator)
  def buffer(ctx, g) when is_function(g), do: buffer_consume(ctx, &%{&1 | buffer: [g.(&2)]})

  def buffer(ctx = %{buffer: buffer}, value),
    do: %{ctx | buffer: [value | buffer]}

  def buffer_consume(ctx, consumer)
  def buffer_consume(ctx = %{buffer: buffer}, c), do: c.(%{ctx | buffer: []}, buffer)

  @spec package(t) :: String.t() | nil
  def package(ctx)

  def package(%{scope: scope}) do
    Enum.find_value(scope, fn
      {:package, name, _} -> name
      _ -> false
    end)
  end

  @spec package_add_option(ctx :: t, option :: term) :: t
  def package_add_option(ctx = %{resources: resources}, option) do
    if p = package(ctx) do
      resources =
        Enum.map(resources, fn
          pkg = %Cordial.Definition.Package{name: ^p, options: options} ->
            %{pkg | options: [option | options]}

          r ->
            r
        end)

      %{ctx | resources: resources}
    else
      buffer(ctx, option)
    end
  end

  def context_new(ctx, source, cwd \\ nil)

  def context_new(
        ctx = %{cwd: cw, buffer: b, scope: s, current: c, context: context, current_source: cs},
        source,
        cwd
      ) do
    cwd = cwd || cw
    c = {b, s, c, cw, cs}

    %{
      ctx
      | cwd: cwd,
        buffer: [],
        scope: [],
        current: :global,
        current_source: source,
        context: [c | context],
        sources: if(source in ctx.sources, do: ctx.sources, else: [source | ctx.sources])
    }
  end

  def context_pop(ctx)

  def context_pop(ctx = %{context: [{b, s, c, cwd, cs} | context]}) do
    %{ctx | cwd: cwd, buffer: b, scope: s, current: c, context: context, current_source: cs}
  end

  def source(%{current_source: s}), do: s

  def source(ctx, source)
  def source(ctx, nil), do: ctx

  def source(ctx = %{current_source: cs, sources: sources}, source) do
    ctx = %{ctx | current_source: cs || source}
    if source_loaded?(ctx, source), do: ctx, else: %{ctx | sources: [source | sources]}
  end

  def source_loaded?(ctx, source)
  def source_loaded?(_, nil), do: false
  def source_loaded?(%{sources: sources}, %{uri: uri}), do: Enum.any?(sources, &(&1.uri == uri))
end
