class CheckWorker
  include Sidekiq::Worker
  include PerformAsyncInQueue

  sidekiq_options retry: 3

  sidekiq_retries_exhausted do |msg|
    Check.connection_pool.with_connection do |_|
      check = msg["args"].first
      check.update!(
        problem_summary: "Check failed",
        suggested_fix: "Speak to your system administrator.",
        link_errors: [],
        link_warnings: [
          "Could not complete the check."
        ],
        completed_at: Time.now,
      )
    end
  end

  def perform(check_id)
    check = Check.includes(:link, :batches).find(check_id)

    return trigger_callbacks(check) unless check.requires_checking?

    check.update!(started_at: Time.now)

    previous_checks = check.link.checks.reject { |c| c == check }

    report = HistoricalLinkChecker.new(check.link.uri, previous_checks).call

    check.update!(
      link_errors: report.errors,
      link_warnings: report.warnings,
      problem_summary: report.problem_summary,
      suggested_fix: report.suggested_fix,
      completed_at: Time.now
    )

    trigger_callbacks(check)
  end

  def trigger_callbacks(check)
    check.batches.where(webhook_triggered: false).each(&:trigger_webhook)
  end

  def self.run(check_id, priority: "high", synchronous: false)
    if synchronous
      self.new.perform(check_id)
    else
      queue = priority == "low" ? "checks_low" : "default"
      self.perform_async_in_queue(queue, check_id)
    end
  end
end
