module Api
  module V1
    class ProfileController < BaseController
      ALLOWED_AVATAR_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
      MAX_AVATAR_SIZE      = 5.megabytes

      # Perfil y apariencia son de la persona: una empresa vencida no debe impedir guardarlos.
      skip_before_action :check_subscription!, only: %i[show update]

      # GET /api/v1/profile
      def show
        render json: UserSerializer.new(current_user).as_json
      end

      # PATCH /api/v1/profile
      def update
        current_user.update!(profile_params)
        render json: UserSerializer.new(current_user).as_json
      end

      # POST /api/v1/profile/avatar
      def upload_avatar
        file = params[:avatar]

        raise ApiErrors::BadRequestError.new(details: "Se requiere el archivo 'avatar'") if file.blank?

        validate_avatar!(file)

        current_user.avatar.purge if current_user.avatar.attached?
        current_user.avatar.attach(file)

        render json: {
          message:    "Avatar actualizado",
          avatar_url: url_for(current_user.avatar)
        }, status: :ok
      end

      # DELETE /api/v1/profile/avatar
      def remove_avatar
        raise ApiErrors::BadRequestError.new(details: "No tienes un avatar para eliminar") unless current_user.avatar.attached?

        current_user.avatar.purge
        render json: { message: "Avatar eliminado" }
      end

      private

      def profile_params
        params.require(:profile).permit(:first_name, :last_name, :phone, :description, :theme, :color_mode)
      end

      def validate_avatar!(file)
        unless file.content_type.in?(ALLOWED_AVATAR_TYPES)
          raise ApiErrors::BadRequestError.new(
            details: "Tipo de archivo no permitido. Usa: jpeg, png, gif o webp"
          )
        end

        if file.size > MAX_AVATAR_SIZE
          raise ApiErrors::BadRequestError.new(
            details: "La imagen es demasiado grande. Máximo 5 MB"
          )
        end
      end
    end
  end
end
