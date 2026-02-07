defmodule ExmcViz.Component.SummaryPanel do
  @moduledoc """
  Text panel showing summary statistics for a variable.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.Colors

  @default_width 200
  @default_height 180
  @line_height 28

  @impl Scenic.Component
  def validate(%ExmcViz.Data.VarData{} = data), do: {:ok, data}
  def validate(_), do: {:error, "Expected %VarData{}"}

  @impl Scenic.Scene
  def init(scene, var_data, opts) do
    w = opts[:width] || @default_width
    h = opts[:height] || @default_height

    graph = build_graph(var_data, w, h)

    scene
    |> assign(var_data: var_data, width: w, height: h)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp build_graph(var_data, w, h) do
    q = var_data.quantiles

    lines = [
      {"mean", fmt(var_data.mean)},
      {"std", fmt(var_data.std)},
      {"ESS", fmt(var_data.ess)},
      {"5%", fmt(q.q5)},
      {"25%", fmt(q.q25)},
      {"50%", fmt(q.q50)},
      {"75%", fmt(q.q75)},
      {"95%", fmt(q.q95)}
    ]

    lines =
      if var_data.rhat do
        lines ++ [{"R-hat", fmt(var_data.rhat)}]
      else
        lines
      end

    graph =
      Graph.build(font_size: 24)
      |> rect({w, h}, fill: Colors.panel_bg())
      |> text(var_data.name,
        fill: Colors.text(),
        font_size: 28,
        translate: {20, 28}
      )

    lines
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {{label, value}, idx}, g ->
      y = 56 + idx * @line_height

      g
      |> text(label,
        fill: Colors.text_dim(),
        font_size: 24,
        translate: {20, y}
      )
      |> text(value,
        fill: Colors.text(),
        font_size: 24,
        text_align: :right,
        translate: {w - 20, y}
      )
    end)
  end

  defp fmt(value) when is_float(value) do
    cond do
      abs(value) >= 1000 -> :erlang.float_to_binary(value, decimals: 0)
      abs(value) >= 10 -> :erlang.float_to_binary(value, decimals: 1)
      abs(value) >= 1 -> :erlang.float_to_binary(value, decimals: 2)
      true -> :erlang.float_to_binary(value, decimals: 3)
    end
  end

  defp fmt(value) when is_integer(value), do: Integer.to_string(value)
  defp fmt(nil), do: "-"
end
