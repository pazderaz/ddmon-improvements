defmodule MonitoredMailbox do

  require Logger

  use GenServer
  alias :ddmon, as: GenServer

  def start do
    GenServer.start(__MODULE__, :ok, name: __MODULE__)
  end

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_mail(message) do
    GenServer.cast(__MODULE__, {:mail, message})
  end

  def init(init_arg) do
    {:ok, init_arg}
  end

  def handle_cast({:mail, message}, state) do
    Logger.info("MonitoredMailbox received message: #{message}")
    {:noreply, state}
  end
end
