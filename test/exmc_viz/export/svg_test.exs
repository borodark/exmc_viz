defmodule ExmcViz.Export.SVGTest do
  use ExUnit.Case, async: true

  alias ExmcViz.Export.SVG
  alias ExmcViz.Data.{VarData, ForestData, Prepare}

  defp sample_var_data(name, n \\ 100) do
    :rand.seed(:exsss, 42)
    samples = Enum.map(1..n, fn _ -> :rand.normal() end)
    histogram = Prepare.compute_histogram(samples, 20)

    %VarData{
      name: name,
      samples: samples,
      n_samples: n,
      mean: Enum.sum(samples) / n,
      std: 1.0,
      quantiles: %{q5: -1.6, q25: -0.67, q50: 0.0, q75: 0.67, q95: 1.6},
      ess: 90.0,
      histogram: histogram,
      acf: Enum.map(0..10, fn i -> :math.exp(-i / 5.0) end),
      chains: nil,
      rhat: nil,
      divergent_indices: nil
    }
  end

  defp sample_forest_data do
    [
      %ForestData{name: "mu", mean: 2.5, hdi_94: {1.0, 4.0}, hdi_50: {1.8, 3.2}},
      %ForestData{name: "sigma", mean: 1.2, hdi_94: {0.5, 2.0}, hdi_50: {0.8, 1.5}}
    ]
  end

  describe "trace_summary" do
    test "output is valid SVG" do
      vd = [sample_var_data("mu"), sample_var_data("sigma")]
      svg = SVG.trace_summary(vd)

      assert String.starts_with?(svg, "<svg")
      assert String.ends_with?(String.trim(svg), "</svg>")
    end

    test "contains variable names" do
      vd = [sample_var_data("alpha"), sample_var_data("beta")]
      svg = SVG.trace_summary(vd)

      assert String.contains?(svg, "alpha")
      assert String.contains?(svg, "beta")
    end

    test "contains polyline for trace" do
      svg = SVG.trace_summary([sample_var_data("x")])
      assert String.contains?(svg, "<polyline")
    end

    test "contains rect for histogram bars" do
      svg = SVG.trace_summary([sample_var_data("x")])
      assert String.contains?(svg, "<rect")
    end

    test "file option writes to disk" do
      path = Path.join(System.tmp_dir!(), "test_trace_#{:rand.uniform(100_000)}.svg")
      vd = [sample_var_data("x")]
      result = SVG.trace_summary(vd, file: path)

      assert result == :ok
      assert File.exists?(path)
      content = File.read!(path)
      assert String.starts_with?(content, "<svg")
      File.rm!(path)
    end

    test "empty data produces valid minimal SVG" do
      svg = SVG.trace_summary([])
      assert String.starts_with?(svg, "<svg")
      assert String.ends_with?(String.trim(svg), "</svg>")
    end
  end

  describe "forest" do
    test "produces valid SVG with circles and lines" do
      fd = sample_forest_data()
      svg = SVG.forest(fd)

      assert String.starts_with?(svg, "<svg")
      assert String.contains?(svg, "<circle")
      assert String.contains?(svg, "<line")
    end

    test "contains variable names" do
      fd = sample_forest_data()
      svg = SVG.forest(fd)

      assert String.contains?(svg, "mu")
      assert String.contains?(svg, "sigma")
    end

    test "empty forest data produces valid SVG" do
      svg = SVG.forest([])
      assert String.starts_with?(svg, "<svg")
      assert String.ends_with?(String.trim(svg), "</svg>")
    end

    test "file option writes forest to disk" do
      path = Path.join(System.tmp_dir!(), "test_forest_#{:rand.uniform(100_000)}.svg")
      fd = sample_forest_data()
      result = SVG.forest(fd, file: path)

      assert result == :ok
      assert File.exists?(path)
      File.rm!(path)
    end
  end
end
