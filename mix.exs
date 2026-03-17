defmodule DDMon.MixProject do
  use Mix.Project

  @ddm_debug Application.compile_env(:ddmon, :ddm_debug, "0")
  @ddm_report Application.compile_env(:ddmon, :ddm_report, false)

  def project do
    [
      app: :ddmon,
      version: "0.1.0",
      compilers: [:erlang] ++ Mix.compilers(),
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      erlc_paths: ["src"],
      erlc_include_path: "include",
      erlc_options: erlc_options(),
      deps: []
    ]
  end

  defp erlc_options do
    [
      :debug_info,
      if(@ddm_debug == "1", do: {:d, :DDM_DEBUG}),
      if(@ddm_report == true, do: {:d, :DDM_REPORT})
    ] |> Enum.reject(&is_nil/1)
  end

  def application do
    [
      extra_applications: [:logger],
    ]
  end
end
