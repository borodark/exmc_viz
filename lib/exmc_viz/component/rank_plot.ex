defmodule ExmcViz.Component.RankPlot do
  @moduledoc """
  Rank histogram plot component.

  Shows per-chain rank histograms overlaid as step functions.
  Uniform distribution (dashed line) indicates good mixing.
  Deviations suggest convergence issues.
  """
  use Scenic.Component

  alias ExmcViz.Draw.{Colors, Scale}

  @default_width 350
  @default_height 180

  def validate(%ExmcViz.Data.RankData{} = data), do: {:ok, data}
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
    pad_left = 45
    pad_right = 10
    pad_top = 30
    pad_bottom = 25
    plot_w = width - pad_left - pad_right
    plot_h = height - pad_top - pad_bottom

    num_bins = data.num_bins
    max_count = data.rank_histograms |> List.flatten() |> Enum.max(fn -> 1 end)
    expected = Enum.sum(List.flatten(data.rank_histograms)) / (data.num_chains * num_bins)

    x_scale = Scale.linear(0, num_bins, pad_left, pad_left + plot_w)
    y_scale = Scale.linear(0, max_count * 1.1, pad_top + plot_h, pad_top)

    graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.rect({width, height}, fill: Colors.panel_bg())
      |> Scenic.Primitives.text(data.name <> " — Rank",
        fill: Colors.text(),
        font_size: 18,
        t: {pad_left, 18}
      )

    # Draw expected uniform line
    expected_y = y_scale.(expected)

    graph =
      graph
      |> Scenic.Primitives.line(
        {{pad_left, expected_y}, {pad_left + plot_w, expected_y}},
        stroke: {1, Colors.text_dim()}
      )

    # Draw per-chain rank histograms as step lines
    Enum.with_index(data.rank_histograms)
    |> Enum.reduce(graph, fn {counts, chain_idx}, graph ->
      color = Colors.chain_color(chain_idx)

      steps =
        Enum.flat_map(Enum.with_index(counts), fn {count, bin} ->
          x0 = x_scale.(bin)
          x1 = x_scale.(bin + 1)
          y = y_scale.(count)
          [{x0, y}, {x1, y}]
        end)

      case steps do
        [] ->
          graph

        [first | rest] ->
          cmds =
            [
              {:move_to, first.x || elem(first, 0), first.y || elem(first, 1)}
              | Enum.map(rest, fn {x, y} -> {:line_to, x, y} end)
            ]

          # Use simple line segments instead of path for reliability
          Enum.chunk_every(steps, 2, 1, :discard)
          |> Enum.reduce(graph, fn [{x0, y0}, {x1, y1}], g ->
            Scenic.Primitives.line(g, {{x0, y0}, {x1, y1}}, stroke: {2, color})
          end)
      end
    end)
  end
end
