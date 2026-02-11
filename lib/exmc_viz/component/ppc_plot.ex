defmodule ExmcViz.Component.PPCPlot do
  @moduledoc """
  Posterior predictive check overlay.

  Shows observed data histogram (solid amber outline) with semi-transparent
  posterior predictive histograms overlaid (blue).
  """
  use Scenic.Component

  alias ExmcViz.Draw.{Colors, Scale}

  @default_width 500
  @default_height 250

  @impl true
  def validate(%ExmcViz.Data.PPCData{} = data), do: {:ok, data}
  def validate(_), do: :invalid_data

  @impl true
  def init(scene, data, opts) do
    width = opts[:width] || @default_width
    height = opts[:height] || @default_height
    graph = build_graph(data, width, height)
    scene = push_graph(scene, graph)
    {:ok, scene}
  end

  defp build_graph(data, width, height) do
    pad_left = 50
    pad_right = 15
    pad_top = 35
    pad_bottom = 30
    plot_w = width - pad_left - pad_right
    plot_h = height - pad_top - pad_bottom

    num_bins = data.num_bins
    x_scale = Scale.linear(0, num_bins, pad_left, pad_left + plot_w)
    y_scale = Scale.linear(0, max(data.max_count, 1) * 1.15, pad_top + plot_h, pad_top)

    graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.rect({width, height}, fill: Colors.panel_bg())
      |> Scenic.Primitives.text("PPC: " <> data.obs_name,
        fill: Colors.text(),
        font_size: 20,
        t: {pad_left, 22}
      )

    # Draw predictive histograms (semi-transparent blue, subsample ~20)
    subset = Enum.take(data.predictive_histograms, 20)

    graph =
      Enum.reduce(subset, graph, fn pred_hist, graph ->
        Enum.with_index(pred_hist)
        |> Enum.reduce(graph, fn {count, bin}, graph ->
          x0 = x_scale.(bin)
          x1 = x_scale.(bin + 1)
          y_top = y_scale.(count)
          y_bottom = y_scale.(0)
          bar_w = x1 - x0
          bar_h = y_bottom - y_top

          graph
          |> Scenic.Primitives.rect({bar_w, bar_h},
            fill: {80, 140, 220, 30},
            t: {x0, y_top}
          )
        end)
      end)

    # Draw observed histogram (solid amber outline)
    Enum.with_index(data.observed_histogram)
    |> Enum.reduce(graph, fn {count, bin}, graph ->
      x0 = x_scale.(bin)
      x1 = x_scale.(bin + 1)
      y_top = y_scale.(count)
      y_bottom = y_scale.(0)
      bar_w = x1 - x0
      bar_h = y_bottom - y_top

      graph
      |> Scenic.Primitives.rect({bar_w, bar_h},
        stroke: {2, Colors.default_line()},
        t: {x0, y_top}
      )
    end)
  end
end
