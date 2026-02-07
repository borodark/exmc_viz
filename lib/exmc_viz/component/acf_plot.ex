defmodule ExmcViz.Component.AcfPlot do
  @moduledoc """
  Autocorrelation function plot. Vertical bars from y=0 to ACF value per lag.

  Includes significance band at +/- 2/sqrt(n).
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.{Scale, Axis, Colors}

  @default_width 220
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

    max_lag = length(var_data.acf) - 1

    # ACF range is [-1, 1] but we'll use the actual data range
    acf_min = min(-0.2, Enum.min(var_data.acf))
    acf_max = max(1.0, Enum.max(var_data.acf))

    x_scale = Scale.linear(0, max_lag, plot_left, plot_right)
    y_scale = Scale.linear(acf_min, acf_max, plot_bottom, plot_top)

    x_ticks = Scale.ticks(0, max_lag, 4)
    y_ticks = Scale.ticks(acf_min, acf_max, 4)

    # Significance band
    sig = 2.0 / :math.sqrt(max(var_data.n_samples, 1))

    zero_y = y_scale.(0.0)
    sig_upper_y = y_scale.(sig)
    sig_lower_y = y_scale.(-sig)

    graph =
      Graph.build(font_size: 10)
      |> rect({w, h}, fill: Colors.panel_bg())
      |> text("ACF",
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
      # Zero line
      |> line({{plot_left, zero_y}, {plot_right, zero_y}},
        stroke: {1, Colors.axis()}
      )
      # Significance bands
      |> line({{plot_left, sig_upper_y}, {plot_right, sig_upper_y}},
        stroke: {1, Colors.sig_band()}
      )
      |> line({{plot_left, sig_lower_y}, {plot_right, sig_lower_y}},
        stroke: {1, Colors.sig_band()}
      )

    # Draw ACF bars
    var_data.acf
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {acf_val, lag}, g ->
      x = x_scale.(lag)
      y_val = y_scale.(acf_val)

      line(g, {{x, zero_y}, {x, y_val}},
        stroke: {2, Colors.acf_bar()}
      )
    end)
  end
end
