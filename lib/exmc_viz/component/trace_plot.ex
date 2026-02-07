defmodule ExmcViz.Component.TracePlot do
  @moduledoc """
  Trace line plot component. Shows sample values over iteration index.

  Multi-chain: one path per chain in different colors.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.{Scale, Axis, Colors}

  @default_width 350
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

    # Determine data ranges
    {y_min, y_max} = Enum.min_max(var_data.samples)
    y_pad = max((y_max - y_min) * 0.05, 0.01)
    y_min = y_min - y_pad
    y_max = y_max + y_pad

    x_scale = Scale.linear(0, var_data.n_samples - 1, plot_left, plot_right)
    y_scale = Scale.linear(y_min, y_max, plot_bottom, plot_top)

    x_ticks = Scale.ticks(0, var_data.n_samples - 1, 4)
    y_ticks = Scale.ticks(y_min, y_max, 4)

    Graph.build(font_size: 10)
    |> rect({w, h}, fill: Colors.panel_bg())
    |> text(var_data.name,
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
    |> draw_traces(var_data, x_scale, y_scale)
    |> draw_divergences(var_data, x_scale, y_scale)
  end

  defp draw_traces(graph, var_data, x_scale, y_scale) do
    case var_data.chains do
      nil ->
        draw_path(graph, var_data.samples, x_scale, y_scale, Colors.default_line())

      chains ->
        chains
        |> Enum.with_index()
        |> Enum.reduce(graph, fn {chain_samples, idx}, g ->
          color = Colors.chain_color(idx)
          draw_path(g, chain_samples, x_scale, y_scale, color)
        end)
    end
  end

  defp draw_path(graph, samples, x_scale, y_scale, color) do
    commands =
      samples
      |> Enum.with_index()
      |> Enum.flat_map(fn {val, i} ->
        px = x_scale.(i)
        py = y_scale.(val)

        if i == 0 do
          [:begin, {:move_to, px, py}]
        else
          [{:line_to, px, py}]
        end
      end)

    path(graph, commands, stroke: {1, color})
  end

  defp draw_divergences(graph, %{divergent_indices: nil}, _x_scale, _y_scale), do: graph

  defp draw_divergences(graph, var_data, x_scale, y_scale) do
    samples_arr = :array.from_list(var_data.samples)

    Enum.reduce(var_data.divergent_indices, graph, fn idx, g ->
      if idx >= 0 and idx < var_data.n_samples do
        val = :array.get(idx, samples_arr)
        px = x_scale.(idx)
        py = y_scale.(val)

        circle(g, 3,
          fill: Colors.divergence(),
          translate: {px, py}
        )
      else
        g
      end
    end)
  end
end
