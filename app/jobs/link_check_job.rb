class LinkCheckJob < ApplicationJob
  queue_as :default

  def perform(check, callback_uri = nil)
    return if check.started_at || check.ended_at

    check.update!(started_at: Time.now)

    report = LinkChecker.new(check.link.uri).call

    check.update!(
      link_errors: report.errors,
      link_warnings: report.warnings,
      ended_at: Time.now
    )

    WebhookJob.perform_now(check, callback_uri) if callback_uri
  end
end
