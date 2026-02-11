defmodule ExmcViz.Cfd.MetricsSocket do
  @moduledoc """
  TCP server that accepts CFD metrics as Erlang terms.

  Payloads must be `:erlang.term_to_binary/1` encoded and length-framed
  with a 4-byte big-endian size (packet: 4).
  """

  use GenServer

  def start_link(opts) do
    port = Keyword.get(opts, :port, 4100)
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port) do
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: 4, active: false, reuseaddr: true])

    state = %{listen: socket, port: port}
    Process.send_after(self(), :accept, 0)
    {:ok, state}
  end

  @impl true
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.listen) do
      {:ok, client} ->
        Task.start(fn -> serve(client) end)
        Process.send_after(self(), :accept, 0)
        {:noreply, state}

      {:error, _} ->
        Process.send_after(self(), :accept, 1000)
        {:noreply, state}
    end
  end

  defp serve(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, bin} ->
        case safe_decode(bin) do
          {:ok, metric} when is_map(metric) ->
            ExmcViz.Cfd.Metrics.publish(metric)

          _ ->
            :ok
        end

        serve(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp safe_decode(bin) do
    try do
      {:ok, :erlang.binary_to_term(bin)}
    rescue
      _ -> {:error, :invalid_term}
    end
  end
end
