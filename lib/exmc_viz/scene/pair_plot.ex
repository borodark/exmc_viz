defmodule ExmcViz.Scene.PairPlot do
  @moduledoc """
  Pair plot (corner plot) scene. Opened by `ExmcViz.pair_plot/2`.

  Lays out a k x k grid of cells, one per variable pair:

  - **Diagonal** — reuses `Histogram` component for marginal distribution
  - **Lower triangle** — `ScatterPlot` showing pairwise sample cloud
  - **Upper triangle** — `CorrelationCell` with Pearson r value

  Cell size is computed to fill the viewport with small gaps between cells.
  """
  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.Colors

  alias ExmcViz.Component.{
    Histogram,
    ScatterPlot,
    CorrelationCell
  }

  @pad 40
  @cell_gap 4

  @impl Scenic.Scene
  def init(scene, pair_data, _opts) do
    {vw, vh} = scene.viewport.size

    graph = build_graph(pair_data, vw, vh)

    scene
    |> assign(data: pair_data)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp build_graph(pair_data, vw, vh) do
    k = length(pair_data.var_names)
    usable = min(vw, vh) - @pad * 2
    cell_size = round((usable - (k - 1) * @cell_gap) / k)

    graph =
      Graph.build(font: :roboto, font_size: 12)
      |> rect({vw, vh}, fill: Colors.bg())
      |> text("Pair Plot",
        fill: Colors.text(),
        font_size: 18,
        translate: {10, 26}
      )

    names = pair_data.var_names

    # Build k x k grid
    for {row_name, row} <- Enum.with_index(names),
        {col_name, col} <- Enum.with_index(names),
        reduce: graph do
      g ->
        x = @pad + col * (cell_size + @cell_gap)
        y = @pad + row * (cell_size + @cell_gap)

        cond do
          # Diagonal: histogram
          row == col ->
            # Build a minimal VarData for the histogram component
            hist = pair_data.histograms[row_name]
            samples = pair_data.var_samples[row_name]
            n = length(samples)

            mini_vd = %ExmcViz.Data.VarData{
              name: row_name,
              samples: samples,
              n_samples: n,
              mean: 0.0,
              std: 0.0,
              quantiles: %{q5: 0.0, q25: 0.0, q50: 0.0, q75: 0.0, q95: 0.0},
              ess: 0.0,
              histogram: hist,
              acf: [1.0]
            }

            Histogram.add_to_graph(g, mini_vd,
              id: :"pair_hist_#{row_name}",
              width: cell_size,
              height: cell_size,
              translate: {x, y}
            )

          # Lower triangle: scatter plot
          row > col ->
            scatter_data = %{
              xs: pair_data.var_samples[col_name],
              ys: pair_data.var_samples[row_name],
              divergent_indices: nil
            }

            ScatterPlot.add_to_graph(g, scatter_data,
              id: :"pair_scatter_#{row_name}_#{col_name}",
              size: cell_size,
              translate: {x, y}
            )

          # Upper triangle: correlation
          true ->
            r = Map.get(pair_data.correlations, {row_name, col_name}, 0.0)

            CorrelationCell.add_to_graph(g, %{r: r},
              id: :"pair_corr_#{row_name}_#{col_name}",
              size: cell_size,
              translate: {x, y}
            )
        end
    end
  end
end
