require "csv"

module Payroll
  # CSV de una corrida (spec 037, FR-018): misma fuente que la pantalla, UTF-8 con BOM para que Excel lo abra bien.
  class CsvExport
    BOM = "﻿".freeze

    def self.call(run) = new(run).call

    def initialize(run)
      @run = run
    end

    def call
      BOM + CSV.generate do |csv|
        csv << %w[employee monthly_salary period_days days_paid salary bonuses deductions net status method reference paid_on]
                 .map { |key| I18n.t("payroll.csv.#{key}") }
        @run.payments.order(:employee_name).each do |p|
          csv << [ p.employee_name, pesos(p.monthly_salary_cents), p.period_days, p.days_paid, pesos(p.salary_cents),
                   pesos(p.bonus_cents), pesos(p.deduction_cents), pesos(p.net_cents),
                   I18n.t("payroll.status.#{p.status}"), p.payment_method && I18n.t("payroll.method.#{p.payment_method}"),
                   p.reference, p.paid_on ]
        end
        csv << [ I18n.t("payroll.csv.total"), nil, nil, nil, nil, nil, nil, pesos(@run.total_cents) ]
      end
    end

    private

    def pesos(cents) = format("%.2f", cents.to_i / 100.0)
  end
end
