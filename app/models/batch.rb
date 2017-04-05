class Batch < ApplicationRecord
  has_and_belongs_to_many :checks

  def to_h
    {
      id: id,
      status: status,
      links: checks.map(&:to_h),
      totals: {
        links: checks.count,
        ok: checks.each.count { |check| check.status == "ok" },
        caution: checks.each.count { |check| check.status == "caution" },
        broken: checks.each.count { |check| check.status == "broken" },
        pending: checks.each.count { |check| check.status == "pending" },
      },
      completed_at: ended_at,
    }.deep_symbolize_keys
  end

  def started_at
    checks.minimum(:started_at)
  end

  def ended_at
    checks.maximum(:ended_at) if completed?
  end

  def completed?
    checks.where(ended_at: nil).empty?
  end

  def status
    return "completed" if completed?
    return "in_progress"
  end
end
