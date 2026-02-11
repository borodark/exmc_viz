defmodule ExmcViz.Cfd.Terminal do
  @moduledoc """
  Terminal dashboard for CFD metrics (orange-on-black).

  Fixed 2x4 layout of 24x80 panels. Subscribes to `ExmcViz.Cfd.Metrics`.
  """

  use GenServer

  @panel_w 80
  @panel_h 24
  @max_points 60
  @orange 208

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start do
    case Process.whereis(__MODULE__) do
      nil -> start_link([])
      _pid -> {:ok, __MODULE__}
    end
  end

  @impl true
  def init(_state) do
    ExmcViz.Cfd.Metrics.subscribe(self())
    state = %{u: [], p: [], halo: [], iter: 0, parts: %{}}
    render(state)
    {:ok, state}
  end

  @impl true
  def handle_info({:cfd_metrics, metric}, state) do
    iter = Map.get(metric, :iteration, state.iter + 1)
    res = Map.get(metric, :residuals, %{})
    u = Map.get(res, :U, last_or(state.u, 1.0))
    p = Map.get(res, :p, last_or(state.p, 1.0))
    halo = Map.get(metric, :halo_ms, last_or(state.halo, 0.0))
    parts = Map.get(metric, :partition_residuals, state.parts)

    state = %{
      state
      | iter: iter,
        u: push(state.u, u),
        p: push(state.p, p),
        halo: push(state.halo, halo),
        parts: parts
    }

    render(state)
    {:noreply, state}
  end

  defp push(list, val) do
    list
    |> List.insert_at(0, val)
    |> Enum.take(@max_points)
    |> Enum.reverse()
  end

  defp last_or([], default), do: default
  defp last_or(list, _default), do: List.last(list)

  defp render(state) do
    header = "CFD TERMINAL OBSERVABILITY"

    panels = [
      panel("Residuals U", spark(state.u)),
      panel("Residuals p", spark(state.p)),
      panel("Halo latency ms", spark(state.halo)),
      panel("Iteration", ["iter: #{state.iter}"]),
      panel("Partitions", part_lines(state.parts)),
      panel("U latest", [format(last_or(state.u, 0.0))]),
      panel("p latest", [format(last_or(state.p, 0.0))]),
      panel("halo latest", [format(last_or(state.halo, 0.0))])
    ]

    grid = layout(panels)

    IO.write([
      IO.ANSI.home(),
      IO.ANSI.clear(),
      IO.ANSI.black_background(),
      IO.ANSI.color(@orange),
      header_line(header),
      grid,
      IO.ANSI.reset()
    ])
  end

  defp header_line(text) do
    line = String.pad_trailing(text, @panel_w * 4)
    line <> "\n"
  end

  defp panel(title, body_lines) do
    top = "+" <> String.duplicate("-", @panel_w - 2) <> "+"
    title_line = "|" <> String.pad_trailing(" #{title}", @panel_w - 2) <> "|"

    body =
      body_lines
      |> Enum.map(&("|" <> String.pad_trailing(" " <> &1, @panel_w - 2) <> "|"))

    body =
      body ++
        List.duplicate(
          "|" <> String.duplicate(" ", @panel_w - 2) <> "|",
          @panel_h - 3 - length(body)
        )

    [top, title_line] ++ body ++ [top]
  end

  defp layout(panels) do
    rows = Enum.chunk_every(panels, 4, 4, [[], [], [], []]) |> Enum.take(2)

    rows
    |> Enum.map(fn row ->
      row_lines = Enum.map(row, & &1)

      0..(@panel_h - 1)
      |> Enum.map(fn idx ->
        row_lines
        |> Enum.map(fn panel -> Enum.at(panel, idx) end)
        |> Enum.join("")
      end)
      |> Enum.join("\n")
    end)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp spark(values) do
    if values == [] do
      ["(no data)"]
    else
      line = sparkline(values, @panel_w - 4)
      [line]
    end
  end

  defp sparkline(values, width) do
    vals = values |> Enum.take(-width)
    {min, max} = Enum.min_max(vals)
    range = if max == min, do: 1.0, else: max - min
    chars = String.graphemes(" .:-=+*#%@")

    vals
    |> Enum.map(fn v ->
      idx = trunc((v - min) / range * (length(chars) - 1))
      Enum.at(chars, idx)
    end)
    |> Enum.join()
  end

  defp part_lines(parts) when map_size(parts) == 0, do: ["(none)"]

  defp part_lines(parts) do
    parts
    |> Enum.sort()
    |> Enum.map(fn {id, res} ->
      "P#{id} U:#{format(Map.get(res, :U))} p:#{format(res.p)}"
    end)
    |> Enum.take(@panel_h - 3)
  end

  defp format(val) when is_number(val) do
    :erlang.float_to_binary(val, decimals: 4)
  end

  defp format(_), do: "-"
end
