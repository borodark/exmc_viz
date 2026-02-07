defmodule ExmcViz.Scene.Dashboard do
  @moduledoc """
  Main dashboard scene. Grid layout with one row per variable,
  each showing `[TracePlot | Histogram | AcfPlot | SummaryPanel]`.

  Accepts either a plain `[%VarData{}]` list (backward compatible) or a
  `{var_data_list, energy_data}` tuple. When energy data is present, an
  extra `EnergyPlot` row is appended below the variable rows.

  Column widths scale proportionally with viewport width (33/26/21/20%).
  Divergent samples appear as red dots on trace plots when stats are provided.
  """
  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.Colors

  alias ExmcViz.Component.{
    TracePlot,
    Histogram,
    AcfPlot,
    SummaryPanel,
    EnergyPlot
  }

  @row_height 200
  @title_height 40
  @col_gap 8
  @row_gap 8

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    {var_data_list, energy_data} = unpack_data(data)
    {vw, _vh} = scene.viewport.size

    # Column widths proportional to viewport
    usable_w = vw - @col_gap * 5
    trace_w = round(usable_w * 0.33)
    hist_w = round(usable_w * 0.26)
    acf_w = round(usable_w * 0.21)
    summary_w = round(usable_w * 0.20)

    plot_h = @row_height - @row_gap

    graph =
      Graph.build(font: :roboto, font_size: 12)
      |> rect({vw, @title_height + length(var_data_list) * @row_height + 20 + energy_row_height(energy_data)},
        fill: Colors.bg()
      )
      |> text("MCMC Trace Diagnostics",
        fill: Colors.text(),
        font_size: 18,
        translate: {@col_gap, 26}
      )

    graph =
      var_data_list
      |> Enum.with_index()
      |> Enum.reduce(graph, fn {vd, row}, g ->
        y = @title_height + row * @row_height

        col1_x = @col_gap
        col2_x = col1_x + trace_w + @col_gap
        col3_x = col2_x + hist_w + @col_gap
        col4_x = col3_x + acf_w + @col_gap

        g
        |> TracePlot.add_to_graph(vd,
          id: :"trace_#{vd.name}",
          width: trace_w,
          height: plot_h,
          translate: {col1_x, y}
        )
        |> Histogram.add_to_graph(vd,
          id: :"hist_#{vd.name}",
          width: hist_w,
          height: plot_h,
          translate: {col2_x, y}
        )
        |> AcfPlot.add_to_graph(vd,
          id: :"acf_#{vd.name}",
          width: acf_w,
          height: plot_h,
          translate: {col3_x, y}
        )
        |> SummaryPanel.add_to_graph(vd,
          id: :"summary_#{vd.name}",
          width: summary_w,
          height: plot_h,
          translate: {col4_x, y}
        )
      end)

    # Add energy plot row if energy data is available
    graph = add_energy_row(graph, energy_data, var_data_list, trace_w + hist_w + @col_gap, plot_h)

    scene
    |> assign(var_data_list: var_data_list, energy_data: energy_data)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  # Accept both tuple and plain list for backward compat
  defp unpack_data({var_data_list, energy_data}), do: {var_data_list, energy_data}
  defp unpack_data(var_data_list) when is_list(var_data_list), do: {var_data_list, nil}

  defp energy_row_height(nil), do: 0
  defp energy_row_height(_), do: @row_height

  defp add_energy_row(graph, nil, _var_data_list, _energy_w, _plot_h), do: graph

  defp add_energy_row(graph, energy_data, var_data_list, energy_w, plot_h) do
    y = @title_height + length(var_data_list) * @row_height

    EnergyPlot.add_to_graph(graph, energy_data,
      id: :energy_plot,
      width: energy_w,
      height: plot_h,
      translate: {@col_gap, y}
    )
  end
end
