# DDMon

**DDMon**, a monitoring tool for distributed black-box deadlock
detection in Erlang and Elixir systems based on generic servers (`gen_server`) and
generic state machines (`gen_statem`).

We developed the tool as a drop-in replacement for generic servers with minimal
user intervention required.

DDMon is originally a companion artifact
of the work accepted at OOPSLA 2025: "Correct Black-Box Monitors for Distributed
Deadlock Detection: Formalisation and Implementation"

## Installation

As a standalone library, DDMon can be added to your Elixir or Erlang projects as a dependency.

**For Elixir (`mix.exs`):**
```elixir
def deps do
  [
    {:ddmon, github: "pazderaz/ddmon-improvements"}
  ]
end
```

## Using DDMon to monitor a `gen_server`-based application

DDMon can monitor applications consisting of processes (written in Erlang or
Elixir) based on the generic server (`gen_server`) behaviour. DDMon
acts as a drop-in replacement for the `gen_server` and `gen_statem` modules of the OTP standard
library. At this stage, DDMon supports only the most commonly used features of
generic servers, i.e. the `call` and `cast` callbacks. Timeouts, deferred
responses (`no_reply`) and pooled calls through `reqids` are not yet convered.

To instrument an Erlang or Elixir program with DDMon monitors, you'll need to
follow these instructions, which depend on the language used to write each
`gen_server` instance:

- In the case of `gen_server`s implemented in Elixir, it suffices to add the
  following line at the top of the file, immediately after `use GenServer`:

  ```elixir
  alias :ddmon, as: GenServer
  ```

- For `gen_statem`, you apply the alias in the same way. However, you must
  additionally specify the type of the worker as part of the `start_link` opts:

  ```elixir
  alias :ddmon, as: GenStateMachine

  ...

  def start_link(...) do
    opts = [
      ddmon_opts: [
        worker_type: :gen_statem
      ]
    ]

    GenStateMachine.start_link(__MODULE__, [], opts)
  end
  ```

- In the case of modules written in Erlang, you will need to find-and-replace
  all references to the `gen_server`/`gen_statem` module with `ddmon`. (This
  is necessary because Erlang lacks the `alias` directive provided by Elixir.)

## ⚠️ Important Limitation: `sys` Module Transparency
DDMon wraps your GenServers in a proxy process to detect deadlocks. Because of how the Erlang VM handles system messages, the proxy intercepts all calls to the `:sys` module.

If you call `:sys.get_state/1`, `:sys.get_status/1`, or `:sys.replace_state/2` on a monitored process, you will interact with the monitor, not the underlying worker process.

### How to handle this:
- In Production Logic: Do not use `:sys` for synchronization. Implement a custom synchronous `GenServer.call(pid, :sync)` in your worker, which DDMon will correctly forward to the process.
- In Tests: If you need to flush a worker's mailbox or check its state, extract the raw worker PID first using `GenServer.call(pid, :"$get_child")` and pass that PID to the `:sys` module. The `DDMon.Test` module provides a helper function for this purpose

## Configuration

DDMon provides compile-time configuration flags to enable debugging and reporting features. Under the hood, these flags inject specific Erlang compiler options (:DDM_DEBUG and :DDM_REPORT) when the library is compiled.

You can configure these flags in your host project's configuration file (e.g., `config/config.exs`):

**`config.exs`**
```elixir
import Config

config :ddmon,
  # Enables full debugging output including monitor state change and deadlock reporting.
  # Accepts: "1" (enabled) or "0" (disabled, default).
  ddm_debug: "1",

  # Enables logging of deadlocks as warnings.
  ddm_report: true

  # Specify the default delay (ms) for passing the probes between monitors.
  # Increasing this value may result in reduced monitoring overhead, but
  # slower deadlock detection.
  # The default value is -1 for immediate delivery.
  default_probe_delay: 1000
```

## Repository layout

This repository is structured to separate the core, distributable library from the academic and evaluation models used to test it. 
We also provide an example scenario showcasing the functionality of DDMon.

* `src/`, `lib/` & `include/` - The core DDMon library source code.
* `test/` - Unit tests validating the basic deadlock monitoring functionality, based on scenarios from `examples/`.
* `examples/` - Example scenarios & simulations in Elixir which showcase the application of DDMon.
  * `factory/` - A `gen_server`-based simulation of a Microchip Factory.
  * `junction/` - A `gen_statem`-based simulation of a 4-way junction.
  * `showcase/` - Other scenarios showcasing the use of DDMon.
* `oopsla/` - The OOPSLA'25 artifact. For more details see the `oopsla/README.md`.

## Prerequisites

- Erlang/OTP 26
- Elixir 1.14