defmodule DDMon.Test do
  @moduledoc """
  Safety wrappers for testing processes monitored by DDMon.
  These functions automatically bypass the proxy to ensure you are
  syncing with the actual worker process.
  """

  @doc "Drop-in replacement for :sys.get_status/1"
  def get_status(server, timeout \\ 5000) do
    server
    |> unwrap_worker()
    |> :sys.get_status(timeout)
  end

  @doc "Drop-in replacement for :sys.get_state/1"
  def get_state(server, timeout \\ 5000) do
    server
    |> unwrap_worker()
    |> :sys.get_state(timeout)
  end

  # Transparently unwrap the PID. If the process is NOT a ddmon proxy,
  # it will safely fall back to returning the original PID.
  defp unwrap_worker(server) do
    try do
      GenServer.call(server, :"$get_child", 1000)
    catch
      # If it's a standard GenServer that doesn't understand :"$get_child",
      # it will exit. We catch that and just return the original server.
      :exit, _ -> server
    end
  end
end
