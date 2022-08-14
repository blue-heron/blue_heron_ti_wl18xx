defmodule BlueHeron.Wilink8 do
  require Logger

  def init(path, gpio_bt_en, tty) do
    bts = BlueHeron.BTS.decode_file!(path)

    Circuits.UART.find_pids()
    |> Enum.each(fn {pid, tty_name} ->
      if tty_name == tty do
        Circuits.UART.stop(pid)
      end
    end)

    {:ok, pid} = Circuits.UART.start_link()
    {:ok, pin_ref} = Circuits.GPIO.open(gpio_bt_en, :output)
    Circuits.GPIO.write(pin_ref, 0)
    Process.sleep(500)
    Circuits.GPIO.write(pin_ref, 1)
    Process.sleep(200)

    opts = [
      speed: 115_200,
      framing: BlueHeronTransportUART.Framing,
      active: false,
      flow_control: :hardware
    ]

    :ok = Circuits.UART.open(pid, tty, opts)

    state = %{pin_ref: pin_ref, pid: pid, tty: tty, opts: opts, baud: 115_200, flow: 1}
    :ok = Circuits.UART.write(pid, <<1, 1, 10, 0>>)

    case Circuits.UART.read(pid, 5000) do
      {:ok, ""} ->
        {:error, :no_response}

      {:ok, <<_, _, _, _, 1, 10, _::binary>>} ->
        Logger.info("starting firmware upload")
        upload(bts.actions, state)
    end
  end

  def upload([%{type: :action_remarks, data: _remark} | rest], state) do
    upload(rest, state)
  end

  def upload(
        [
          %{type: :action_send_command, data: <<1, 64780::little-size(16), _::binary>> = _packet}
          | rest
        ],
        state
      ) do
    Logger.warn("Reached deep sleep command. ")
    upload(rest, state)
  end

  def upload(
        [
          %{type: :action_send_command, data: <<1, _opcode::little-size(16), _::binary>> = packet}
          | rest
        ],
        state
      ) do
    :ok = Circuits.UART.write(state.pid, packet)

    case Circuits.UART.read(state.pid, 1024) do
      {:ok, bin} when byte_size(bin) < 7 ->
        {:error, "TI Init command failed"}

      {:ok, <<_, _, _, _, _, _, resp, _::binary>>} when resp != 0 ->
        {:error, "TI Init command failed"}

      {:ok, _} ->
        upload(rest, state)

      error ->
        error
    end
  end

  def upload(
        [%{type: :action_wait_event, data: %{msec: _timeout, wait_data: _wait_data}} | rest],
        state
      ) do
    upload(rest, state)
  end

  def upload([%{type: :action_serial, data: %{baud: baud, flow: flow}} | rest], state) do
    Logger.warn("texas: changing baud rate to #{baud}, flow control to #{flow}")
    updated_opts = Keyword.put(state.opts, :speed, baud)
    Circuits.UART.flush(state.pid, :both)

    :ok =
      Circuits.UART.configure(state.pid,
        speed: baud,
        framing: BlueHeronTransportUART.Framing,
        active: false,
        flow_control: :hardware
      )

    upload(rest, %{state | opts: updated_opts})
  end

  def upload([], state) do
    Circuits.UART.flush(state.pid, :both)

    %BlueHeronTransportUART{
      device: state.tty,
      uart_pid: state.pid,
      uart_opts: state.opts
    }
  end
end
