defmodule ExmcViz.Component.Histogram do
  @moduledoc """
  Histogram bar chart component. Shows distribution of sample values.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.{Scale, Axis, Colors}

  @default_width 280
  @default_height 180
  @pad %{left: 45, right: 10, top: 25, bottom: 25}

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
    plot_left = @pad.left
    plot_right = w - @pad.right
    plot_top = @pad.top
    plot_bottom = h - @pad.bottom

    %{bins: bins, max_count: max_count} = var_data.histogram

    # X range from bin edges
    {x_min, _, _} = hd(bins)
    {_, x_max, _} = List.last(bins)

    x_scale = Scale.linear(x_min, x_max, plot_left, plot_right)
    y_scale = Scale.linear(0, max_count, plot_bottom, plot_top)

    x_ticks = Scale.ticks(x_min, x_max, 4)
    y_ticks = Scale.ticks(0, max_count, 3)

    graph =
      Graph.build(font_size: 10)
      |> rect({w, h}, fill: Colors.panel_bg())
      |> text("Posterior",
        fill: Colors.text(),
        font_size: 12,
        translate: {plot_left, 14}
      )
      |> Axis.x_axis(x_scale, x_ticks,
        y: plot_bottom,
        x_start: plot_left,
        x_end: plot_right
      )
      |> Axis.y_axis(y_scale, y_ticks,
        x: plot_left,
        y_start: plot_top,
        y_end: plot_bottom
      )

    # Draw bars
    Enum.reduce(bins, graph, fn {left, right, count}, g ->
      px_left = x_scale.(left)
      px_right = x_scale.(right)
      px_top = y_scale.(count)
      bar_w = max(px_right - px_left - 1, 1)
      bar_h = plot_bottom - px_top

      if bar_h > 0 do
        rect(g, {bar_w, bar_h},
          fill: Colors.hist_fill(),
          translate: {px_left, px_top}
        )
      else
        g
      end
    end)
  end
end
