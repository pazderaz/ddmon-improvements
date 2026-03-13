defmodule Receiver do
  use GenServer
  alias :ddmon, as: GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, nil}
  end

  @impl true
  def handle_call(:do_work, _from, state) do
    {:reply, :work_done, state}
  end
end

defmodule Sender do
  use GenServer
  alias :ddmon, as: GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, nil}
  end

  def trigger_call() do
    GenServer.cast(__MODULE__, :trigger_call)
  end

  @impl true
  def handle_cast(:trigger_call, state) do
    GenServer.call(Receiver, :do_work)
    {:noreply, state}
  end
end
