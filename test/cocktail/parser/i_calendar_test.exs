defmodule Cocktail.Parser.ICalendarTest do
  use ExUnit.Case

  alias Cocktail.Rule
  alias Cocktail.Validation.{Interval, Day, HourOfDay}

  import Cocktail.Parser.ICalendar
  import Cocktail.TestSupport.DateTimeSigil

  doctest Cocktail.Parser.ICalendar, import: true

  test "parse a schedule with a naive time" do
    schedule_string =
      """
      DTSTART:20170810T160000
      """

    assert {:ok, schedule} = parse(schedule_string)
    assert schedule.start_time == ~N[2017-08-10 16:00:00]
  end

  test "parse a schedule with a UTC time" do
    schedule_string =
      """
      DTSTART:20170810T160000Z
      """

    assert {:ok, schedule} = parse(schedule_string)
    assert schedule.start_time == ~Y[2017-08-10 16:00:00 UTC]
  end

  test "parse a schedule with a zoned time" do
    schedule_string =
      """
      DTSTART;TZID=America/Los_Angeles:20170810T160000
      """

    assert {:ok, schedule} = parse(schedule_string)
    assert schedule.start_time == ~Y[2017-08-10 16:00:00 America/Los_Angeles]
  end

  test "parse a schedule with an end time" do
    schedule_string =
      """
      DTSTART:20170810T160000
      DTEND:20170810T170000
      """

    assert {:ok, schedule} = parse(schedule_string)
    assert schedule.start_time == ~N[2017-08-10 16:00:00]
    assert schedule.duration == 3600
  end

  for frequency <- [:weekly, :daily, :hourly, :minutely, :secondly] do
    test "parse a schedule with a single #{frequency} repeat rule" do
      schedule_string =
        ~s"""
        DTSTART:20170810T160000
        DTEND:20170810T170000
        RRULE:FREQ=#{unquote(frequency |> Atom.to_string |> String.upcase)}
        """

      assert {:ok, schedule} = parse(schedule_string)
      assert [ %Rule{} = rule ] = schedule.recurrence_rules
      assert rule.validations[:interval] == [ %Interval{type: unquote(frequency), interval: 1} ]
    end
  end

  test "parse a schedule with a weekly rrule with days and hours" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;BYHOUR=10,12,14
      """

    assert {:ok, schedule} = parse(schedule_string)
    assert [ %Rule{} = rule ] = schedule.recurrence_rules
    assert rule.validations[:hour_of_day] == [ %HourOfDay{hour: 10}, %HourOfDay{hour: 12}, %HourOfDay{hour: 14} ]
    assert rule.validations[:day] == [ %Day{day: 1}, %Day{day: 3}, %Day{day: 5} ]
  end

  ##########
  # Errors #
  ##########

  test "parse an empty string" do
    schedule_string = ""
    assert {:error, {:unknown_eventprop, 0}} = parse(schedule_string)
  end

  test "parse a string with an invalid line" do
    schedule_string = "invalid"
    assert {:error, {:unknown_eventprop, 0}} = parse(schedule_string)
  end

  test "parse a schedule with an incomplete DTSTART" do
    schedule_string = "DTSTART"
    assert {:error, {"Input datetime string cannot be empty!", 0}} = parse(schedule_string)
  end

  test "parse a schedule with an invalid DTSTART" do
    schedule_string = "DTSTART:invalid"
    assert {:error, {"Expected `1-4 digit year` at line 1, column 1.", 0}} = parse(schedule_string)
  end

  test "parse a schedule with an invalid timezone" do
    schedule_string =
      """
      DTSTART;TZID=invalid:20170810T160000
      """

      assert {:error, {{:invalid_timezone, "invalid"}, 0}} = parse(schedule_string)
  end

  test "parse a schedule with an invalid DTEND" do
    schedule_string =
      """
      DTSTART:20170810T160000
      DTEND:invalid
      """

    assert {:error, {"Expected `1-4 digit year` at line 1, column 1.", 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with an invalid frequency" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=invalid
      """

    assert {:error, {:invalid_frequency, 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with an invalid interval" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=DAILY;INTERVAL=invalid
      """

    assert {:error, {:invalid_interval, 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with an invalid count" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=DAILY;INTERVAL=2;COUNT=invalid
      """

    assert {:error, {:invalid_count, 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with an invalid until" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=invalid
      """

    assert {:error, {"Expected `1-4 digit year` at line 1, column 1.", 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with an invalid day" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,INVALID
      """

    assert {:error, {:invalid_day, 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with empty days" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=
      """

    assert {:error, {:invalid_days, 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with an invalid hour" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;BYHOUR=10,12,INVALID
      """

    assert {:error, {:invalid_hour, 1}} = parse(schedule_string)
  end

  test "parse a schedule with an rrule with empty hours" do
    schedule_string =
      """
      DTSTART:20170810T160000
      RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;BYHOUR=
      """

    assert {:error, {:invalid_hours, 1}} = parse(schedule_string)
  end
end