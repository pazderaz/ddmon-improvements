defmodule DDMon.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do

    children = [
      %{
        id: :mon_reg,
        start: {:mon_reg, :start_link, []}
      }
    ]

    opts = [strategy: :one_for_one, name: DDMon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
