defmodule Cocktail.Parser.ICalendar do
  @moduledoc """
  Create schedules from iCalendar format.

  TODO: write long description
  """

  alias Cocktail.{Schedule, Rule}

  @time_regex ~r/^:?;?(?:TZID=(.+?):)?(.*?)(Z)?$/
  @time_format "{YYYY}{0M}{0D}T{h24}{m}{s}"

  @doc ~S"""
  Parses a string in iCalendar format into a `t:Cocktail.Schedule.t/0`.

  ## Examples

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=DAILY;INTERVAL=2")
      ...> schedule
      #Cocktail.Schedule<Every 2 days>

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=WEEKLY")
      ...> schedule
      #Cocktail.Schedule<Weekly>

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR")
      ...> schedule
      #Cocktail.Schedule<Weekly on Mondays, Wednesdays and Fridays>

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;BYHOUR=10,12,14")
      ...> schedule
      #Cocktail.Schedule<Every 2 weeks on Mondays, Wednesdays and Fridays on the 10th, 12th and 14th hours of the day>
  """
  @spec parse(String.t) :: {:ok, Schedule.t} | {:error, term}
  def parse(i_calendar_string) when is_binary(i_calendar_string) do
    i_calendar_string
    |> String.trim
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> parse_lines(Schedule.new(Timex.now), 0) # FIXME: using Timex.now because shedules require a start time
  end

  @spec parse_lines([String.t], Schedule.t, non_neg_integer) :: {:ok, Schedule.t} | {:error, term}
  defp parse_lines([], schedule, _), do: {:ok, schedule}
  defp parse_lines([line | rest], schedule, index) do
    with {:ok, schedule} <- parse_line(line, schedule, index) do
      parse_lines(rest, schedule, index + 1)
    end
  end

  @spec parse_line(String.t, Schedule.t, non_neg_integer) :: {:ok, Schedule.t} | {:error, term}
  defp parse_line("DTSTART" <> time_string, schedule, index), do: parse_dtstart(time_string, schedule, index)
  defp parse_line("DTEND" <> time_string, schedule, index), do: parse_dtend(time_string, schedule, index)
  defp parse_line("RRULE:" <> options_string, schedule, index), do: parse_rrule(options_string, schedule, index)
  defp parse_line(_, _, index), do: {:error, {:unknown_eventprop, index}}

  @spec parse_dtstart(String.t, Schedule.t, non_neg_integer) :: {:ok, Schedule.t} | {:error, term}
  defp parse_dtstart(time_string, schedule, index) do
    with {:ok, datetime} <- parse_datetime(time_string) do
      {:ok, Schedule.set_start_time(schedule, datetime)}
    else
      {:error, term} -> {:error, {term, index}}
    end
  end

  @spec parse_dtend(String.t, Schedule.t, non_neg_integer) :: {:ok, Schedule.t} | {:error, term}
  defp parse_dtend(time_string, schedule, index) do
    with {:ok, datetime} <- parse_datetime(time_string) do
      {:ok, Schedule.set_end_time(schedule, datetime)}
    else
      {:error, term} -> {:error, {term, index}}
    end
  end

  @spec parse_rrule(String.t, Schedule.t, non_neg_integer) :: {:ok, Schedule.t} | {:error, term}
  defp parse_rrule(options_string, schedule, index) do
    with {:ok, options} <- parse_rrule_options_string(options_string) do
      rule = Rule.new(options)
      schedule = Schedule.add_recurrence_rule(schedule, rule)
      {:ok, schedule}
    else
      {:error, term} -> {:error, {term, index}}
    end
  end

  @spec parse_datetime(String.t) :: {:ok, Cocktail.time} | {:error, term}
  defp parse_datetime(time_string) do
    case Regex.run(@time_regex, time_string) do
      [_, "", time_string] ->
        parse_naive_datetime(time_string)
      [_, "", time_string, "Z"] ->
        parse_utc_datetime(time_string)
      [_, tzid, time_string] ->
        parse_zoned_datetime(time_string, tzid)
      _ ->
        {:error, :invalid_time_format}
    end
  end

  @spec parse_naive_datetime(String.t) :: {:ok, NaiveDateTime.t} | {:error, term}
  defp parse_naive_datetime(time_string), do: Timex.parse(time_string, @time_format)

  @spec parse_utc_datetime(String.t) :: {:ok, DateTime.t} | {:error, term}
  defp parse_utc_datetime(time_string), do: parse_zoned_datetime(time_string, "UTC")

  @spec parse_zoned_datetime(String.t, String.t) :: {:ok, DateTime.t} | {:error, term}
  defp parse_zoned_datetime(time_string, zone) do
    with {:ok, naive_datetime}  <- Timex.parse(time_string, @time_format),
         %DateTime{} = datetime <- Timex.to_datetime(naive_datetime, zone)
    do
      {:ok, datetime}
    end
  end

  @spec parse_rrule_options_string(String.t) :: {:ok, Cocktail.rule_options} | {:error, term}
  defp parse_rrule_options_string(options_string) do
    options_string
    |> String.split(";")
    |> parse_rrule_options([])
  end

  @spec parse_rrule_options([String.t], Cocktail.rule_options) :: {:ok, Cocktail.rule_options} | {:error, term}
  defp parse_rrule_options([], options), do: {:ok, options}
  defp parse_rrule_options([option_string | rest], options) do
    with {:ok, option} <- parse_rrule_option(option_string) do
      parse_rrule_options(rest, [option | options])
    end
  end

  @spec parse_rrule_option(String.t) :: {:ok, Cocktail.rule_option} | {:error, term}
  defp parse_rrule_option("FREQ=" <> frequency_string) do
    with {:ok, frequency} <- parse_frequency(frequency_string) do
      {:ok, {:frequency, frequency}}
    end
  end
  defp parse_rrule_option("INTERVAL=" <> interval_string) do
    with {:ok, interval} <- parse_interval(interval_string) do
      {:ok, {:interval, interval}}
    end
  end
  defp parse_rrule_option("COUNT=" <> count_string) do
    with {:ok, count} <- parse_count(count_string) do
      {:ok, {:count, count}}
    end
  end
  defp parse_rrule_option("UNTIL=" <> until_string) do
    with {:ok, until} <- parse_datetime(until_string) do
      {:ok, {:until, until}}
    end
  end
  defp parse_rrule_option("BYDAY=" <> days_string) do
    with {:ok, days} <- parse_days_string(days_string) do
      {:ok, {:days, days |> Enum.reverse}}
    end
  end
  defp parse_rrule_option("BYHOUR=" <> hours_string) do
    with {:ok, hours} <- parse_hours_string(hours_string) do
      {:ok, {:hours, hours |> Enum.reverse}}
    end
  end
  defp parse_rrule_option(_), do: {:error, :unknown_rrulparam}

  @spec parse_frequency(String.t) :: {:ok, Cocktail.frequency} | {:error, :invalid_frequency}
  defp parse_frequency("WEEKLY"), do: {:ok, :weekly}
  defp parse_frequency("DAILY"), do: {:ok, :daily}
  defp parse_frequency("HOURLY"), do: {:ok, :hourly}
  defp parse_frequency("MINUTELY"), do: {:ok, :minutely}
  defp parse_frequency("SECONDLY"), do: {:ok, :secondly}
  defp parse_frequency(_), do: {:error, :invalid_frequency}

  @spec parse_interval(String.t) :: {:ok, pos_integer} | {:error, :invalid_interval}
  defp parse_interval(interval_string) do
    with {integer, _}    <- Integer.parse(interval_string),
         {:ok, interval} <- validate_positive(integer)
    do
      {:ok, interval}
    else
      :error -> {:error, :invalid_interval}
    end
  end

  @spec parse_count(String.t) :: {:ok, pos_integer} | {:error, :invalid_count}
  defp parse_count(count_string) do
    with {integer, _} <- Integer.parse(count_string),
         {:ok, count} <- validate_positive(integer)
    do
      {:ok, count}
    else
      :error -> {:error, :invalid_count}
    end
  end

  @spec validate_positive(integer) :: {:ok, pos_integer} | :error
  defp validate_positive(n) when n > 0, do: {:ok, n}
  defp validate_positive(_), do: :error

  @spec parse_days_string(String.t) :: {:ok, [Cocktail.day_atom]} | {:error, :invalid_days}
  defp parse_days_string(""), do: {:error, :invalid_days}
  defp parse_days_string(days_string) do
    days_string
    |> String.split(",")
    |> parse_days([])
  end

  @spec parse_days([String.t], [Cocktail.day_atom]) :: {:ok, [Cocktail.day_atom]}
  defp parse_days([], days), do: {:ok, days}
  defp parse_days([day_string | rest], days) do
    with {:ok, day} <- parse_day(day_string) do
      parse_days(rest, [day | days])
    end
  end

  @spec parse_day(String.t) :: {:ok, Cocktail.day_atom} | {:error, :invalid_day}
  defp parse_day("SU"), do: {:ok, :sunday}
  defp parse_day("MO"), do: {:ok, :monday}
  defp parse_day("TU"), do: {:ok, :tuesday}
  defp parse_day("WE"), do: {:ok, :wednesday}
  defp parse_day("TH"), do: {:ok, :thursday}
  defp parse_day("FR"), do: {:ok, :friday}
  defp parse_day("SA"), do: {:ok, :saturday}
  defp parse_day(_), do: {:error, :invalid_day}

  @spec parse_hours_string(String.t) :: {:ok, [Cocktail.hour_number]} | {:error, :invalid_hours}
  defp parse_hours_string(""), do: {:error, :invalid_hours}
  defp parse_hours_string(hours_string) do
    hours_string
    |> String.split(",")
    |> parse_hours([])
  end

  @spec parse_hours([String.t], [Cocktail.hour_number]) :: {:ok, [Cocktail.hour_number]}
  defp parse_hours([], hours), do: {:ok, hours}
  defp parse_hours([hour_string | rest], hours) do
    with {:ok, hour} <- parse_hour(hour_string) do
      parse_hours(rest, [hour | hours])
    end
  end

  @spec parse_hour(String.t) :: {:ok, Cocktail.hour_number} | {:error, :invalid_hour}
  defp parse_hour(hour_string) do
    with {integer, _} <- Integer.parse(hour_string),
         {:ok, hour}  <- validate_hour(integer)
    do
      {:ok, hour}
    else
      :error -> {:error, :invalid_hour}
    end
  end

  @spec validate_hour(integer) :: {:ok, Cocktail.hour_number} | :error
  defp validate_hour(n) when n >= 0 and n < 24, do: {:ok, n}
  defp validate_hour(_), do: :error
end