defmodule ExmcViz.Scene.Dashboard do
  @moduledoc """
  Main dashboard scene — dynamic portrait layout.

  Fills the viewport evenly based on the number of variables. Within each
  variable section, space is allocated by watching priority:

  1. **Trace plot** (50%) — the main event, mixing & convergence
  2. **Histogram + ACF** (30%) — posterior shape + autocorrelation
  3. **Summary panel** (20%) — reference numbers

  Energy plot (if present) sits at the very bottom as the lowest-priority
  diagnostic. It claims 8% of total height; the rest is split among variables.
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
  @gap 8

  # Within each variable section, allocation by priority
  @trace_frac 0.50
  @hist_acf_frac 0.30
  # summary gets the remaining 0.20

  # Energy claims this fraction of total height (lowest priority, bottom)
  @energy_frac 0.08

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    {var_data_list, energy_data} = unpack_data(data)
    {vw, vh} = scene.viewport.size

    graph = build_graph(var_data_list, energy_data, vw, vh)

    scene
    |> assign(var_data_list: var_data_list, energy_data: energy_data)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp build_graph(var_data_list, energy_data, vw, vh) do
    usable_w = vw - @gap * 2
    n_vars = length(var_data_list)
    has_energy = energy_data != nil

    # Compute heights dynamically
    available = vh - @title_height
    energy_h = if has_energy, do: round(available * @energy_frac), else: 0
    vars_total = available - energy_h
    var_gaps = n_vars * 2 * @gap
    var_section_h = if n_vars > 0, do: round((vars_total - var_gaps) / n_vars), else: 0

    trace_h = round(var_section_h * @trace_frac)
    hist_acf_h = round(var_section_h * @hist_acf_frac)
    summary_h = var_section_h - trace_h - hist_acf_h - @gap * 2

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
        y_base = @title_height + i * (var_section_h + @gap * 2)

        # Priority 1: Trace plot — full width, biggest allocation
        g =
          TracePlot.add_to_graph(g, vd,
            id: :"trace_#{vd.name}",
            width: usable_w,
            height: trace_h,
            translate: {@gap, y_base}
          )

        # Priority 2: Histogram (left 55%) + ACF (right 45%)
        y_hist = y_base + trace_h + @gap
        hist_w = round(usable_w * 0.55)
        acf_w = usable_w - hist_w - @gap

        g =
          g
          |> Histogram.add_to_graph(vd,
            id: :"hist_#{vd.name}",
            width: hist_w,
            height: hist_acf_h,
            translate: {@gap, y_hist}
          )
          |> AcfPlot.add_to_graph(vd,
            id: :"acf_#{vd.name}",
            width: acf_w,
            height: hist_acf_h,
            translate: {@gap + hist_w + @gap, y_hist}
          )

        # Priority 3: Summary — full width, least important per-variable widget
        y_summary = y_hist + hist_acf_h + @gap

        SummaryPanel.add_to_graph(g, vd,
          id: :"summary_#{vd.name}",
          width: usable_w,
          height: summary_h,
          translate: {@gap, y_summary}
        )
      end)

    # Priority 4: Energy — very bottom, lowest priority diagnostic
    if has_energy do
      y_energy = vh - energy_h

      EnergyPlot.add_to_graph(graph, energy_data,
        id: :energy_plot,
        width: usable_w,
        height: energy_h,
        translate: {@gap, y_energy}
      )
    else
      graph
    end
  end

  defp unpack_data({var_data_list, energy_data}), do: {var_data_list, energy_data}
  defp unpack_data(var_data_list) when is_list(var_data_list), do: {var_data_list, nil}
end
