# DDMon

**DDMon**, a monitoring tool for distributed black-box .deadlock
detection in Erlang and Elixir systems based on generic servers (`gen_server`).
We developed the tool as a drop-in replacement for generic servers with minimal
user intervention required. DDMon is the implementation and companion artifact
of our work accepted at OOPSLA 2025: "Correct Black-Box Monitors for Distributed
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
Elixir) based on the generic server (`gen_server`) behaviour. Intuitively, DDMon
acts as a drop-in replacement for the `gen_server` module of the OTP standard
library. At this stage, DDMon supports only the most commonly used features of
generic servers, i.e. the `call` and `cast` callbacks. Timeouts, deferred
responses (`no_reply`) and pooled calls through `reqids` are not covered by the
prototype yet.

To instrument an Erlang or Elixir program with DDMon monitors, you'll need to
follow these instructions, which depend on the language used to write each
`gen_server` instance:

- In the case of `gen_server`s implemented in Elixir, it suffices to add the
  following line at the top of the file, immediately after `use GenServer`:

  ```elixir
  alias :ddmon, as: GenServer
  ```

- In the case of `gen_server`s written in Erlang, you will need to
  find-and-replace all references to the `gen_server` module with `ddmon`. (This
  is necessary because Erlang lacks the `alias` directive provided by Elixir.)

### Application Architecture & Monitoring Registry

The `ddmon` dependency operates as a supervised **OTP Application** rather than just a passive code library. 

When your app starts, `ddmon` spins up its own supervision tree alongside your main application. 

- **The `mon_reg` Registry:** At the root of this tree, the `ddmon` application starts and supervises a centralized registry process called `mon_reg`.
- **Monitor Tracking:** Every time a worker process is wrapped by a `ddmon` proxy, that proxy registers itself with `mon_reg`. The registry acts as the source of truth, maintaining active references to all running `ddmon` monitors across the node to coordinate distributed deadlock detection.

## ⚠️ Important Limitation: `sys` Module Transparency
DDMon wraps your GenServers in a proxy process to detect deadlocks. Because of how the Erlang VM handles system messages, the proxy intercepts all calls to the `:sys` module.

If you call `:sys.get_state/1`, `:sys.get_status/1`, or `:sys.replace_state/2` on a monitored process, you will interact with the monitor's state, not the underlying worker process.

### How to handle this:
- In Production Logic: Do not use `:sys` for synchronization. Implement a custom synchronous `GenServer.call(pid, :sync)` in your worker, which DDMon will correctly forward.
- In Tests: If you need to flush a worker's mailbox or check its state, extract the raw worker PID first using `GenServer.call(pid, :"$get_child")` and pass that PID to the `:sys` module.

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
```

## Repository layout

This repository is structured to separate the core, distributable library from the academic and evaluation models used to test it. 
We also provide an example scenario showcasing the functionality of DDMon.

* `src/` & `lib/` – The core DDMon library source code.
* `example-system/` –  An example `gen_server`-based Elixir application which shows DDMon in a slightly more realistic local setup.
* `oopsla` - The OOPSLA'25 artifact. For more details see the `oopsla/README.md`.

## Prerequisites

- Erlang/OTP 26
- Elixir 1.14