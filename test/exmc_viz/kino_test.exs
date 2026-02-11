defmodule ExmcViz.KinoTest do
  use ExUnit.Case, async: true

  alias ExmcViz.Kino, as: K

  defp sample_trace do
    :rand.seed(:exsss, 42)

    %{
      "mu" => Nx.tensor(Enum.map(1..100, fn _ -> :rand.normal() * 2 + 3 end)),
      "sigma" => Nx.tensor(Enum.map(1..100, fn _ -> abs(:rand.normal()) + 0.5 end))
    }
  end

  describe "trace_plot" do
    test "returns map with $schema key" do
      spec = K.trace_plot(sample_trace())
      assert is_map(spec)
      assert Map.has_key?(spec, "$schema")
    end

    test "contains vconcat with per-variable layers" do
      spec = K.trace_plot(sample_trace())
      assert is_list(spec["vconcat"])
      assert length(spec["vconcat"]) == 2
    end

    test "each layer has data points" do
      spec = K.trace_plot(sample_trace())

      for layer <- spec["vconcat"] do
        assert is_map(layer["data"])
        assert is_list(layer["data"]["values"])
        assert length(layer["data"]["values"]) == 100
      end
    end
  end

  describe "histogram" do
    test "returns map with vconcat key" do
      spec = K.histogram(sample_trace())
      assert is_map(spec)
      assert Map.has_key?(spec, "vconcat")
    end

    test "each layer uses bar mark with binning" do
      spec = K.histogram(sample_trace())

      for layer <- spec["vconcat"] do
        assert layer["mark"] == "bar"
        assert layer["encoding"]["x"]["bin"] == %{"maxbins" => 30}
      end
    end
  end

  describe "forest_plot" do
    test "data points contain name, lo, hi fields" do
      spec = K.forest_plot(sample_trace())
      assert is_map(spec)

      points = spec["data"]["values"]
      assert is_list(points)

      for point <- points do
        assert Map.has_key?(point, "name")
        assert Map.has_key?(point, "lo")
        assert Map.has_key?(point, "hi")
      end
    end

    test "has two layers (rules + points)" do
      spec = K.forest_plot(sample_trace())
      assert length(spec["layer"]) == 2
    end
  end

  describe "pair_plot" do
    test "has repeat spec structure" do
      spec = K.pair_plot(sample_trace())
      assert is_map(spec["repeat"])
      assert is_list(spec["repeat"]["row"])
      assert is_list(spec["repeat"]["column"])
      assert spec["repeat"]["row"] == spec["repeat"]["column"]
    end

    test "data points have all variable keys" do
      spec = K.pair_plot(sample_trace())
      points = spec["data"]["values"]
      assert is_list(points)

      first = hd(points)
      assert Map.has_key?(first, "mu")
      assert Map.has_key?(first, "sigma")
    end
  end

  describe "single variable trace" do
    test "all functions handle single-variable trace" do
      trace = %{"x" => Nx.tensor(Enum.map(1..50, fn _ -> :rand.normal() end))}

      assert is_map(K.trace_plot(trace))
      assert is_map(K.histogram(trace))
      assert is_map(K.forest_plot(trace))
      assert is_map(K.pair_plot(trace))
    end
  end
end
