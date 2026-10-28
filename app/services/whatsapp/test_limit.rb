module Whatsapp
  # Límite de mensajes de prueba (spec 047): 5 por hora por super admin. Se cuenta con el historial (`test_sent`), así
  # que no hay otro contador que pueda desfasarse.
  module TestLimit
    PER_HOUR = 5

    def self.remaining(user)
      used = WhatsappEvent.where(user_id: user.id, action: "test_sent").where(created_at: 1.hour.ago..).count
      [ PER_HOUR - used, 0 ].max
    end
  end
end
