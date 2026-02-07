defmodule ExmcViz.Draw.Scale do
  @moduledoc """
  Linear scale mapping between data domain and pixel range.

  Y-axis convention: Scenic has y=0 at top, so Y scales map
  low values → high pixels (bottom) and high values → low pixels (top).
  """

  @doc """
  Create a linear scale function mapping [domain_min, domain_max] → [range_min, range_max].

  Returns `fn(value) -> pixel`.

  For Y-axis (flip): use `linear(data_min, data_max, bottom_px, top_px)`
  where bottom_px > top_px.
  """
  def linear(domain_min, domain_max, range_min, range_max)
      when is_number(domain_min) and is_number(domain_max) do
    span = domain_max - domain_min

    if span == 0 or span == 0.0 do
      mid = (range_min + range_max) / 2
      fn _value -> mid end
    else
      scale = (range_max - range_min) / span

      fn value ->
        range_min + (value - domain_min) * scale
      end
    end
  end

  @doc """
  Generate approximately `target_count` nice tick values spanning [domain_min, domain_max].

  Returns `[{value, label_string}, ...]`.
  """
  def ticks(domain_min, domain_max, target_count \\ 5) do
    span = domain_max - domain_min

    if span == 0 or span == 0.0 do
      [{domain_min, format_number(domain_min)}]
    else
      step = nice_step(span, target_count)
      first = Float.ceil(domain_min / step) * step
      last = Float.floor(domain_max / step) * step

      n_ticks = round((last - first) / step)

      Enum.map(0..n_ticks, fn i ->
        value = first + i * step
        {value, format_number(value)}
      end)
    end
  end

  @doc """
  Compute nice step size for tick generation.
  """
  def nice_step(span, target_count) do
    raw = span / max(target_count, 1)
    magnitude = :math.pow(10, Float.floor(:math.log10(abs(raw))))
    normalized = raw / magnitude

    nice =
      cond do
        normalized <= 1.0 -> 1.0
        normalized <= 2.0 -> 2.0
        normalized <= 5.0 -> 5.0
        true -> 10.0
      end

    nice * magnitude
  end

  defp format_number(value) when is_float(value) do
    abs_val = abs(value)

    cond do
      abs_val == 0.0 -> "0"
      abs_val >= 1000 -> :erlang.float_to_binary(value, decimals: 0)
      abs_val >= 1 -> :erlang.float_to_binary(value, decimals: 1)
      abs_val >= 0.01 -> :erlang.float_to_binary(value, decimals: 2)
      true -> :erlang.float_to_binary(value, decimals: 3)
    end
  end

  defp format_number(value) when is_integer(value) do
    Integer.to_string(value)
  end
end
