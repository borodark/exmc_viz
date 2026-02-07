defmodule ExmcViz.Component.ScatterPlot do
  @moduledoc """
  Scatter plot component for the lower triangle of pair plots.

  Renders pairwise posterior samples as small filled circles. To keep rendering
  fast, subsamples to at most 500 points when the trace is longer.

  Divergent samples (if `divergent_indices` is set) are highlighted in red.

  Accepts `%{xs: [float()], ys: [float()], divergent_indices: [int()] | nil}`.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.{Scale, Colors}

  @default_size 200
  @pad %{left: 10, right: 10, top: 10, bottom: 10}
  @max_points 500

  @impl Scenic.Component
  def validate(data) when is_map(data), do: {:ok, data}
  def validate(_), do: {:error, "Expected scatter data map"}

  @impl Scenic.Scene
  def init(scene, data, opts) do
    size = opts[:size] || @default_size

    graph = build_graph(data, size)

    scene
    |> assign(data: data, size: size)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp build_graph(%{xs: xs, ys: ys, divergent_indices: div_indices}, size) do
    plot_left = @pad.left
    plot_right = size - @pad.right
    plot_top = @pad.top
    plot_bottom = size - @pad.bottom

    {x_min, x_max} = Enum.min_max(xs)
    {y_min, y_max} = Enum.min_max(ys)

    x_pad = max((x_max - x_min) * 0.05, 0.01)
    y_pad = max((y_max - y_min) * 0.05, 0.01)

    x_scale = Scale.linear(x_min - x_pad, x_max + x_pad, plot_left, plot_right)
    y_scale = Scale.linear(y_min - y_pad, y_max + y_pad, plot_bottom, plot_top)

    # Subsample if needed
    n = length(xs)
    {xs_sub, ys_sub, indices} = subsample(xs, ys, n)

    div_set = if div_indices, do: MapSet.new(div_indices), else: MapSet.new()

    graph =
      Graph.build(font_size: 24)
      |> rect({size, size}, fill: Colors.panel_bg())

    # Draw points
    Enum.zip([xs_sub, ys_sub, indices])
    |> Enum.reduce(graph, fn {x, y, idx}, g ->
      px = x_scale.(x)
      py = y_scale.(y)
      color = if MapSet.member?(div_set, idx), do: Colors.divergence(), else: Colors.default_line()

      circle(g, 3,
        fill: color,
        translate: {px, py}
      )
    end)
  end

  defp subsample(xs, ys, n) when n <= @max_points do
    {xs, ys, Enum.to_list(0..(n - 1))}
  end

  defp subsample(xs, ys, n) do
    step = n / @max_points
    indices = Enum.map(0..(@max_points - 1), fn i -> round(i * step) end)
    xs_arr = :array.from_list(xs)
    ys_arr = :array.from_list(ys)

    {
      Enum.map(indices, &:array.get(&1, xs_arr)),
      Enum.map(indices, &:array.get(&1, ys_arr)),
      indices
    }
  end
end
