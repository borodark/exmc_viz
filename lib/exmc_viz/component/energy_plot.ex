defmodule ExmcViz.Component.EnergyPlot do
  @moduledoc """
  Energy diagnostic plot component.

  Renders two overlaid semi-transparent histograms on a shared axis:

  - **Amber** — marginal energy distribution (Hamiltonian at trajectory start)
  - **Blue** — energy transition distribution (absolute change between steps)

  Good overlap indicates efficient sampling. A heavy right tail on the
  transition histogram signals poor exploration or tuning issues.

  Accepts `%EnergyData{}` as input data. Added to the dashboard below
  the per-variable rows when energy stats are available.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.{Scale, Axis, Colors}

  @default_width 600
  @default_height 180
  @pad %{left: 45, right: 10, top: 25, bottom: 25}

  @impl Scenic.Component
  def validate(%ExmcViz.Data.EnergyData{} = data), do: {:ok, data}
  def validate(_), do: {:error, "Expected %EnergyData{}"}

  @impl Scenic.Scene
  def init(scene, energy_data, opts) do
    w = opts[:width] || @default_width
    h = opts[:height] || @default_height

    graph = build_graph(energy_data, w, h)

    scene
    |> assign(data: energy_data, width: w, height: h)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp build_graph(energy_data, w, h) do
    plot_left = @pad.left
    plot_right = w - @pad.right
    plot_top = @pad.top
    plot_bottom = h - @pad.bottom

    %{hist_energy: he, hist_transition: ht, max_count: max_count} = energy_data

    # X range spans both histograms
    {e_x_min, _, _} = hd(he.bins)
    {_, e_x_max, _} = List.last(he.bins)
    {t_x_min, _, _} = hd(ht.bins)
    {_, t_x_max, _} = List.last(ht.bins)

    x_min = min(e_x_min, t_x_min)
    x_max = max(e_x_max, t_x_max)

    x_scale = Scale.linear(x_min, x_max, plot_left, plot_right)
    y_scale = Scale.linear(0, max_count, plot_bottom, plot_top)

    x_ticks = Scale.ticks(x_min, x_max, 4)
    y_ticks = Scale.ticks(0, max_count, 3)

    graph =
      Graph.build(font_size: 10)
      |> rect({w, h}, fill: Colors.panel_bg())
      |> text("Energy",
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

    # Draw energy histogram (amber, behind)
    graph = draw_bars(graph, he.bins, x_scale, y_scale, plot_bottom, Colors.energy_marginal(), 0.7)

    # Draw transition histogram (blue, in front)
    draw_bars(graph, ht.bins, x_scale, y_scale, plot_bottom, Colors.energy_transition(), 0.7)
  end

  defp draw_bars(graph, bins, x_scale, y_scale, plot_bottom, {r, g, b}, alpha) do
    color = {r, g, b, round(alpha * 255)}

    Enum.reduce(bins, graph, fn {left, right, count}, g ->
      px_left = x_scale.(left)
      px_right = x_scale.(right)
      px_top = y_scale.(count)
      bar_w = max(px_right - px_left - 1, 1)
      bar_h = plot_bottom - px_top

      if bar_h > 0 do
        rect(g, {bar_w, bar_h},
          fill: color,
          translate: {px_left, px_top}
        )
      else
        g
      end
    end)
  end
end
