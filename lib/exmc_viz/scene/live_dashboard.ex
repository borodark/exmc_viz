defmodule ExmcViz.Scene.LiveDashboard do
  @moduledoc """
  Live-updating dashboard scene for streaming MCMC samples.

  On init, starts a `StreamCoordinator` GenServer and a background
  `Task` running `Exmc.NUTS.Sampler.sample_stream/4`. As samples arrive,
  the coordinator batches them and sends `{:update_data, ...}` messages
  to this scene, which rebuilds the full graph (trace, histogram, ACF,
  summary) from the accumulated samples.

  The title bar shows progress: `"MCMC Live Sampling (N / total)"` during
  sampling, then `"(complete)"` when done.

  ## Lifecycle

  1. Scene `init` starts coordinator + sampler task
  2. Shows "warming up..." placeholder with variable names
  3. After 5+ samples arrive, rebuilds full dashboard on each flush
  4. On `:sampling_complete`, marks title as complete
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

  @row_height 200
  @title_height 40
  @col_gap 8
  @row_gap 8
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

    # Start sampling in a background task
    ir = opts[:ir]
    init_values = opts[:init_values] || %{}
    sampler_opts = opts[:sampler_opts] || []

    Task.start(fn ->
      Exmc.NUTS.Sampler.sample_stream(ir, coordinator_pid, init_values, sampler_opts)
    end)

    {:ok, scene}
  end

  @impl GenServer
  def handle_info({:update_data, all_samples, _all_stats, count, total}, scene) do
    # Only rebuild if we have enough samples
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
      Graph.build(font: :roboto, font_size: 12)
      |> rect({vw, vh}, fill: Colors.bg())
      |> text("MCMC Live Sampling — warming up...",
        fill: Colors.text(),
        font_size: 18,
        translate: {@col_gap, 26}
      )

    # Show variable name placeholders
    var_names
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {name, i}, g ->
      y = @title_height + i * 30 + 20

      text(g, name,
        fill: Colors.text_dim(),
        font_size: 14,
        translate: {@col_gap + 10, y}
      )
    end)
  end

  defp build_live_graph(scene, all_samples, count, total) do
    {vw, _vh} = scene.viewport.size

    # Build var_data from accumulated samples
    trace =
      Map.new(all_samples, fn {name, values} ->
        {name, Nx.tensor(values)}
      end)

    var_data_list = Prepare.from_trace(trace)

    # Column widths
    usable_w = vw - @col_gap * 5
    trace_w = round(usable_w * 0.33)
    hist_w = round(usable_w * 0.26)
    acf_w = round(usable_w * 0.21)
    summary_w = round(usable_w * 0.20)

    plot_h = @row_height - @row_gap

    status = if scene.assigns.complete, do: "complete", else: "#{count} / #{total}"
    title = "MCMC Live Sampling (#{status})"

    graph =
      Graph.build(font: :roboto, font_size: 12)
      |> rect({vw, @title_height + length(var_data_list) * @row_height + 20},
        fill: Colors.bg()
      )
      |> text(title,
        fill: Colors.text(),
        font_size: 18,
        translate: {@col_gap, 26}
      )

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
  end
end
