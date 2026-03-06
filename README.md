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

## Configuration

DDMon provides compile-time configuration flags to enable debugging and reporting features. Under the hood, these flags inject specific Erlang compiler options (:DDM_DEBUG and :DDM_REPORT) when the library is compiled.

You can configure these flags in your host project's configuration file (e.g., `config/config.exs`):

**`config.exs`**
```elixir
import Config

config :ddmon,
  # Enables debugging output describing the monitor state change and deadlock reporting.
  # Accepts: "1" (enabled) or "0" (disabled, default).
  ddm_debug: "1",

  # Enables the deadlock reporting functionality.
  ddm_report: true
```

## Repository layout

This repository is structured to separate the core, distributable library from the academic and evaluation models used to test it. 
We also provide an example scenario showcasing the functionality of DDMon.

* `src/` – The core DDMon library source code.
* `example-system/` –  An example `gen_server`-based Elixir application which shows DDMon in a slightly more realistic local setup.
* `oopsla` - The OOPSLA'25 artifact. For more details see the `oopsla/README.md`.

## Prerequisites

- Erlang/OTP 26
- Elixir 1.14