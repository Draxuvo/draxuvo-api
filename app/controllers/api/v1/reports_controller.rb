module Api
  module V1
    class ReportsController < BaseController
      requires_module :reports
      before_action :require_admin!

      # GET /api/v1/reports/summary?period=weekly|monthly|annual&date=2026-04-01
      def summary
        period = params[:period].presence&.downcase || "monthly"
        date   = parse_date(params[:date]) || Date.current
        range  = period_range(period, date)

        render json: Reports::SummaryService.new(current_company, range, period).call
      end

      # GET /api/v1/reports/income?from=2026-01-01&to=2026-04-30&group_by=week|month|year
      def income
        range    = from_to_range
        group_by = params[:group_by].presence&.downcase || "month"

        render json: Reports::IncomeService.new(current_company, range, group_by).call
      end

      # GET /api/v1/reports/expenses?from=2026-01-01&to=2026-04-30&group_by=week|month|year
      def expenses
        range    = from_to_range
        group_by = params[:group_by].presence&.downcase || "month"

        render json: Reports::ExpensesService.new(current_company, range, group_by).call
      end

      # GET /api/v1/reports/payroll?from=2026-04-01&to=2026-04-30
      def payroll
        range = from_to_range
        render json: Reports::PayrollService.new(current_company, range).call
      end

      private

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
