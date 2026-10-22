module Api
  module V1
    class ReportsController < BaseController
      requires_module :reports
      before_action :require_admin!
      # Reportes completos fuera del plan dan 403 module_not_in_plan (spec 033, FR-007); el Resumen no falla, omite bloques.
      before_action(only: :income) { gate_reports!(:tickets, report_modules.income?) }
      before_action(only: :expenses) { gate_reports!(report_modules.payroll? ? :inventory : :employees, report_modules.expenses?) }
      before_action(only: :payroll) { gate_reports!(report_modules.payroll? ? :attendance : :employees, report_modules.attendance?) }
      before_action(only: :inventory) { gate_reports!(:inventory, report_modules.inventory?) }

      # GET /api/v1/reports/summary?from=2026-04-01&to=2026-04-30[&compare=true]
      # También acepta period=weekly|monthly|annual&date=2026-04-01 (si llegan from/to, mandan estos).
      def summary
        compare = params[:compare].to_s == "true"
        if params[:from].present? || params[:to].present?
          period = "custom"
          range  = from_to_range
        else
          period = params[:period].presence&.downcase || "monthly"
          range  = period_range(period, parse_date(params[:date]) || Date.current)
        end

        render json: Reports::SummaryService.new(current_company, range, period, compare: compare).call
      end

      # GET /api/v1/reports/income?from=2026-01-01&to=2026-04-30&group_by=day|week|month|year
      def income
        range    = from_to_range
        group_by = group_by_param

        render json: Reports::IncomeService.new(current_company, range, group_by).call
      end

      # GET /api/v1/reports/expenses?from=2026-01-01&to=2026-04-30&group_by=day|week|month|year
      def expenses
        range    = from_to_range
        group_by = group_by_param

        render json: Reports::ExpensesService.new(current_company, range, group_by).call
      end

      # GET /api/v1/reports/payroll?from=2026-04-01&to=2026-04-30
      def payroll
        range = from_to_range
        render json: Reports::PayrollService.new(current_company, range).call
      end

      # GET /api/v1/reports/inventory?from=2026-04-01&to=2026-04-30
      # Existencias y valor son de hoy; solo los movimientos usan el rango.
      def inventory
        render json: Reports::InventoryService.new(current_company, from_to_range).call
      end

      private

      def report_modules = @report_modules ||= Reports::Modules.new(current_company)

      def gate_reports!(key, allowed)
        return if allowed || current_user&.super_admin?

        raise_module_not_in_plan!(key)
      end

      def group_by_param
        value = params[:group_by].to_s.downcase
        Reports::PeriodKey::GROUPS.include?(value) ? value : "month"
      end

      def period_range(period, date)
        case period
        when "weekly"  then date.beginning_of_week(:monday)..date.end_of_week(:monday)
        when "annual"  then date.beginning_of_year..date.end_of_year
        else                date.beginning_of_month..date.end_of_month
        end
      end

      def from_to_range
        from = parse_date(params[:from]) || 1.month.ago.to_date
        to   = parse_date(params[:to])   || Date.current
        from.beginning_of_day..to.end_of_day
      end

      def parse_date(value)
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
