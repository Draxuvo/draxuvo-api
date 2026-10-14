# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
User.find_or_create_by!(email: "draxuvo@mailinator.com") do |user|
  user.assign_attributes(
    first_name: "Super",
    last_name: "Admin",
    second_last_name: "Draxuvo",
    phone: "+525512345678",
    password: "Draxuvo12345*",
    password_confirmation: "Draxuvo12345*",
    active: true,
    role: :super_admin,
  )
end

puts "Super admin creado/actualizado exitosamente!"


# ─────────────────────────────────────────
# UNITS
# ─────────────────────────────────────────
units_data = [
  { key: "pza",  name: "Pieza",       group: "cantidad", position: 1 },
  { key: "hr",   name: "Hora",        group: "tiempo",   position: 2 },
  { key: "kg",   name: "Kilogramo",   group: "peso",     position: 3 },
  { key: "lt",   name: "Litro",       group: "volumen",  position: 4 },
  { key: "mts",  name: "Metro",       group: "longitud", position: 5 },
  { key: "serv", name: "Servicio",    group: "servicio", position: 6 },
]
units_data.each do |data|
  Unit.find_or_create_by!(key: data[:key]) do |u|
    u.assign_attributes(name: data[:name], group: data[:group], position: data[:position])
  end
end
puts "  [ok] #{units_data.size} units"