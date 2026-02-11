defmodule ExmcViz.Component.ForestPlot do
  @moduledoc """
  Forest plot component. Displays horizontal credible intervals for each variable.

  Visual encoding:

  - **Thin line** (dim amber) — 94% Highest Density Interval
  - **Thick line** (bright amber) — 50% Highest Density Interval
  - **Dot** (white) — posterior mean

  A vertical reference line is drawn at zero. Variables are stacked vertically
  with labels on the left. Accepts `[%ForestData{}]` as input data.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.{Scale, Axis, Colors}

  @default_width 600
  @default_height 400
  @pad %{left: 180, right: 40, top: 50, bottom: 50}

  @impl Scenic.Component
  def validate(data) when is_list(data), do: {:ok, data}
  def validate(_), do: {:error, "Expected [%ForestData{}]"}

  @impl Scenic.Scene
  def init(scene, forest_data_list, opts) do
    w = opts[:width] || @default_width
    h = opts[:height] || @default_height

    graph = build_graph(forest_data_list, w, h)

    scene
    |> assign(data: forest_data_list, width: w, height: h)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp build_graph(forest_data_list, w, h) do
    plot_left = @pad.left
    plot_right = w - @pad.right
    plot_top = @pad.top
    plot_bottom = h - @pad.bottom

    # Compute global x range from all HDI_94 intervals
    all_lo = Enum.map(forest_data_list, fn fd -> elem(fd.hdi_94, 0) end)
    all_hi = Enum.map(forest_data_list, fn fd -> elem(fd.hdi_94, 1) end)
    x_min = Enum.min(all_lo)
    x_max = Enum.max(all_hi)

    x_pad = max((x_max - x_min) * 0.05, 0.01)
    x_min = x_min - x_pad
    x_max = x_max + x_pad

    x_scale = Scale.linear(x_min, x_max, plot_left, plot_right)
    x_ticks = Scale.ticks(x_min, x_max, 5)

    graph =
      Graph.build(font_size: 24)
      |> rect({w, h}, fill: Colors.panel_bg())
      |> text("Forest Plot",
        fill: Colors.text(),
        font_size: 32,
        translate: {plot_left, 36}
      )
      |> Axis.x_axis(x_scale, x_ticks,
        y: plot_bottom,
        x_start: plot_left,
        x_end: plot_right
      )
      # Zero reference line
      |> draw_zero_line(x_scale, plot_top, plot_bottom)

    # Draw each variable as a row
    n = length(forest_data_list)
    row_space = (plot_bottom - plot_top) / max(n, 1)

    forest_data_list
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {fd, idx}, g ->
      y = plot_top + (idx + 0.5) * row_space

      {lo94, hi94} = fd.hdi_94
      {lo50, hi50} = fd.hdi_50

      g
      # Variable name label
      |> text(fd.name,
        fill: Colors.text(),
        font_size: 26,
        text_align: :right,
        translate: {plot_left - 16, y + 8}
      )
      # 94% HDI thin line
      |> line({{x_scale.(lo94), y}, {x_scale.(hi94), y}},
        stroke: {4, Colors.forest_thin()}
      )
      # 50% HDI thick line
      |> line({{x_scale.(lo50), y}, {x_scale.(hi50), y}},
        stroke: {10, Colors.forest_thick()}
      )
      # Mean dot
      |> circle(7,
        fill: Colors.forest_dot(),
        translate: {x_scale.(fd.mean), y}
      )
    end)
  end

  defp draw_zero_line(graph, x_scale, plot_top, plot_bottom) do
    zero_px = x_scale.(0.0)
    line(graph, {{zero_px, plot_top}, {zero_px, plot_bottom}}, stroke: {3, Colors.axis()})
  end
end
