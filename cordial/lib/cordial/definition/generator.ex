defmodule Cordial.Definition.Generator do
  @spec doc(String.t() | nil, Keyword.t()) :: String.t() | nil
  def doc(doc, opts)
  def doc(nil, _opts), do: nil

  def doc(doc, opts) do
    if Keyword.get(opts, :doc, false) and doc != "" do
      doc
      |> String.split("\n")
      |> Enum.map_join("\n", &("// " <> &1))
    end
  end

  @spec indent(String.t() | [String.t()], indentation :: non_neg_integer()) :: String.t()
  def indent(code, indentation)
  def indent(code, 0) when is_binary(code), do: code
  def indent(code, 0), do: Enum.join(code, "\n")
  def indent(code, i) when is_binary(code), do: code |> String.split("\n") |> indent(i)

  def indent(code, indentation) when is_list(code) do
    prefix = String.duplicate("  ", indentation)

    Enum.map_join(code, "\n", &(prefix <> &1))
  end
end
