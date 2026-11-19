require "csv"

module Teams
  # Shared CSV plumbing for the team exports.
  #
  # Two things a spreadsheet needs that CSV.generate doesn't do on its own:
  #
  # - A UTF-8 byte-order mark. Without it Excel reads the file as the system
  #   codepage, and Discord names / WoW realms are full of accents and emoji.
  # - Formula neutralising. Application answers are free text typed by people
  #   who aren't members yet; a cell beginning with = + - @ is executed as a
  #   formula when a lead opens the file. Prefixing a quote renders it as the
  #   literal text it was. Only strings are touched, so numbers stay numbers.
  module CsvExport
    BOM = "﻿".freeze
    FORMULA_PREFIX = /\A[=+\-@\t\r]/

    module_function

    def generate(headers, rows)
      BOM + CSV.generate do |csv|
        csv << headers
        rows.each { |row| csv << row.map { |value| neutralise(value) } }
      end
    end

    def neutralise(value)
      value.is_a?(String) && value.match?(FORMULA_PREFIX) ? "'#{value}" : value
    end

    def timestamp(time) = time&.utc&.iso8601

    def filename(team, kind) = "#{team.slug}-#{kind}-#{Date.current.iso8601}.csv"
  end
end
