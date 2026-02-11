defmodule ExmcViz.Kino do
  @moduledoc """
  Kino + VegaLite integration for Livebook visualization.

  Requires `{:kino_vega_lite, "~> 0.1"}` in your Livebook dependencies.
  These functions return VegaLite specs (maps) that Kino renders inline.
  """

  alias ExmcViz.Data.Prepare

  @doc """
  Render a trace plot in Livebook.

  Returns a VegaLite spec (map) that Kino renders automatically.
  """
  def trace_plot(trace, opts \\ []) do
    var_data = Prepare.from_trace(trace)
    width = Keyword.get(opts, :width, 600)
    height = Keyword.get(opts, :height, 150)

    layers =
      Enum.map(var_data, fn vd ->
        data_points =
          vd.samples
          |> Enum.with_index()
          |> Enum.map(fn {v, i} -> %{"x" => i, "y" => v, "variable" => vd.name} end)

        %{
          "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
          "title" => vd.name,
          "width" => width,
          "height" => height,
          "data" => %{"values" => data_points},
          "mark" => %{"type" => "line", "strokeWidth" => 0.5},
          "encoding" => %{
            "x" => %{"field" => "x", "type" => "quantitative", "title" => "Sample"},
            "y" => %{"field" => "y", "type" => "quantitative", "title" => "Value"}
          }
        }
      end)

    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "vconcat" => layers
    }
  end

  @doc "Render a histogram in Livebook."
  def histogram(trace, opts \\ []) do
    var_data = Prepare.from_trace(trace)
    width = Keyword.get(opts, :width, 400)
    height = Keyword.get(opts, :height, 150)

    layers =
      Enum.map(var_data, fn vd ->
        data_points =
          Enum.map(vd.samples, fn v -> %{"value" => v, "variable" => vd.name} end)

        %{
          "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
          "title" => vd.name,
          "width" => width,
          "height" => height,
          "data" => %{"values" => data_points},
          "mark" => "bar",
          "encoding" => %{
            "x" => %{
              "field" => "value",
              "type" => "quantitative",
              "bin" => %{"maxbins" => 30}
            },
            "y" => %{"aggregate" => "count", "type" => "quantitative"}
          }
        }
      end)

    %{"$schema" => "https://vega.github.io/schema/vega-lite/v5.json", "vconcat" => layers}
  end

  @doc "Render a forest plot in Livebook."
  def forest_plot(trace, opts \\ []) do
    forest_data = Prepare.prepare_forest(trace)
    width = Keyword.get(opts, :width, 600)

    data_points =
      Enum.flat_map(forest_data, fn fd ->
        {lo94, hi94} = fd.hdi_94
        {lo50, hi50} = fd.hdi_50

        [
          %{"name" => fd.name, "lo" => lo94, "hi" => hi94, "type" => "94% HDI"},
          %{"name" => fd.name, "lo" => lo50, "hi" => hi50, "type" => "50% HDI"},
          %{"name" => fd.name, "lo" => fd.mean, "hi" => fd.mean, "type" => "mean"}
        ]
      end)

    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "title" => "Forest Plot",
      "width" => width,
      "height" => length(forest_data) * 40 + 40,
      "data" => %{"values" => data_points},
      "layer" => [
        %{
          "mark" => %{"type" => "rule"},
          "encoding" => %{
            "y" => %{"field" => "name", "type" => "nominal"},
            "x" => %{"field" => "lo", "type" => "quantitative"},
            "x2" => %{"field" => "hi"},
            "size" => %{
              "field" => "type",
              "type" => "nominal",
              "scale" => %{"range" => [1, 4, 0]},
              "legend" => nil
            },
            "color" => %{"field" => "type", "type" => "nominal"}
          }
        },
        %{
          "transform" => [%{"filter" => "datum.type == 'mean'"}],
          "mark" => %{"type" => "point", "filled" => true, "size" => 80},
          "encoding" => %{
            "y" => %{"field" => "name", "type" => "nominal"},
            "x" => %{"field" => "lo", "type" => "quantitative"},
            "color" => %{"value" => "white"}
          }
        }
      ]
    }
  end

  @doc "Render a pair/corner plot in Livebook."
  def pair_plot(trace, opts \\ []) do
    pair_data = Prepare.prepare_pairs(trace)
    cell_size = Keyword.get(opts, :cell_size, 150)

    var_names = pair_data.var_names
    n = length(hd(Map.values(pair_data.var_samples)))

    data_points =
      Enum.map(0..(n - 1), fn i ->
        Map.new(var_names, fn name -> {name, Enum.at(pair_data.var_samples[name], i)} end)
      end)

    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "title" => "Pair Plot",
      "data" => %{"values" => data_points},
      "repeat" => %{
        "row" => var_names,
        "column" => var_names
      },
      "spec" => %{
        "width" => cell_size,
        "height" => cell_size,
        "mark" => %{"type" => "point", "size" => 3, "opacity" => 0.3},
        "encoding" => %{
          "x" => %{"field" => %{"repeat" => "column"}, "type" => "quantitative"},
          "y" => %{"field" => %{"repeat" => "row"}, "type" => "quantitative"}
        }
      }
    }
  end
end
