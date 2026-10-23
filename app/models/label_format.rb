# Formato de etiqueta propio de una empresa (spec 035): hoja con cuadrícula o rollo. Medidas en milímetros.
class LabelFormat < ApplicationRecord
  KINDS = %w[sheet roll].freeze
  MAX_PER_COMPANY = 20
  MAX_PAGE_MM = 500
  MIN_LABEL_MM = 10
  TOLERANCE = 0.01.to_d

  belongs_to :company

  before_validation { self.name = name.to_s.strip }
  validates :name, presence: true, length: { maximum: 60 }
  validates :name, uniqueness: { scope: :company_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :page_width_mm, :page_height_mm, numericality: { greater_than: 0, less_than_or_equal_to: MAX_PAGE_MM }
  validates :label_width_mm, :label_height_mm, numericality: { greater_than_or_equal_to: MIN_LABEL_MM }
  validates :margin_top_mm, :margin_left_mm, :gap_x_mm, :gap_y_mm, numericality: { greater_than_or_equal_to: 0 }
  validates :columns, :rows, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 20 }
  validate :roll_has_one_label
  validate :grid_fits_the_page
  validate :within_company_limit, on: :create

  def custom? = true
  def labels_per_page = columns * rows
  def paper = kind

  private

  def roll_has_one_label
    return unless kind == "roll"

    errors.add(:columns, :roll_single) if columns != 1
    errors.add(:rows, :roll_single) if rows != 1
  end

  # La cuadrícula completa (márgenes, etiquetas y separaciones) debe caber en la página.
  def grid_fits_the_page
    return if [ page_width_mm, page_height_mm, label_width_mm, label_height_mm, columns, rows ].any?(&:blank?)

    used_x = margin_left_mm.to_d + (columns * label_width_mm) + ((columns - 1) * gap_x_mm.to_d)
    used_y = margin_top_mm.to_d + (rows * label_height_mm) + ((rows - 1) * gap_y_mm.to_d)
    errors.add(:base, :grid_too_wide) if used_x > page_width_mm + TOLERANCE
    errors.add(:base, :grid_too_tall) if used_y > page_height_mm + TOLERANCE
  end

  def within_company_limit
    errors.add(:base, :formats_limit, count: MAX_PER_COMPANY) if company && company.label_formats.count >= MAX_PER_COMPANY
  end
end
