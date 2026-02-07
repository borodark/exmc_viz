defmodule ExmcViz.Draw.ScaleTest do
  use ExUnit.Case, async: true

  alias ExmcViz.Draw.Scale

  describe "linear/4" do
    test "maps domain endpoints to range endpoints" do
      scale = Scale.linear(0.0, 10.0, 0, 100)
      assert scale.(0.0) == 0
      assert scale.(10.0) == 100
    end

    test "maps midpoint correctly" do
      scale = Scale.linear(0.0, 10.0, 0, 100)
      assert scale.(5.0) == 50.0
    end

    test "y-axis flip: low values map to high pixels" do
      scale = Scale.linear(0.0, 10.0, 180, 20)
      # 0 -> bottom (180), 10 -> top (20)
      assert scale.(0.0) == 180
      assert scale.(10.0) == 20
    end

    test "handles negative domain" do
      scale = Scale.linear(-5.0, 5.0, 0, 200)
      assert scale.(-5.0) == 0
      assert scale.(0.0) == 100.0
      assert scale.(5.0) == 200
    end

    test "zero span returns midpoint" do
      scale = Scale.linear(5.0, 5.0, 0, 100)
      assert scale.(5.0) == 50.0
      assert scale.(999.0) == 50.0
    end
  end

  describe "ticks/3" do
    test "generates approximately target_count ticks" do
      ticks = Scale.ticks(0.0, 100.0, 5)
      assert length(ticks) >= 3
      assert length(ticks) <= 12

      # All values within domain
      Enum.each(ticks, fn {val, _label} ->
        assert val >= 0.0
        assert val <= 100.0
      end)
    end

    test "tick labels are strings" do
      ticks = Scale.ticks(0.0, 10.0, 5)

      Enum.each(ticks, fn {_val, label} ->
        assert is_binary(label)
      end)
    end

    test "single-value domain returns one tick" do
      ticks = Scale.ticks(5.0, 5.0, 5)
      assert length(ticks) == 1
      [{val, _label}] = ticks
      assert val == 5.0
    end

    test "nice step sizes" do
      # For range 0-100 with ~5 ticks, step should be 20
      step = Scale.nice_step(100.0, 5)
      assert step == 20.0
    end
  end
end
