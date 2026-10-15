module Api::V1
  class UploadsController < ApplicationController
    skip_before_action :authenticate_request

    ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp image/svg+xml].freeze
    MAX_SIZE_BYTES = 10.megabytes

    # GET /api/v1/uploads
    def index
      blobs = ActiveStorage::Blob.where(content_type: ALLOWED_TYPES).order(created_at: :desc)
      render json: blobs.map { |blob| blob_json(blob) }, status: :ok
    end

    # GET /api/v1/uploads/:id
    def show
      blob = ActiveStorage::Blob.find_by!(key: params[:id])
      render json: blob_json(blob), status: :ok
    rescue ActiveRecord::RecordNotFound
      raise ApiErrors::NotFoundError.new(message: "Image not found")
    end

    # POST /api/v1/uploads
    def create
      file = params[:file]

      raise ApiErrors::BadRequestError.new(message: "No file provided") if file.blank?
      validate_file!(file)

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: file.original_filename,
        content_type: file.content_type,
      )

      render json: blob_json(blob), status: :created
    end

    # DELETE /api/v1/uploads/:id
    def destroy
      blob = ActiveStorage::Blob.find_by!(key: params[:id])
      blob.purge
      head :no_content
    rescue ActiveRecord::RecordNotFound
      raise ApiErrors::NotFoundError.new(message: "Image not found")
    end

    private

    def blob_json(blob)
      {
        id: blob.key,
        filename: blob.filename,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        url: url_for(blob)
      }
    end

    def validate_file!(file)
      unless file.content_type.in?(ALLOWED_TYPES)
        raise ApiErrors::BadRequestError.new(
          message: "Invalid file type. Allowed: jpeg, png, gif, webp, svg",
        )
      end

      if file.size > MAX_SIZE_BYTES
        raise ApiErrors::BadRequestError.new(
          message: "File too large. Maximum size is 10 MB",
        )
      end
    end
  end
end
