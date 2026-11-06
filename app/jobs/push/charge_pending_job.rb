module Push
  # Avisa «Por cobrar» (spec 058). Reintenta hasta 3 veces si Expo falla y luego lo registra como fallido para los jefes.
  class ChargePendingJob < ApplicationJob
    queue_as :default

    ATTEMPTS = 3

    retry_on ExpoClient::Transient, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      type, id, actor_id = job.arguments
      notice = ChargePending.new(subject_type: type, subject_id: id, actor_id: actor_id)
      subject = notice.subject
      next unless subject

      subject.company.user_companies.where(role: %i[owner admin]).where.not(user_id: actor_id).includes(:user).each do |membership|
        Deliver.record(company: subject.company, user: membership.user, kind: ChargePending::KIND, subject_key: notice.subject_key,
                       status: "failed", error: error.message, attempts: ATTEMPTS)
      end
    end

    def perform(subject_type, subject_id, actor_id = nil)
      ChargePending.call(subject_type: subject_type, subject_id: subject_id, actor_id: actor_id, attempt: executions)
    end
  end
end
