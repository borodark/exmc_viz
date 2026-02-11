defmodule ExmcViz.Export.SVG do
  @moduledoc """
  Export ExmcViz data as standalone SVG files.

  Converts the same data structures used by Scenic components
  into SVG markup. No Scenic dependency required for export.
  """

  alias ExmcViz.Data.VarData
  alias ExmcViz.Draw.{Colors, Scale}

  @doc """
  Export a trace summary as SVG.

  Returns an SVG string. Options:
  - `:width` — SVG width (default 1200)
  - `:height` — SVG height (default: auto based on num vars)
  - `:file` — if provided, writes to file and returns :ok
  """
  def trace_summary(var_data_list, opts \\ []) do
    width = Keyword.get(opts, :width, 1200)
    row_height = 200
    height = Keyword.get(opts, :height, length(var_data_list) * row_height + 60)

    svg =
      svg_header(width, height) <>
        svg_background(width, height) <>
        svg_title("MCMC Trace Summary", width) <>
        render_var_rows(var_data_list, width, row_height) <>
        svg_footer()

    maybe_write(svg, opts)
  end

  @doc "Export forest plot as SVG."
  def forest(forest_data_list, opts \\ []) do
    width = Keyword.get(opts, :width, 800)
    row_height = 40
    height = Keyword.get(opts, :height, length(forest_data_list) * row_height + 80)

    svg =
      svg_header(width, height) <>
        svg_background(width, height) <>
        svg_title("Forest Plot", width) <>
        render_forest(forest_data_list, width, row_height) <>
        svg_footer()

    maybe_write(svg, opts)
  end

  # --- SVG primitives ---

  defp svg_header(w, h) do
    ~s[<svg xmlns="http://www.w3.org/2000/svg" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}">\n]
  end

  defp svg_footer, do: "</svg>\n"

  defp svg_background(w, h) do
    {r, g, b} = Colors.bg()
    ~s[<rect width="#{w}" height="#{h}" fill="rgb(#{r},#{g},#{b})"/>\n]
  end

  defp svg_title(text, width) do
    {r, g, b} = Colors.text()
    x = div(width, 2)

    ~s[<text x="#{x}" y="35" fill="rgb(#{r},#{g},#{b})" font-size="22" text-anchor="middle" font-family="monospace">#{text}</text>\n]
  end

  defp render_var_rows(var_data_list, width, row_height) do
    var_data_list
    |> Enum.with_index()
    |> Enum.map(fn {vd, i} ->
      y_offset = 60 + i * row_height
      render_trace_row(vd, width, row_height, y_offset)
    end)
    |> Enum.join()
  end

  defp render_trace_row(%VarData{} = vd, width, row_height, y_offset) do
    # Trace plot (left 60%)
    trace_w = trunc(width * 0.6)
    trace_svg = render_trace_line(vd, trace_w, row_height - 20, 0, y_offset + 10)

    # Histogram (right 30%)
    hist_x = trace_w + 20
    hist_w = trunc(width * 0.28)
    hist_svg = render_histogram(vd, hist_w, row_height - 20, hist_x, y_offset + 10)

    # Label
    {r, g, b} = Colors.text()

    label =
      ~s[<text x="5" y="#{y_offset + 20}" fill="rgb(#{r},#{g},#{b})" font-size="14" font-family="monospace">#{vd.name}</text>\n]

    label <> trace_svg <> hist_svg
  end

  defp render_trace_line(%VarData{} = vd, width, height, x_off, y_off) do
    n = vd.n_samples
    if n < 2, do: "", else: do_render_trace(vd.samples, n, width, height, x_off, y_off)
  end

  defp do_render_trace(samples, n, width, height, x_off, y_off) do
    {lo, hi} = {Enum.min(samples), Enum.max(samples)}
    x_scale = Scale.linear(0, n - 1, x_off + 40, x_off + width - 5)
    y_scale = Scale.linear(lo, hi, y_off + height - 5, y_off + 5)

    points =
      samples
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        "#{Float.round(x_scale.(i) / 1, 1)},#{Float.round(y_scale.(v) / 1, 1)}"
      end)
      |> Enum.join(" ")

    {r, g, b} = Colors.default_line()

    ~s[<polyline points="#{points}" fill="none" stroke="rgb(#{r},#{g},#{b})" stroke-width="1" opacity="0.8"/>\n]
  end

  defp render_histogram(%VarData{} = vd, width, height, x_off, y_off) do
    bins = vd.histogram.bins
    max_count = vd.histogram.max_count
    if max_count == 0, do: "", else: do_render_hist(bins, max_count, width, height, x_off, y_off)
  end

  defp do_render_hist(bins, max_count, width, height, x_off, y_off) do
    {lo, _hi} =
      elem(hd(bins), 0) |> then(fn _ -> {elem(hd(bins), 0), elem(List.last(bins), 1)} end)

    hi = elem(List.last(bins), 1)
    x_scale = Scale.linear(lo, hi, x_off + 5, x_off + width - 5)
    y_scale = Scale.linear(0, max_count, y_off + height - 5, y_off + 5)

    {r, g, b} = Colors.hist_fill()

    Enum.map(bins, fn {left, right, count} ->
      x = Float.round(x_scale.(left) / 1, 1)
      bar_w = Float.round((x_scale.(right) - x_scale.(left)) / 1, 1)
      y_top = Float.round(y_scale.(count) / 1, 1)
      bar_h = Float.round((y_scale.(0) - y_top) / 1, 1)

      ~s[<rect x="#{x}" y="#{y_top}" width="#{bar_w}" height="#{bar_h}" fill="rgb(#{r},#{g},#{b})" opacity="0.7"/>\n]
    end)
    |> Enum.join()
  end

  defp render_forest(forest_data, width, row_height) do
    if forest_data == [], do: "", else: do_render_forest(forest_data, width, row_height)
  end

  defp do_render_forest(forest_data, width, row_height) do
    all_lo = Enum.map(forest_data, fn fd -> elem(fd.hdi_94, 0) end) |> Enum.min()
    all_hi = Enum.map(forest_data, fn fd -> elem(fd.hdi_94, 1) end) |> Enum.max()
    pad_left = 150
    x_scale = Scale.linear(all_lo, all_hi, pad_left, width - 20)

    forest_data
    |> Enum.with_index()
    |> Enum.map(fn {fd, i} ->
      y = 60 + i * row_height + div(row_height, 2)
      {lo94, hi94} = fd.hdi_94
      {lo50, hi50} = fd.hdi_50

      {tr, tg, tb} = Colors.forest_thin()
      {kr, kg, kb} = Colors.forest_thick()

      label =
        ~s[<text x="#{pad_left - 10}" y="#{y + 5}" fill="rgb(#{tr},#{tg},#{tb})" font-size="14" text-anchor="end" font-family="monospace">#{fd.name}</text>\n]

      thin =
        ~s[<line x1="#{Float.round(x_scale.(lo94) / 1, 1)}" y1="#{y}" x2="#{Float.round(x_scale.(hi94) / 1, 1)}" y2="#{y}" stroke="rgb(#{tr},#{tg},#{tb})" stroke-width="1"/>\n]

      thick =
        ~s[<line x1="#{Float.round(x_scale.(lo50) / 1, 1)}" y1="#{y}" x2="#{Float.round(x_scale.(hi50) / 1, 1)}" y2="#{y}" stroke="rgb(#{kr},#{kg},#{kb})" stroke-width="4"/>\n]

      dot =
        ~s[<circle cx="#{Float.round(x_scale.(fd.mean) / 1, 1)}" cy="#{y}" r="4" fill="white"/>\n]

      label <> thin <> thick <> dot
    end)
    |> Enum.join()
  end

  defp maybe_write(svg, opts) do
    case Keyword.get(opts, :file) do
      nil ->
        svg

      path ->
        File.write!(path, svg)
        :ok
    end
  end
end
