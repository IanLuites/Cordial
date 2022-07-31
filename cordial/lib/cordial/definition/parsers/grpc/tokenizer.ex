defmodule Cordial.Parsers.GRPC.Tokenizer do
  @blocks %{
    ?( => :tuple,
    ?{ => :block,
    ?[ => :array,
    ?< => :template
  }
  @block_open Map.keys(@blocks)
  @block_types Map.values(@blocks)

  @spec tokenize(binary) :: Enumerable.t()
  def tokenize(data) do
    {result, _} = tokenize(data, [])
    post(result)
  end

  defp post(tokens, acc \\ [])
  defp post([], acc), do: :lists.reverse(acc)
  defp post([{:string, a}, {:string, b} | t], acc), do: post([{:string, a <> b} | t], acc)

  defp post([{block, data} | t], acc) when block in @block_types,
    do: post(t, [{block, post(data)} | acc])

  defp post([h | t], acc), do: post(t, [h | acc])

  defguardp alpha(char) when char in ?a..?z or char in ?A..?Z
  defguardp num(char) when char in ?0..?9
  defguardp alpha_numeric(char) when alpha(char) or num(char)
  defguardp literal(char) when alpha_numeric(char) or char in [?_, ?.]

  defp tokenize(binary, acc)
  defp tokenize(<<>>, acc), do: {:lists.reverse(acc), <<>>}
  defp tokenize(<<b, rest::binary>>, acc) when b in [?\s, ?\r, ?\n, ?\t], do: tokenize(rest, acc)
  defp tokenize(<<?=, rest::binary>>, acc), do: tokenize(rest, [:= | acc])
  defp tokenize(<<?:, rest::binary>>, acc), do: tokenize(rest, [:set | acc])
  defp tokenize(<<?;, rest::binary>>, acc), do: tokenize(rest, [:stop | acc])
  defp tokenize(<<?,, rest::binary>>, acc), do: tokenize(rest, [:and | acc])

  defp tokenize(<<close, rest::binary>>, acc) when close in '})]>' do
    {:lists.reverse(acc), rest}
  end

  defp tokenize(<<open, rest::binary>>, acc) when open in @block_open do
    {block, left} = tokenize(rest, [])
    tokenize(left, [{@blocks[open], block} | acc])
  end

  defp tokenize(<<?), rest::binary>>, acc) do
    {:lists.reverse(acc), rest}
  end

  defp tokenize(<<?(, rest::binary>>, acc) do
    {block, left} = tokenize(rest, [])
    tokenize(left, [{:tuple, block} | acc])
  end

  defp tokenize(<<lit, rest::binary>>, acc) when alpha(lit) do
    {literal, left} = grab_till(rest, &(not literal(&1)), [lit])
    tokenize(left, [{:literal, literal} | acc])
  end

  defp tokenize(<<lit, rest::binary>>, acc) when num(lit) do
    {number, left} = grab_till(rest, &(not num(&1)), [lit])
    tokenize(left, [{:number, String.to_integer(number)} | acc])
  end

  defp tokenize(<<?\", rest::binary>>, acc) do
    {string, <<?\", left::binary>>} = grab_till(rest, &(&1 == ?\"))
    tokenize(left, [{:string, string} | acc])
  end

  defp tokenize(<<?\/, ?*, rest::binary>>, acc) do
    {comment, <<_, _, left::binary>>} = grab_till2(rest, &(&1 == "*/"))
    tokenize(left, [{:comment, String.trim(comment)} | acc])
  end

  defp tokenize(<<?\/, ?\/, rest::binary>>, acc) do
    {comment, left} = grab_till(rest, &(&1 in [?\r, ?\n]))
    tokenize(left, [{:comment, String.trim(comment)} | acc])
  end

  defp grab_till(binary, condition, acc \\ [])
  defp grab_till(<<>>, _condition, acc), do: {acc |> :lists.reverse() |> to_string(), ""}

  defp grab_till(all = <<c, rest::binary>>, condition, acc) do
    if condition.(c),
      do: {acc |> :lists.reverse() |> to_string(), all},
      else: grab_till(rest, condition, [c | acc])
  end

  defp grab_till2(binary, condition, acc \\ [])
  defp grab_till2(<<>>, _condition, acc), do: {acc |> :lists.reverse() |> to_string(), ""}
  defp grab_till2(<<c>>, condition, acc), do: grab_till2(<<>>, condition, [c | acc])

  defp grab_till2(all = <<c1, c2, rest::binary>>, condition, acc) do
    if condition.(<<c1, c2>>),
      do: {acc |> :lists.reverse() |> to_string(), all},
      else: grab_till2(<<c2, rest::binary>>, condition, [c1 | acc])
  end
end
