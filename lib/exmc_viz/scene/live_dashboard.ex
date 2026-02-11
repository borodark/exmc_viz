defmodule ExmcViz.Scene.LiveDashboard do
  @moduledoc """
  Live-updating dashboard scene for streaming MCMC samples — dynamic layout.

  Fills the viewport evenly based on variable count. Priority order:
  1. Trace plot (50%) — mixing & convergence
  2. Histogram + ACF (30%) — posterior shape + autocorrelation
  3. Summary panel (20%) — reference numbers

  Title bar shows progress: `"MCMC Live Sampling (N / total)"`.
  """
  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.Colors
  alias ExmcViz.Data.Prepare

  alias ExmcViz.Component.{
    TracePlot,
    Histogram,
    AcfPlot,
    SummaryPanel
  }

  @title_height 60
  @gap 8
  @trace_frac 0.50
  @hist_acf_frac 0.30
  @min_samples_for_display 5

  @impl Scenic.Scene
  def init(scene, opts, _scene_opts) do
    num_samples = opts[:num_samples] || 1000
    var_names = opts[:var_names] || []

    graph = build_waiting_graph(scene, var_names)

    scene =
      scene
      |> assign(
        num_samples: num_samples,
        var_names: var_names,
        count: 0,
        complete: false
      )
      |> push_graph(graph)

    # Start coordinator pointing at this scene process
    {:ok, coordinator_pid} =
      ExmcViz.Stream.Coordinator.start_link(
        dashboard_pid: self(),
        num_samples: num_samples
      )

    # Publish coordinator PID for external mode access
    :persistent_term.put(:exmc_viz_coordinator, coordinator_pid)

    # Start sampling in a background task (skip in external mode when ir is nil)
    ir = opts[:ir]

    if ir do
      init_values = opts[:init_values] || %{}
      sampler_opts = opts[:sampler_opts] || []

      Task.start(fn ->
        Exmc.NUTS.Sampler.sample_stream(ir, coordinator_pid, init_values, sampler_opts)
      end)
    end

    {:ok, scene}
  end

  @impl GenServer
  def handle_info({:update_data, all_samples, _all_stats, count, total}, scene) do
    if count >= @min_samples_for_display do
      graph = build_live_graph(scene, all_samples, count, total)

      scene =
        scene
        |> assign(count: count)
        |> push_graph(graph)

      {:noreply, scene}
    else
      {:noreply, assign(scene, count: count)}
    end
  end

  @impl GenServer
  def handle_info(:sampling_complete, scene) do
    {:noreply, assign(scene, complete: true)}
  end

  defp build_waiting_graph(scene, var_names) do
    {vw, vh} = scene.viewport.size

    graph =
      Graph.build(font: :roboto, font_size: 14)
      |> rect({vw, vh}, fill: Colors.bg())
      |> text("MCMC Live Sampling — warming up...",
        fill: Colors.text(),
        font_size: 24,
        translate: {@gap, 36}
      )

    var_names
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {name, i}, g ->
      y = @title_height + i * 40 + 20

      text(g, name,
        fill: Colors.text_dim(),
        font_size: 18,
        translate: {@gap + 10, y}
      )
    end)
  end

  defp build_live_graph(scene, all_samples, count, total) do
    {vw, vh} = scene.viewport.size

    trace =
      Map.new(all_samples, fn {name, values} ->
        {name, Nx.tensor(values)}
      end)

    var_data_list = Prepare.from_trace(trace)
    n_vars = length(var_data_list)
    usable_w = vw - @gap * 2

    # Dynamic height allocation
    available = vh - @title_height
    var_gaps = n_vars * 2 * @gap
    var_section_h = if n_vars > 0, do: round((available - var_gaps) / n_vars), else: 0

    trace_h = round(var_section_h * @trace_frac)
    hist_acf_h = round(var_section_h * @hist_acf_frac)
    summary_h = var_section_h - trace_h - hist_acf_h - @gap * 2

    status = if scene.assigns.complete, do: "complete", else: "#{count} / #{total}"
    title = "MCMC Live Sampling (#{status})"

    graph =
      Graph.build(font: :roboto, font_size: 14)
      |> rect({vw, vh}, fill: Colors.bg())
      |> text(title,
        fill: Colors.text(),
        font_size: 24,
        translate: {@gap, 36}
      )

    var_data_list
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {vd, i}, g ->
      y_base = @title_height + i * (var_section_h + @gap * 2)

      # Priority 1: Trace plot — full width, biggest
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

      # Priority 3: Summary — full width, least important
      y_summary = y_hist + hist_acf_h + @gap

      SummaryPanel.add_to_graph(g, vd,
        id: :"summary_#{vd.name}",
        width: usable_w,
        height: summary_h,
        translate: {@gap, y_summary}
      )
    end)
  end
end
