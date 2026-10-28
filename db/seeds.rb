# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
# La contraseña del super admin viene de SUPER_ADMIN_PASSWORD: obligatoria en producción y con un
# valor local por defecto en desarrollo (spec 004, R15). Solo se usa al crearlo.
super_admin_password =
  if Rails.env.production?
    ENV.fetch("SUPER_ADMIN_PASSWORD")
  else
    ENV.fetch("SUPER_ADMIN_PASSWORD", "SuperAdmin12345*")
  end

User.find_or_create_by!(email: "draxuvo@mailinator.com") do |user|
  user.assign_attributes(
    first_name: "Super",
    last_name: "Admin",
    second_last_name: "Draxuvo",
    phone: "+525512345678",
    password: super_admin_password,
    password_confirmation: super_admin_password,
    active: true,
    role: :super_admin,
  )
end

puts "Super admin creado/actualizado exitosamente!"


# ─────────────────────────────────────────
# UNITS
# ─────────────────────────────────────────
Unit.ensure_catalog!
puts "  [ok] #{Unit::CATALOG.size} units"
load Rails.root.join("db/seeds/demo.rb") if Rails.env.development?
