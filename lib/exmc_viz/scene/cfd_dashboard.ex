defmodule ExmcViz.Scene.CfdDashboard do
  @moduledoc """
  CFD observability dashboard: residuals + halo latency + per-partition tiles.

  Driven by `ExmcViz.Cfd.Metrics` updates.
  """

  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.{Axis, Colors, Scale}

  @pad %{left: 80, right: 40, top: 40, bottom: 40}
  @max_points 200

  @impl Scenic.Scene
  def init(scene, _args, _opts) do
    {vw, vh} = scene.viewport.size

    ExmcViz.Cfd.Metrics.subscribe(self())

    state = %{
      width: vw,
      height: vh,
      iterations: [],
      u_vals: [],
      p_vals: [],
      halo_vals: [],
      partitions: %{}
    }

    graph = build_graph(state)

    scene
    |> assign(state)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl Scenic.Scene
  def handle_info({:cfd_metrics, metric}, scene) do
    state = update_state(scene.assigns, metric)
    graph = build_graph(state)

    scene
    |> assign(state)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp update_state(state, metric) do
    iter = Map.get(metric, :iteration, next_iter(state))
    residuals = Map.get(metric, :residuals, %{})

    u = Map.get(residuals, :U, last_or(state.u_vals, 1.0))
    p = Map.get(residuals, :p, last_or(state.p_vals, 1.0))
    halo = Map.get(metric, :halo_ms, last_or(state.halo_vals, 0.0))

    %{
      state
      | iterations: trim([iter | state.iterations]),
        u_vals: trim([u | state.u_vals]),
        p_vals: trim([p | state.p_vals]),
        halo_vals: trim([halo | state.halo_vals]),
        partitions: Map.get(metric, :partition_residuals, state.partitions)
    }
  end

  defp trim(list), do: list |> Enum.take(@max_points) |> Enum.reverse()

  defp last_or([], default), do: default
  defp last_or(list, _default), do: hd(list)

  defp next_iter(state) do
    case state.iterations do
      [] -> 1
      [last | _] -> last + 1
    end
  end

  defp build_graph(state) do
    Graph.build(font_size: 22)
    |> rect({state.width, state.height}, fill: Colors.bg())
    |> text("CFD Observability",
      fill: Colors.text(),
      font_size: 32,
      translate: {30, 32}
    )
    |> draw_residuals_panel(state)
    |> draw_halo_panel(state)
    |> draw_partitions(state)
  end

  defp draw_residuals_panel(graph, state) do
    w = div(state.width - 80, 2)
    h = div(state.height - 160, 2)

    x0 = 30
    y0 = 70

    graph
    |> rect({w, h}, fill: Colors.panel_bg(), translate: {x0, y0})
    |> text("Residuals", fill: Colors.text_dim(), translate: {x0 + 20, y0 + 24})
    |> draw_series_panel(state.iterations, state.u_vals, state.p_vals, {x0, y0, w, h})
  end

  defp draw_halo_panel(graph, state) do
    w = div(state.width - 80, 2)
    h = div(state.height - 160, 2)

    x0 = 50 + w
    y0 = 70

    graph
    |> rect({w, h}, fill: Colors.panel_bg(), translate: {x0, y0})
    |> text("Halo Latency (ms)",
      fill: Colors.text_dim(),
      translate: {x0 + 20, y0 + 24}
    )
    |> draw_single_series(state.iterations, state.halo_vals, {x0, y0, w, h}, Colors.energy_transition())
  end

  defp draw_series_panel(graph, iters, u_vals, p_vals, {x0, y0, w, h}) do
    plot_left = x0 + @pad.left
    plot_right = x0 + w - @pad.right
    plot_top = y0 + @pad.top
    plot_bottom = y0 + h - @pad.bottom

    {y_min, y_max} = range_with_pad(u_vals ++ p_vals, 0.001)
    {x_min, x_max} = range_with_pad(iters, 1.0)

    x_scale = Scale.linear(x_min, x_max, plot_left, plot_right)
    y_scale = Scale.linear(y_min, y_max, plot_bottom, plot_top)

    x_ticks = Scale.ticks(x_min, x_max, 4)
    y_ticks = Scale.ticks(y_min, y_max, 4)

    graph
    |> Axis.x_axis(x_scale, x_ticks, y: plot_bottom, x_start: plot_left, x_end: plot_right)
    |> Axis.y_axis(y_scale, y_ticks, x: plot_left, y_start: plot_top, y_end: plot_bottom)
    |> draw_path(iters, u_vals, x_scale, y_scale, Colors.default_line())
    |> draw_path(iters, p_vals, x_scale, y_scale, Colors.energy_transition())
  end

  defp draw_single_series(graph, iters, vals, {x0, y0, w, h}, color) do
    plot_left = x0 + @pad.left
    plot_right = x0 + w - @pad.right
    plot_top = y0 + @pad.top
    plot_bottom = y0 + h - @pad.bottom

    {y_min, y_max} = range_with_pad(vals, 0.1)
    {x_min, x_max} = range_with_pad(iters, 1.0)

    x_scale = Scale.linear(x_min, x_max, plot_left, plot_right)
    y_scale = Scale.linear(y_min, y_max, plot_bottom, plot_top)

    x_ticks = Scale.ticks(x_min, x_max, 4)
    y_ticks = Scale.ticks(y_min, y_max, 4)

    graph
    |> Axis.x_axis(x_scale, x_ticks, y: plot_bottom, x_start: plot_left, x_end: plot_right)
    |> Axis.y_axis(y_scale, y_ticks, x: plot_left, y_start: plot_top, y_end: plot_bottom)
    |> draw_path(iters, vals, x_scale, y_scale, color)
  end

  defp draw_path(graph, iters, vals, x_scale, y_scale, color) do
    points = Enum.zip(iters, vals)

    commands =
      points
      |> Enum.with_index()
      |> Enum.flat_map(fn {{x, y}, idx} ->
        px = x_scale.(x)
        py = y_scale.(y)

        if idx == 0 do
          [:begin, {:move_to, px, py}]
        else
          [{:line_to, px, py}]
        end
      end)

    if commands == [] do
      graph
    else
      path(graph, commands, stroke: {3, color})
    end
  end

  defp draw_partitions(graph, state) do
    x0 = 30
    y0 = div(state.height, 2) + 40
    w = state.width - 60
    h = state.height - y0 - 40

    graph =
      graph
      |> rect({w, h}, fill: Colors.panel_bg(), translate: {x0, y0})
      |> text("Per-partition residuals", fill: Colors.text_dim(), translate: {x0 + 20, y0 + 24})

    tiles = Enum.sort(state.partitions)
    tile_w = 240
    tile_h = 90
    gap = 20

    Enum.reduce(Enum.with_index(tiles), graph, fn {{part, res}, idx}, g ->
      col = rem(idx, max(div(w, tile_w + gap), 1))
      row = div(idx, max(div(w, tile_w + gap), 1))

      tx = x0 + 20 + col * (tile_w + gap)
      ty = y0 + 50 + row * (tile_h + gap)

      g
      |> rect({tile_w, tile_h}, fill: Colors.bg(), stroke: {2, Colors.axis()}, translate: {tx, ty})
      |> text("P#{part}", fill: Colors.text(), translate: {tx + 12, ty + 24})
      |> text("U: #{format_float(Map.get(res, :U))}",
        fill: Colors.text_dim(),
        translate: {tx + 12, ty + 52}
      )
      |> text("p: #{format_float(res.p)}",
        fill: Colors.text_dim(),
        translate: {tx + 12, ty + 76}
      )
    end)
  end

  defp range_with_pad([], pad), do: {0.0, max(1.0, pad)}

  defp range_with_pad(list, pad) do
    {min, max} = Enum.min_max(list)
    if min == max do
      {min - pad, max + pad}
    else
      {min - pad, max + pad}
    end
  end

  defp format_float(value) when is_number(value) do
    :erlang.float_to_binary(value, decimals: 4)
  end

  defp format_float(_), do: "-"
end
