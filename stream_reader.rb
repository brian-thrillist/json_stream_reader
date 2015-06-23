#!/usr/bin/env ruby

require 'pp'
require 'json'
require 'fileutils'

class AggregateRequestStats
  attr_reader(
    :http_method,
    :route,
    :count,
    :total_runtime,
    :num_slow,
    :slowest_time,
    :success_count,
    :fail_count
  )

  FILEPATH = '/tmp/the_goods.txt'

  def initialize(http_method, route)
    @http_method = http_method
    @route = route
    @count = 0
    @total_runtime = 0.0
    @num_slow = 0
    @slowest_time = 0.0
    @success_count = 0
    @fail_count = 0
  end

  def read_new_log(log_data)
    @count += 1

    runtime = log_data['runtime']
    @total_runtime += runtime
    @num_slow += 1 if runtime >= 1
    @slowest_time = [@slowest_time, runtime].max

    status = log_data['status']
    @success_count += 1 if status.between?(200,299)
    @fail_count += 1 if status.between?(300,999)
  end

  def avg_runtime
    self.total_runtime.to_f / self.count
  end

  def to_s
    output = "**** #{self.http_method} - #{self.route} ****\n"
    output += "response time total: #{self.total_runtime}\n"
    output += "num requests: #{self.count}\n"
    output += "avg time: #{total_runtime.to_f / self.count}\n"
    output += "num slow requests: #{self.num_slow}\n"
    output += "longest request time: #{self.slowest_time}\n"
    output += "percent slow: #{100 * self.num_slow.to_f / self.count}%\n"
    output += "num successful requests: #{self.success_count}\n"
    output += "num failed requests: #{self.fail_count}\n\n"
    output
  end

  def display
    puts self.to_s
  end

  def write_to_file
    File.open(self.class::FILEPATH, 'a') do |file|
      file.puts(self.to_s)
    end
  end
end

total_count = 0
total_runtime = 0
invalid_json_count = 0
phantom_count = 0
$all_stats = {}

trap("INT") do
  filepath = AggregateRequestStats::FILEPATH
  FileUtils::remove_file(filepath)
  $all_stats.each { |_, stats| stats.write_to_file }

  File.open(filepath, 'a') do |file|
    file.puts "**** Overall stats ****"
    file.puts "TOTAL COUNT: #{total_count}"
    file.puts "INVALID JSON COUNT: #{invalid_json_count}"
    file.puts "PHANTOM COUNT: #{phantom_count}"
    file.puts ""
    file.puts "PERCENT INVALID JSON: #{100 * invalid_json_count.to_f/total_count}%"
    file.puts "PERCENT PHANTOM: #{100 * phantom_count.to_f/total_count}%"
    file.puts ""
    file.puts "TOTAL RUNTIME: #{total_runtime}"
    file.puts "AVG RUNTIME: #{total_runtime.to_f/total_count}"
  end
end

ARGF.each do |line|
  begin
    total_count += 1
    data = JSON.parse(line.strip)
    http_method = data['method']
    route = data['route']

    if http_method.nil? || route.nil? || http_method == '' && route == ''
      phantom_count += 1
      next
    end

    total_runtime += data['runtime']
    stats = $all_stats["#{http_method}-#{route}"] ||= AggregateRequestStats.new(http_method, route)
    stats.read_new_log(data)
    stats.display
  rescue JSON::ParserError
    invalid_json_count += 1
  end
end

