defmodule ExmcViz.Scene.Forest do
  @moduledoc """
  Forest plot scene. Wraps `ForestPlot` component in a full-window layout
  with title bar. Opened by `ExmcViz.forest_plot/2`.
  """
  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ExmcViz.Draw.Colors
  alias ExmcViz.Component.ForestPlot

  @title_height 40

  @impl Scenic.Scene
  def init(scene, forest_data_list, _opts) do
    {vw, vh} = scene.viewport.size

    graph =
      Graph.build(font: :roboto, font_size: 12)
      |> rect({vw, vh}, fill: Colors.bg())
      |> text("Forest Plot",
        fill: Colors.text(),
        font_size: 18,
        translate: {10, 26}
      )
      |> ForestPlot.add_to_graph(forest_data_list,
        id: :forest_plot,
        width: vw - 20,
        height: vh - @title_height - 10,
        translate: {10, @title_height}
      )

    scene
    |> assign(data: forest_data_list)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end
end
