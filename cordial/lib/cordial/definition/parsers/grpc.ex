defmodule Cordial.Parsers.GRPC do
  @moduledoc ~S"""
  Protocol buffer and gRPC parser.
  """
  alias Cordial.Definition.Enum, as: GEnum
  alias Cordial.Definition.{Message, Package, Parser, Service, Type}
  alias Cordial.Definition.Parser.Context
  import Cordial.Definition.Resource

  defguard global(ctx) when ctx.current in [:global, :package]
  defguard message(ctx) when ctx.current == :message
  defguard service(ctx) when ctx.current == :service
  defguard rpc(ctx) when ctx.current == :rpc
  defguard enum(ctx) when ctx.current == :enum

  def parse(data, context)

  def parse(data, context) do
    context
    |> do_parse(__MODULE__.Tokenizer.tokenize(data))
    |> Map.update!(:resources, fn resources ->
      resources
      |> Enum.group_by(fn
        %Cordial.Definition.Package{name: n} -> n
        _ -> nil
      end)
      |> Enum.flat_map(fn
        {nil, r} -> r
        {_, combine} -> package_merge(combine)
      end)
      |> resolve_types()
      |> merge_extensions()
    end)
  end

  defp merge_extensions(resources) do
    grouped = Enum.group_by(resources, &match?(%{type: :extend}, &1))
    resources = Map.get(grouped, false, [])
    extensions = Map.get(grouped, true, [])

    Enum.reduce(extensions, resources, fn ext, resources ->
      [n | p] = ext.message |> String.split(".") |> :lists.reverse()
      p = p |> :lists.reverse() |> Enum.join(".")

      if index = Enum.find_index(resources, &(&1.name == n and &1.package == p)) do
        List.update_at(resources, index, &%{&1 | fields: &1.fields ++ ext.fields})
      else
        resources
      end
    end)
  end

  defp resolve_types(resources) do
    Enum.map(resources, fn
      p = %Package{} ->
        p

      e = %GEnum{} ->
        e

      m = %Message{fields: fields} ->
        %{m | fields: Enum.map(fields, &fix_type(&1, m, resources))}

      m = %{type: :extend, fields: fields} ->
        %{m | fields: Enum.map(fields, &fix_type(&1, m, resources))}

      s = %Service{functions: functions} ->
        functions =
          Enum.map(functions, fn f = %{argument: a, return: r} ->
            %{f | argument: fix_type(a, s, resources), return: fix_type(r, s, resources)}
          end)

        %{s | functions: functions}
    end)
  end

  defp fix_type(type, resource, resources)

  defp fix_type(n = %{type: t}, resource, resources),
    do: %{n | type: fix_type(t, resource, resources)}

  defp fix_type({:map, k, v}, resource, resources),
    do: {:map, fix_type(k, resource, resources), fix_type(v, resource, resources)}

  defp fix_type({:type, t, nil}, resource, resources), do: resolve_type(t, resource, resources)
  defp fix_type(t, _, _), do: t

  defp resolve_type(relative, resource, resources) do
    absolute =
      resource
      |> selector()
      |> find_type(String.split(relative, "."), resources)

    {:type, relative, absolute}
  end

  defp find_type(scope, selector, resources)
  defp find_type([], selector, _resources), do: Enum.join(selector, ".")

  defp find_type(scope, selector, resources) do
    full = scope ++ selector

    if Enum.any?(resources, &(selector(&1) == full)),
      do: Enum.join(full, "."),
      else: scope |> Enum.slice(0..-2) |> find_type(selector, resources)
  end

  defp package_merge(packages)
  defp package_merge(package = [_]), do: package

  defp package_merge(packages) do
    [
      Enum.reduce(
        packages,
        fn package, acc ->
          %{
            acc
            | doc: if(acc.doc == "", do: package.doc, else: acc.doc),
              options: Enum.uniq_by(acc.options ++ package.options, &elem(&1, 0)),
              sources: Enum.uniq(acc.sources ++ package.sources)
          }
        end
      )
    ]
  end

  defp do_parse(ctx, tokens)
  defp do_parse(ctx, []), do: ctx

  # All
  defp do_parse(ctx, [:stop | tokens]), do: do_parse(ctx, tokens)

  defp do_parse(ctx, [{:comment, c} | tokens]),
    do: ctx |> Context.doc_push(c) |> do_parse(tokens)

  defp do_parse(ctx, [
         {:literal, "extensions"},
         {:number, _},
         {:literal, "to"},
         {:literal, "max"} | tokens
       ]),
       do: ctx |> do_parse(tokens)

  defp do_parse(ctx, [{:literal, "reserved"}, {:number, _} | tokens]) do
    drop = Enum.find_index(tokens, &(&1 == :stop))
    ctx |> do_parse(Enum.slice(tokens, drop..-1))
  end

  defp do_parse(
         ctx,
         [{:literal, "option"}, {:literal, key}, :=, value, :stop | tokens]
       ) do
    ctx
    |> Context.doc_reset()
    |> set_option(parse_option(key, value))
    |> do_parse(tokens)
  end

  defp do_parse(
         ctx,
         [
           {:literal, "option"},
           {:tuple, [{:literal, key}]},
           :=,
           value,
           :stop | tokens
         ]
       ) do
    ctx
    |> Context.doc_reset()
    |> set_option(parse_option(key, value))
    |> do_parse(tokens)
  end

  defp do_parse(ctx, [{:literal, "syntax"}, :=, {:string, "proto" <> _}, :stop | tokens])
       when global(ctx),
       do: ctx |> Context.doc_reset() |> do_parse(tokens)

  defp do_parse(ctx, [{:literal, "package"}, {:literal, name}, :stop | tokens])
       when global(ctx) do
    ctx
    |> Context.doc_reset()
    |> Context.resource(fn f ->
      %Package{
        name: name,
        doc: Context.doc(ctx),
        options: f,
        sources: [Context.source(ctx)]
      }
    end)
    |> Context.scope_push(:package, name)
    |> do_parse(tokens)
  end

  defp do_parse(ctx, [{:literal, "import"}, {:string, file}, :stop | tokens]) when global(ctx) do
    ctx
    |> Parser.load(file, [])
    |> do_parse(tokens)
  end

  ## Services
  defp do_parse(ctx, [{:literal, "service"}, {:literal, name}, {:block, block} | tokens])
       when global(ctx) do
    ctx
    |> Context.doc_reset()
    |> Context.scope_push(:service, name)
    |> do_parse(block)
    |> Context.resource(fn f ->
      %Service{
        name: name,
        package: Context.package(ctx),
        doc: Context.doc(ctx),
        functions: f,
        source: Context.source(ctx)
      }
    end)
    |> Context.scope_pop()
    |> do_parse(tokens)
  end

  defp do_parse(
         ctx,
         [
           {:literal, "rpc"},
           {:literal, name},
           {:tuple, argument},
           {:literal, "returns"},
           {:tuple, return},
           stop | tokens
         ]
       )
       when service(ctx) do
    inside =
      case stop do
        :stop -> []
        {:block, block} -> block
      end

    ctx
    |> Context.doc_reset()
    |> Context.scope_push(:rpc, name)
    |> do_parse(inside)
    |> Context.buffer(fn f ->
      %Service.Function{
        name: name,
        doc: Context.doc(ctx),
        argument: parse_rpc_type(argument),
        return: parse_rpc_type(return),
        options: Map.new(f)
      }
    end)
    |> Context.scope_pop()
    |> do_parse(tokens)
  end

  ## Message
  defp do_parse(ctx, [{:literal, "message"}, {:literal, name}, {:block, block} | tokens])
       when global(ctx) or message(ctx) do
    ctx
    |> Context.doc_reset()
    |> Context.scope_push(:message, name)
    |> do_parse(block)
    |> Context.resource(fn f ->
      %Message{
        name: name,
        package: Context.package(ctx),
        parent: Context.parent(ctx),
        doc: Context.doc(ctx),
        fields: List.flatten(f),
        source: Context.source(ctx)
      }
    end)
    |> Context.scope_pop()
    |> do_parse(tokens)
  end

  defp do_parse(ctx, [{:literal, "extend"}, {:literal, message}, {:block, block} | tokens]) do
    ctx
    |> Context.doc_reset()
    |> Context.scope_push(:message, message)
    |> do_parse(block)
    |> Context.resource(fn f ->
      %{
        type: :extend,
        message: message,
        package: Context.package(ctx),
        parent: Context.parent(ctx),
        doc: Context.doc(ctx),
        fields: List.flatten(f),
        source: Context.source(ctx)
      }
    end)
    |> Context.scope_pop()
    # |> Context.buffer_consume(fn ctx = %{resources: resources}, buffer ->
    #   index = Enum.find_index(resources, &(&1.name == n and &1.package == p))
    #   added = Enum.map(buffer, &%{&1 | name: prefix <> &1.name})
    #   %{ctx | resources: List.update_at(resources, index, &%{&1 | fields: &1.fields ++ added})}
    # end)
    |> do_parse(tokens)
  end

  defp do_parse(ctx, [{:literal, "enum"}, {:literal, name}, {:block, block} | tokens])
       when message(ctx) or global(ctx) do
    ctx
    |> Context.doc_reset()
    |> Context.scope_push(:enum, name)
    |> do_parse(block)
    |> Context.resource(fn f ->
      %GEnum{
        name: name,
        package: Context.package(ctx),
        parent: Context.parent(ctx),
        doc: Context.doc(ctx),
        values: f,
        source: Context.source(ctx)
      }
    end)
    |> Context.scope_pop()
    |> do_parse(tokens)
  end

  defp do_parse(ctx, [{:literal, name}, :=, {:number, value}, :stop | tokens])
       when enum(ctx) do
    ctx
    |> Context.buffer(%{name: name, value: value})
    |> do_parse(tokens)
  end

  defp do_parse(ctx, [
         {:literal, "oneof"},
         {:literal, name},
         {:block, block} | tokens
       ])
       when message(ctx) do
    one_of = String.to_atom(name)

    ctx
    |> Context.scope_push(:message, nil)
    |> do_parse(block)
    |> Context.buffer(fn buffer ->
      Enum.map(buffer, &%{&1 | one_of: one_of})
    end)
    |> Context.scope_pop()
    |> do_parse(tokens)
  end

  defp do_parse(
         ctx,
         [
           {:literal, "required"},
           {:literal, type},
           {:literal, name},
           :=,
           {:number, index},
           :stop | tokens
         ]
       )
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, [], optional: false)

  defp do_parse(
         ctx,
         [
           {:literal, "optional"},
           {:literal, type},
           {:literal, name},
           :=,
           {:number, index},
           :stop | tokens
         ]
       )
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, [], optional: true)

  defp do_parse(
         ctx,
         [
           {:literal, "repeated"},
           {:literal, type},
           {:literal, name},
           :=,
           {:number, index},
           :stop | tokens
         ]
       )
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, [], repeated: true)

  defp do_parse(ctx, [{:literal, type}, {:literal, name}, :=, {:number, index}, :stop | tokens])
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, [])

  defp do_parse(ctx, [
         {:literal, "required"},
         {:literal, type},
         {:literal, name},
         :=,
         {:number, index},
         {:array, annotations},
         :stop | tokens
       ])
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, annotations, optional: false)

  defp do_parse(ctx, [
         {:literal, "optional"},
         {:literal, type},
         {:literal, name},
         :=,
         {:number, index},
         {:array, annotations},
         :stop | tokens
       ])
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, annotations, optional: true)

  defp do_parse(ctx, [
         {:literal, "repeated"},
         {:literal, type},
         {:literal, name},
         :=,
         {:number, index},
         {:array, annotations},
         :stop | tokens
       ])
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, annotations, repeated: true)

  defp do_parse(ctx, [
         {:literal, type},
         {:literal, name},
         :=,
         {:number, index},
         {:array, annotations},
         :stop | tokens
       ])
       when message(ctx),
       do: parse_field(ctx, tokens, name, type, index, annotations)

  defp do_parse(ctx, [
         {:literal, "map"},
         {:template, [{:literal, key}, :and, {:literal, value}]},
         {:literal, name},
         :=,
         {:number, index},
         {:array, annotations},
         :stop | tokens
       ])
       when message(ctx),
       do: parse_field(ctx, tokens, name, {:map, key, value}, index, annotations)

  defp do_parse(ctx, [
         {:literal, "map"},
         {:template, [{:literal, key}, :and, {:literal, value}]},
         {:literal, name},
         :=,
         {:number, index},
         :stop | tokens
       ])
       when message(ctx),
       do: parse_field(ctx, tokens, name, {:map, key, value}, index, [])

  defp parse_field(ctx, tokens, name, type, index, annotations, opts \\ [])

  defp parse_field(ctx, tokens, name, type, index, _annotations, opts) do
    ctx
    |> Context.buffer(%Message.Field{
      name: name,
      type: parse_type(type),
      doc: Context.doc(ctx),
      index: index,
      repeated: Keyword.get(opts, :repeated, false),
      optional: Keyword.get(opts, :optional, true),
      one_of: Keyword.get(opts, :one_of, false)
    })
    |> Context.doc_reset()
    |> do_parse(tokens)
  end

  defp set_option(ctx, option)
  defp set_option(ctx, option) when rpc(ctx), do: Context.buffer(ctx, option)
  defp set_option(ctx, option), do: Context.package_add_option(ctx, option)

  defp parse_option(key, value) do
    {key, decode_value(value)}
  end

  defp decode_value(value)
  defp decode_value({:literal, atom}), do: String.to_atom(atom)
  defp decode_value({:string, string}), do: string
  defp decode_value({:number, number}), do: number
  defp decode_value({:block, block}), do: decode_block_map(block)

  defp decode_block_map(tokens, acc \\ %{})
  defp decode_block_map([], acc), do: acc

  defp decode_block_map([{:literal, k}, :set, v | tokens], acc) do
    decode_block_map(tokens, Map.put(acc, k, decode_value(v)))
  end

  @scalars Enum.map(Type.scalars(), &to_string/1)
  @spec parse_type(term) :: Type.t()
  defp parse_type(type)
  defp parse_type({:literal, value}), do: parse_type(value)
  defp parse_type(scalar) when scalar in @scalars, do: String.to_atom(scalar)

  defp parse_type({:map, key, value}), do: {:map, parse_type(key), parse_type(value)}

  defp parse_type(type) do
    {:type, type, if(String.starts_with?(type, "."), do: String.slice(type, 1..-1))}
  end

  defp parse_rpc_type(tuple)

  defp parse_rpc_type(tuple) do
    {:literal, type} = List.last(tuple)

    %{stream: match?([{:literal, "stream"} | _], tuple), type: parse_type(type)}
  end
end
