require 'chronic_duration'

module ElapsedTime
  module_function

  def output(value)
    seconds = elapsed_seconds(value).round(2)
    return '0 sec' if seconds <= 0

    ChronicDuration.output(seconds) || '0 sec'
  end

  def label(value, prefix: '花費時間: ')
    "#{prefix}#{output(value)}"
  end

  def elapsed_seconds(value)
    return Time.now - value if value.is_a?(Time)

    value.to_f
  end
end
