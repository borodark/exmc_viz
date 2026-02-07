defmodule ExmcViz.Component.CorrelationCell do
  @moduledoc """
  Correlation cell for the upper triangle of pair plots.

  Displays the Pearson correlation coefficient as centered text.
  Visual emphasis scales with the strength of the correlation:

  - **Font size** grows with `|r|` (12pt at r=0, up to 32pt at |r|=1)
  - **Color** indicates sign: green for positive, red for negative,
    dim amber for values near zero (|r| < 0.05)

  Accepts `%{r: float()}`.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.Colors

  @default_size 200

  @impl Scenic.Component
  def validate(data) when is_map(data), do: {:ok, data}
  def validate(_), do: {:error, "Expected correlation data map"}

  @impl Scenic.Scene
  def init(scene, data, opts) do
    size = opts[:size] || @default_size

    graph = build_graph(data, size)

    scene
    |> assign(data: data, size: size)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp build_graph(%{r: r}, size) do
    abs_r = abs(r)
    font_size = round(24 + abs_r * 36)

    color =
      cond do
        r > 0.05 -> {80, 200, 80}
        r < -0.05 -> {255, 80, 80}
        true -> Colors.text_dim()
      end

    label = :erlang.float_to_binary(r, decimals: 2)

    Graph.build(font_size: 24)
    |> rect({size, size}, fill: Colors.panel_bg())
    |> text(label,
      fill: color,
      font_size: font_size,
      text_align: :center,
      translate: {div(size, 2), div(size, 2) + div(font_size, 3)}
    )
  end
end
