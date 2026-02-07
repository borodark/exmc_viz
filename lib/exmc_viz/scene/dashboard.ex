defmodule ExmcViz.Scene.Dashboard do
  @moduledoc """
  Main dashboard scene — portrait layout for 4K displays.

  Each variable is stacked vertically:
  1. Trace plot (full width)
  2. Histogram (left 55%) + ACF (right 45%) side by side
  3. Summary panel (full width)

  When energy data is present, an energy plot row is appended at the bottom.
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

  @title_height 60
  @trace_h 300
  @hist_acf_h 250
  @summary_h 100
  @energy_h 300
  @gap 8
  @var_section_h @trace_h + @hist_acf_h + @summary_h + @gap * 2

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    {var_data_list, energy_data} = unpack_data(data)
    {vw, vh} = scene.viewport.size

    usable_w = vw - @gap * 2

    graph =
      Graph.build(font: :roboto, font_size: 14)
      |> rect({vw, vh}, fill: Colors.bg())
      |> text("MCMC Trace Diagnostics",
        fill: Colors.text(),
        font_size: 24,
        translate: {@gap, 36}
      )

    graph =
      var_data_list
      |> Enum.with_index()
      |> Enum.reduce(graph, fn {vd, i}, g ->
        y_base = @title_height + i * @var_section_h

        # Row 1: Trace plot — full width
        g =
          TracePlot.add_to_graph(g, vd,
            id: :"trace_#{vd.name}",
            width: usable_w,
            height: @trace_h,
            translate: {@gap, y_base}
          )

        # Row 2: Histogram (left 55%) + ACF (right 45%)
        y_hist = y_base + @trace_h + @gap
        hist_w = round(usable_w * 0.55)
        acf_w = usable_w - hist_w - @gap

        g =
          g
          |> Histogram.add_to_graph(vd,
            id: :"hist_#{vd.name}",
            width: hist_w,
            height: @hist_acf_h,
            translate: {@gap, y_hist}
          )
          |> AcfPlot.add_to_graph(vd,
            id: :"acf_#{vd.name}",
            width: acf_w,
            height: @hist_acf_h,
            translate: {@gap + hist_w + @gap, y_hist}
          )

        # Row 3: Summary — full width
        y_summary = y_hist + @hist_acf_h + @gap

        SummaryPanel.add_to_graph(g, vd,
          id: :"summary_#{vd.name}",
          width: usable_w,
          height: @summary_h,
          translate: {@gap, y_summary}
        )
      end)

    # Energy plot at bottom
    graph = add_energy_row(graph, energy_data, length(var_data_list), usable_w)

    scene
    |> assign(var_data_list: var_data_list, energy_data: energy_data)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp unpack_data({var_data_list, energy_data}), do: {var_data_list, energy_data}
  defp unpack_data(var_data_list) when is_list(var_data_list), do: {var_data_list, nil}

  defp add_energy_row(graph, nil, _n_vars, _w), do: graph

  defp add_energy_row(graph, energy_data, n_vars, usable_w) do
    y = @title_height + n_vars * @var_section_h + @gap

    EnergyPlot.add_to_graph(graph, energy_data,
      id: :energy_plot,
      width: usable_w,
      height: @energy_h,
      translate: {@gap, y}
    )
  end
end
