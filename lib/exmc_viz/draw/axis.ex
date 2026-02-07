defmodule ExmcViz.Draw.Axis do
  @moduledoc """
  Axis drawing helpers for Scenic graphs.

  Adds axis lines, tick marks, and labels to a Scenic graph.
  """

  import Scenic.Primitives, only: [line: 3, text: 3]

  alias ExmcViz.Draw.Colors

  @tick_size 4
  @label_font_size 10

  @doc """
  Draw an X-axis at the bottom of the plot area.

  Options:
  - `:y` — Y pixel position of the axis line (default: bottom of area)
  - `:x_start` — left pixel boundary
  - `:x_end` — right pixel boundary
  """
  def x_axis(graph, scale_fn, ticks, opts \\ []) do
    y = opts[:y] || 0
    x_start = opts[:x_start] || 0
    x_end = opts[:x_end] || 300

    # Axis line
    graph =
      line(graph, {{x_start, y}, {x_end, y}}, stroke: {1, Colors.axis()})

    # Ticks and labels
    Enum.reduce(ticks, graph, fn {value, label}, g ->
      x = scale_fn.(value)

      g
      |> line({{x, y}, {x, y + @tick_size}}, stroke: {1, Colors.axis()})
      |> text(label,
        fill: Colors.text_dim(),
        font_size: @label_font_size,
        text_align: :center,
        translate: {x, y + @tick_size + 10}
      )
    end)
  end

  @doc """
  Draw a Y-axis at the left of the plot area.

  Options:
  - `:x` — X pixel position of the axis line
  - `:y_start` — top pixel boundary
  - `:y_end` — bottom pixel boundary
  """
  def y_axis(graph, scale_fn, ticks, opts \\ []) do
    x = opts[:x] || 0
    y_start = opts[:y_start] || 0
    y_end = opts[:y_end] || 180

    # Axis line
    graph =
      line(graph, {{x, y_start}, {x, y_end}}, stroke: {1, Colors.axis()})

    # Ticks and labels
    Enum.reduce(ticks, graph, fn {value, label}, g ->
      y = scale_fn.(value)

      g
      |> line({{x - @tick_size, y}, {x, y}}, stroke: {1, Colors.axis()})
      |> text(label,
        fill: Colors.text_dim(),
        font_size: @label_font_size,
        text_align: :right,
        translate: {x - @tick_size - 2, y + 3}
      )
    end)
  end
end
